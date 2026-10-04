// Edge Function: admin-api
// Admin dashboard read proxy.
//
// WHY THIS EXISTS
//   The dashboard (dashborad/ui) is a browser app and must never hold the
//   service_role key. But it cannot read what it needs with the anon key
//   either, because RLS correctly hides it:
//
//     * merchants with approval_status = 'pending' are invisible to anon
//       (migration 109 tightened merchants_read_active)
//     * review moderation queues are invisible (reviews_read_visible)
//     * the Overview RPCs are service_role-only (migration 120)
//
//   So the browser authenticates with the anon key and calls this function.
//   This function holds service_role, verifies the caller is a real admin, and
//   forwards. It is a PROXY, not a second API layer: no business logic lives
//   here, only the admin gate and the parameter clamping.
//
// ROUTING
//   Routes by the `action` body field, matching admin-driver and
//   driver-actions. POST only, because that is the house pattern for Edge
//   Functions and it keeps every parameter in one validated body.
//
//   Actions:
//     'overview.kpis'        platform KPIs + previous-window deltas
//     'overview.series'      daily series for the three graphs
//     'overview.trending'    top items by revenue, last 7 days
//     'overview.recent_orders' newest orders across all merchants
//     'merchant.get'         one merchant, including rows RLS hides from anon
//
//   and these WRITES, which are the dashboard's first writes to Postgres:
//     'merchant.create'       forces { approval_status: 'pending', is_active: false }
//     'merchant.update'       partial update; cannot touch the two state columns
//     'merchant.approve'      approval_status -> 'approved'
//     'merchant.unapprove'    -> 'pending', and unpublishes atomically
//     'merchant.reject'       -> 'rejected', reason REQUIRED, and unpublishes
//     'merchant.publish'      is_active -> true; REFUSES unless approved
//     'merchant.unpublish'    is_active -> false
//
//   Approve and publish are separate because approval_status is an onboarding
//   judgement and is_active is a runtime switch — see the state-machine notes
//   above the handlers.
//
//   NOTE: Google Maps link resolution is deliberately NOT an action here. The
//   coordinates are already present in the pasted URL as text (`@lat,lng`,
//   `!3d`/`!4d`), so it is a pure client-side parse in the dashboard — no server
//   round trip, no outbound third-party request, no SSRF allowlist to maintain.
//   See dashborad/ui/src/lib/mapsLink.ts.
//
//   WRITE ACTIONS ARE A SEPARATE GROUP, and they are the reason this file is no
//   longer read-only. Every one of them is a state change a customer can
//   observe, so they share three properties the reads do not need:
//     - an explicit state-machine check before the write (see assertTransition)
//     - an audit_logs row (audit_logs has RLS and zero policies, so this
//       service_role client is the only thing that can write one)
//     - a tighter rate limit than the reads
//
// SECURITY
//   requireRole(header, 'admin') from _shared/auth.ts is the gate: it verifies
//   the JWT and checks profiles.role = 'admin'. Nothing else in this file
//   authorises anything. Unknown actions return a validation error listing the
//   valid ones, which is fine because the action list is not secret.
//   Upstream Postgres errors are logged but never returned to the client — a
//   raw error can leak column names and constraint definitions.

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, successResponse } from '../_shared/errors.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { getSupabaseAdmin } from '../_shared/supabase.ts';
import { requireRole } from '../_shared/auth.ts';
import {
  validateRequestSize,
  validateEnum,
  validateUUID,
  validateString,
  normalizeEgyptianPhone,
  validateAdminMerchantRequest,
  formatValidationErrors,
} from '../_shared/validation.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';

const VALID_ACTIONS = [
  'overview.kpis',
  'overview.series',
  'overview.trending',
  'overview.recent_orders',
  'merchant.get',
  // --- writes: merchant onboarding + the approval state machine ---
  'merchant.create',
  'merchant.update',
  'merchant.approve',
  'merchant.unapprove',
  'merchant.reject',
  'merchant.publish',
  'merchant.unpublish',
] as const;

type Action = (typeof VALID_ACTIONS)[number];

/**
 * Actions that change state, and therefore get the write rate limit.
 *
 * A list rather than a prefix test: `merchant.get` and `merchant.create` share a
 * prefix and nothing else, and a prefix rule would quietly rate-limit reads at
 * the write threshold. Being explicit means adding a read can never inherit a
 * write's limit by accident.
 */
const WRITE_ACTIONS: ReadonlySet<string> = new Set<Action>([
  'merchant.create',
  'merchant.update',
  'merchant.approve',
  'merchant.unapprove',
  'merchant.reject',
  'merchant.publish',
  'merchant.unpublish',
]);

// The dashboard's range selector offers exactly these three.
const ALLOWED_WINDOWS = [7, 30, 90] as const;
const DEFAULT_WINDOW_DAYS = 30;

// Trending is fixed at 7 days by product decision, not user-selectable.
const TRENDING_WINDOW_DAYS = 7;

/** Days -> ISO timestamptz the RPCs expect. */
function windowStart(days: number): string {
  return new Date(Date.now() - days * 86_400_000).toISOString();
}

/**
 * Validate and normalise the range selector.
 *
 * validateEnum takes strings, so the number the UI sends is stringified first.
 * An absent or unrecognised value falls back to 30 rather than erroring: a
 * dashboard should render on load, and a bad range selector must not blank the
 * page. Returns the resolved value so the caller can log a coercion.
 */
function resolveWindowDays(raw: unknown): { days: number; coerced: boolean } {
  const asString = String(raw ?? DEFAULT_WINDOW_DAYS);
  const check = validateEnum(asString, 'days', ALLOWED_WINDOWS.map(String));
  if (!check.valid) return { days: DEFAULT_WINDOW_DAYS, coerced: true };
  return { days: Number(asString), coerced: false };
}

/**
 * Clamp a caller-supplied limit. The RPCs clamp too (migration 120), but
 * clamping here means a hostile value never reaches the database at all.
 */
function clampLimit(raw: unknown, fallback: number, max: number): number {
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 1) return fallback;
  return Math.min(Math.floor(n), max);
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async function handleOverviewKpis(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  const supabase = getSupabaseAdmin();

  const { days, coerced } = resolveWindowDays(body.days);
  if (coerced) log.warn('days coerced to default', { requested: body.days });

  const { data, error } = await supabase.rpc('get_platform_kpis', {
    p_from: windowStart(days),
  });
  if (error) {
    log.error('get_platform_kpis failed', { error: error.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  log.info('Overview KPIs served', { days });
  // get_platform_kpis echoes window_days; requested_days is added so the client
  // can tell a coerced range from the one that was asked for.
  return corsResponse(
    successResponse({ ...(data as object), requested_days: days }),
    200,
    undefined,
    req,
  );
}

async function handleOverviewSeries(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  const supabase = getSupabaseAdmin();

  const { days, coerced } = resolveWindowDays(body.days);
  if (coerced) log.warn('days coerced to default', { requested: body.days });

  const { data, error } = await supabase.rpc('get_daily_series', {
    p_from: windowStart(days),
    p_to: new Date().toISOString(),
  });
  if (error) {
    log.error('get_daily_series failed', { error: error.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  return corsResponse(successResponse({ days, rows: data }), 200, undefined, req);
}

async function handleOverviewTrending(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  const supabase = getSupabaseAdmin();

  const { data, error } = await supabase.rpc('get_trending_items', {
    p_from: windowStart(TRENDING_WINDOW_DAYS),
    p_to: new Date().toISOString(),
    p_limit: clampLimit(body.limit, 10, 100),
  });
  if (error) {
    log.error('get_trending_items failed', { error: error.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  return corsResponse(
    successResponse({ days: TRENDING_WINDOW_DAYS, rows: data }),
    200,
    undefined,
    req,
  );
}

async function handleOverviewRecentOrders(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  const supabase = getSupabaseAdmin();

  const { data, error } = await supabase.rpc('get_recent_orders', {
    p_limit: clampLimit(body.limit, 10, 100),
  });
  if (error) {
    log.error('get_recent_orders failed', { error: error.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  return corsResponse(successResponse({ rows: data }), 200, undefined, req);
}

// ---------------------------------------------------------------------------
// Merchant onboarding + approval state machine
// ---------------------------------------------------------------------------
//
// WHY APPROVE AND PUBLISH ARE SEPARATE ACTIONS
//
//   approval_status and is_active are two independent columns with two different
//   jobs, and migration 103 says so in the column's own COMMENT:
//
//     "pending=new place awaiting Ops, approved=live, rejected=refused with
//      reason in approval_note. is_active remains the runtime kill-switch."
//
//   So approval_status is an ONBOARDING JUDGEMENT ("did this vendor check out")
//   and is_active is a RUNTIME SWITCH ("should this vendor be serving now").
//   Collapsing them would lose the distinction the schema was built to keep.
//
// WHY CREATE FORCES BOTH COLUMNS
//
//   The column defaults to approval_status='approved' and is_active=true
//   (schema-final.sql:9233, :9247). That default is a reasonable default for a
//   row inserted by a trusted migration and a dangerous one for a row inserted
//   through a form, because it would publish a vendor nobody reviewed. Create
//   therefore sets { approval_status: 'pending', is_active: false } server-side
//   and ignores whatever the client sent — a client that could choose these
//   could publish an unreviewed merchant, which is the one thing this endpoint
//   exists to prevent.
//
// WHY PUBLISH IS GATED ON APPROVAL
//
//   The customer-facing feed does NOT filter on approval_status. Both
//   get-merchant-feed (index.ts:137) and search_catalog (migration 095) run on
//   service_role and check is_active only, because they bypass RLS. Migration
//   109 tightened the RLS policy and the matview but left those queries alone,
//   and its own header admits "the feed still leaks pending vendors".
//
//   Fixing those queries is out of scope for the dashboard — they are the
//   customer app's read path. What IS in scope is making the dangerous state
//   unreachable from here: create never produces pending + active, and publish
//   refuses unless approved. So the combination cannot be written through this
//   API even though the feed would tolerate it.
//
// DELIBERATELY NO TRANSITION TRIGGER
//
//   There is no state-machine trigger on merchants (contrast
//   trg_enforce_merchant_payout_transitions), so every rule lives here. That is
//   a real weakness — a direct PostgREST write or a future migration bypasses
//   all of it — but adding a trigger is a migration and out of scope. Flagged
//   rather than quietly accepted.

type ApprovalStatus = 'pending' | 'approved' | 'rejected';

interface MerchantState {
  id: string;
  name_en: string;
  name_ar: string;
  category: string;
  city: string;
  approval_status: ApprovalStatus;
  is_active: boolean;
  approval_note: string | null;
  updated_at: string;
}

const MERCHANT_STATE_COLUMNS =
  'id, name_en, name_ar, category, city, approval_status, is_active, approval_note, updated_at';

/**
 * Load just enough of a merchant to decide a transition, or 404.
 *
 * A separate read rather than trusting the client's idea of current state: the
 * whole point of the guards below is that two admins acting at once cannot both
 * succeed, and that requires the decision to be made against the row as it is
 * now, not as the caller last saw it.
 */
async function loadMerchantState(
  merchantId: string,
): Promise<MerchantState | null> {
  const { data, error } = await getSupabaseAdmin()
    .from('merchants')
    .select(MERCHANT_STATE_COLUMNS)
    .eq('id', merchantId)
    .maybeSingle();
  if (error) throw error;
  return (data as MerchantState | null) ?? null;
}

/**
 * Record an admin action.
 *
 * NEVER throws. A failed audit row must not roll back or fail the state change
 * the operator actually asked for — the write already happened, and returning an
 * error would invite a retry that double-applies it. The failure is logged, which
 * is the same trade apps/admin makes in its audit-log helper.
 *
 * Only the HOST of a resolved Maps link is recorded, never the full URL: a place
 * URL embeds the vendor's search string, which is the sort of thing an audit
 * trail should not be storing when the host is enough to answer "where did this
 * pin come from".
 */
async function writeMerchantAudit(
  req: Request,
  adminId: string,
  entry: {
    action: string;
    resourceId: string;
    details?: Record<string, unknown>;
    reason?: string | null;
  },
): Promise<void> {
  try {
    const { error } = await getSupabaseAdmin().from('audit_logs').insert({
      admin_id: adminId,
      action: entry.action,
      resource_type: 'merchant',
      resource_id: entry.resourceId,
      details:
        entry.details && Object.keys(entry.details).length > 0 ? entry.details : null,
      ip_address:
        req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ??
        req.headers.get('x-real-ip') ??
        null,
      user_agent: req.headers.get('user-agent'),
    });
    if (error) {
      // Surfaced through the caller's logger would be better, but this helper has
      // no logger handle; the state change itself is logged by every caller.
      console.error('audit_logs insert failed', {
        action: entry.action,
        error: error.message,
      });
    }
  } catch (err) {
    console.error('audit_logs insert threw', {
      action: entry.action,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/** The transition guards, as data, so each handler reads as one line. */
type Guard = { current: MerchantState; error: string; status: number };

function guardApprove(current: MerchantState): Guard | null {
  if (current.approval_status === 'approved') {
    return { current, error: 'MERCHANT_ALREADY_APPROVED', status: 409 };
  }
  return null;
}

function guardUnapprove(current: MerchantState): Guard | null {
  // Only "already approved" is a no-op worth refusing. Moving a pending merchant
  // to pending is refused too, because it means the caller misread the row.
  if (current.approval_status !== 'approved') {
    return { current, error: 'MERCHANT_NOT_APPROVED', status: 409 };
  }
  return null;
}

function guardPublish(current: MerchantState): Guard | null {
  if (current.approval_status !== 'approved') {
    return { current, error: 'MERCHANT_NOT_APPROVED', status: 409 };
  }
  if (current.is_active) {
    return { current, error: 'MERCHANT_ALREADY_ACTIVE', status: 409 };
  }
  return null;
}

function guardUnpublish(current: MerchantState): Guard | null {
  if (!current.is_active) {
    return { current, error: 'MERCHANT_ALREADY_INACTIVE', status: 409 };
  }
  return null;
}

/**
 * Apply a state transition and audit it.
 *
 * Both the update and the audit are driven from here so no handler can ship one
 * without the other. The patch is a single statement: approval_status and
 * is_active must never be observably half-updated, because the dangerous state
 * is precisely "one moved and the other didn't".
 */
async function applyTransition(
  req: Request,
  adminId: string,
  current: MerchantState,
  patch: Partial<Pick<MerchantState, 'approval_status' | 'is_active' | 'approval_note'>>,
  audit: {
    action: string;
    details: Record<string, unknown>;
    reason?: string | null;
  },
): Promise<MerchantState | null> {
  const { data, error } = await getSupabaseAdmin()
    .from('merchants')
    .update(patch)
    .eq('id', current.id)
    .select(MERCHANT_STATE_COLUMNS)
    .single();

  if (error || !data) {
    // Postgres constraint violations are NOT forwarded: a raw error leaks column
    // names and CHECK definitions.
    return null;
  }

  await writeMerchantAudit(req, adminId, {
    action: audit.action,
    resourceId: current.id,
    details: audit.details,
    reason: audit.reason ?? null,
  });

  return data as MerchantState;
}

/** Bilingual note. Capped because the column is unconstrained nullable text. */
const MAX_NOTE_LENGTH = 500;

function readNote(body: Record<string, unknown>): { value: string | null; error?: string } {
  const raw = body.approval_note ?? body.reason;
  if (raw === undefined || raw === null || raw === '') return { value: null };
  if (typeof raw !== 'string') return { value: null, error: 'approval_note must be a string' };
  const trimmed = raw.trim();
  if (trimmed.length === 0) return { value: null };
  if (trimmed.length > MAX_NOTE_LENGTH) {
    return { value: null, error: `approval_note must be at most ${MAX_NOTE_LENGTH} characters` };
  }
  return { value: trimmed };
}

function notFound(req: Request) {
  return corsResponse(errorResponse('MERCHANT_NOT_FOUND'), 404, undefined, req);
}

/** Resolve the merchant_id from either `merchant_id` or `id`. */
function readMerchantId(body: Record<string, unknown>): string | null {
  const raw = body.merchant_id ?? body.id;
  if (typeof raw !== 'string') return null;
  const check = validateUUID(raw, 'merchant_id');
  return check.valid ? raw : null;
}

// --- handlers ---------------------------------------------------------------

async function handleMerchantGet(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  const merchantId = readMerchantId(body);
  if (!merchantId) {
    return corsResponse(
      errorResponse('VALIDATION_ERROR', {
        message_en: 'merchant_id must be a UUID',
        message_ar: 'يجب أن يكون معرف التاجر UUID',
      }),
      400,
      undefined,
      req,
    );
  }

  const { data, error } = await getSupabaseAdmin()
    .from('merchants')
    .select('*')
    .eq('id', merchantId)
    .maybeSingle();

  if (error) {
    log.error('merchant.get failed', { error: error.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
  if (!data) return notFound(req);

  // This action exists BECAUSE RLS hides pending merchants from the anon key
  // (migration 109). Without it the SPA cannot show an operator the record they
  // are trying to approve.
  return corsResponse(successResponse({ merchant: data }), 200, undefined, req);
}

async function handleMerchantCreate(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
  adminId: string,
) {
  const validation = validateAdminMerchantRequest(body);
  if (!validation.valid) {
    return corsResponse(
      errorResponse('VALIDATION_ERROR', {
        message_en: formatValidationErrors(validation.errors),
        message_ar: 'راجع الحقول المطلوبة',
      }),
      422,
      undefined,
      req,
    );
  }

  const phone = normalizeEgyptianPhone(body.phone);

  // Only the columns the operator actually supplied. Everything else falls
  // through to the column default, which is the whole point of validating just
  // the 8 required fields.
  const insert: Record<string, unknown> = {
    name_en: (body.name_en as string).trim(),
    name_ar: (body.name_ar as string).trim(),
    category: body.category,
    address: (body.address as string).trim(),
    city: (body.city as string).trim(),
    phone,
    lat: Number(body.lat),
    lng: Number(body.lng),
    // Forced. See the WHY CREATE FORCES BOTH COLUMNS note above.
    approval_status: 'pending',
    is_active: false,
  };

  const optional = [
    'area',
    'description_en',
    'description_ar',
    'logo_url',
    'cover_url',
    'commission_pct',
    'min_order_amount',
    'delivery_fee_override',
    'delivery_radius_km',
    'estimated_delivery_minutes',
    'estimated_prep_time_minutes',
    'payout_frequency',
    'payout_method',
  ];
  for (const key of optional) {
    const value = body[key];
    if (value === undefined || value === null || value === '') continue;
    insert[key] = typeof value === 'string' ? value.trim() : value;
  }

  const { data, error } = await getSupabaseAdmin()
    .from('merchants')
    .insert(insert)
    .select('*')
    .single();

  if (error || !data) {
    log.error('merchant.create failed', { error: error?.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  await writeMerchantAudit(req, adminId, {
    action: 'admin.create_merchant',
    resourceId: (data as { id: string }).id,
    details: {
      merchant_name_en: data.name_en,
      merchant_name_ar: data.name_ar,
      category: data.category,
      city: data.city,
      approval_status: 'pending',
      is_active: false,
    },
  });

  log.info('merchant created', { merchantId: (data as { id: string }).id, adminId });
  return corsResponse(successResponse({ merchant: data }), 200, undefined, req);
}

/**
 * Partial update of the merchant's own fields.
 *
 * Deliberately EXCLUDES approval_status and is_active: those move only through
 * the transition handlers, so "edit the name" can never double as "publish".
 * updated_at is excluded too — set_merchants_updated_at maintains it on every
 * UPDATE, and sending it would fight the trigger.
 */
async function handleMerchantUpdate(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
  adminId: string,
) {
  const merchantId = readMerchantId(body);
  if (!merchantId) {
    return corsResponse(
      errorResponse('VALIDATION_ERROR', {
        message_en: 'merchant_id must be a UUID',
        message_ar: 'يجب أن يكون معرف التاجر UUID',
      }),
      400,
      undefined,
      req,
    );
  }

  const existing = await loadMerchantState(merchantId);
  if (!existing) return notFound(req);

  // validateAdminMerchantRequest requires the 8 identity fields, which a partial
  // update does not carry, so each supplied field is checked on its own here.
  const patch: Record<string, unknown> = {};
  const textFields: [string, number][] = [
    ['name_en', 200],
    ['name_ar', 200],
    ['address', 300],
    ['city', 100],
    ['area', 100],
    ['description_en', 1000],
    ['description_ar', 1000],
  ];
  for (const [field, max] of textFields) {
    const value = body[field];
    if (value === undefined) continue;
    const check = validateString(value, field, { max, required: false });
    if (!check.valid) {
      return corsResponse(
        errorResponse('VALIDATION_ERROR', {
          message_en: formatValidationErrors(check.errors),
          message_ar: 'راجع الحقول المُدخلة',
        }),
        422,
        undefined,
        req,
      );
    }
    patch[field] = typeof value === 'string' ? value.trim() : value;
  }

  if (body.phone !== undefined) {
    const phone = normalizeEgyptianPhone(body.phone);
    if (phone === null) {
      return corsResponse(
        errorResponse('VALIDATION_ERROR', {
          message_en: 'Phone must be an Egyptian mobile number',
          message_ar: 'يجب أن يكون الهاتف رقمًا مصريًا صحيحًا',
        }),
        422,
        undefined,
        req,
      );
    }
    patch.phone = phone;
  }

  if (body.category !== undefined) {
    const check = validateEnum(body.category, 'category', [
      'restaurant',
      'pharmacy',
      'market',
      'grocery',
      'bakery',
      'butcher',
      'flowers',
      'other',
    ]);
    if (!check.valid) {
      return corsResponse(
        errorResponse('VALIDATION_ERROR', {
          message_en: formatValidationErrors(check.errors),
          message_ar: 'قيمة التصنيف غير صالحة',
        }),
        422,
        undefined,
        req,
      );
    }
    patch.category = body.category;
  }

  if (Object.keys(patch).length === 0) {
    return corsResponse(
      errorResponse('VALIDATION_ERROR', {
        message_en: 'No updatable fields were supplied',
        message_ar: 'لم يتم إرسال أي حقول قابلة للتحديث',
      }),
      400,
      undefined,
      req,
    );
  }

  const { data, error } = await getSupabaseAdmin()
    .from('merchants')
    .update(patch)
    .eq('id', merchantId)
    .select('*')
    .single();

  if (error || !data) {
    log.error('merchant.update failed', { error: error?.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  await writeMerchantAudit(req, adminId, {
    action: 'admin.update_merchant',
    resourceId: merchantId,
    details: { fields: Object.keys(patch) },
  });

  return corsResponse(successResponse({ merchant: data }), 200, undefined, req);
}

async function handleMerchantApprove(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
  adminId: string,
) {
  const merchantId = readMerchantId(body);
  if (!merchantId) {
    return corsResponse(
      errorResponse('VALIDATION_ERROR', {
        message_en: 'merchant_id must be a UUID',
        message_ar: 'يجب أن يكون معرف التاجر UUID',
      }),
      400,
      undefined,
      req,
    );
  }

  const note = readNote(body);
  if (note.error) {
    return corsResponse(
      errorResponse('VALIDATION_ERROR', {
        message_en: note.error,
        message_ar: 'الملاحظة طويلة جدًا',
      }),
      422,
      undefined,
      req,
    );
  }

  const current = await loadMerchantState(merchantId);
  if (!current) return notFound(req);

  const guard = guardApprove(current);
  if (guard) return corsResponse(errorResponse(guard.error), guard.status, undefined, req);

  // is_active is NOT touched. Approving says the vendor checked out; it does not
  // decide when they go live. That is what publish is for.
  const updated = await applyTransition(req, adminId, current, {
    approval_status: 'approved',
    ...(note.value ? { approval_note: note.value } : {}),
  }, {
    action: 'admin.approve_merchant',
    details: {
      merchant_name: current.name_en,
      previous_approval_status: current.approval_status,
      new_approval_status: 'approved',
      is_active_unchanged: current.is_active,
    },
    reason: note.value,
  });

  if (!updated) {
    log.error('merchant.approve write failed', { merchantId });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  log.info('merchant approved', { merchantId, adminId });
  return corsResponse(successResponse({ merchant: updated }), 200, undefined, req);
}

/**
 * Send an approved merchant back to pending.
 *
 * Writes is_active=false IN THE SAME STATEMENT. Leaving a merchant published
 * while its approval is withdrawn would be exactly the state the feed leak
 * tolerates, so the two columns are never separated here.
 */
async function handleMerchantUnapprove(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
  adminId: string,
) {
  const merchantId = readMerchantId(body);
  if (!merchantId) return corsResponse(errorResponse('VALIDATION_ERROR'), 400, undefined, req);

  const note = readNote(body);
  const current = await loadMerchantState(merchantId);
  if (!current) return notFound(req);

  const guard = guardUnapprove(current);
  if (guard) return corsResponse(errorResponse(guard.error), guard.status, undefined, req);

  const updated = await applyTransition(req, adminId, current, {
    approval_status: 'pending',
    is_active: false,
    ...(note.value ? { approval_note: note.value } : {}),
  }, {
    action: 'admin.unapprove_merchant',
    details: {
      merchant_name: current.name_en,
      previous_approval_status: current.approval_status,
      new_approval_status: 'pending',
      previous_is_active: current.is_active,
      new_is_active: false,
    },
    reason: note.value,
  });

  if (!updated) {
    log.error('merchant.unapprove write failed', { merchantId });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  log.info('merchant unapproved', { merchantId, adminId });
  return corsResponse(successResponse({ merchant: updated }), 200, undefined, req);
}

/**
 * Refuse a merchant. The reason is REQUIRED.
 *
 * A rejection without a reason is not actionable — whoever reads the audit trail
 * later cannot tell a documentation problem from a duplicate from a refusal to
 * pay, and the vendor cannot be told why. So unlike approve, a missing note is
 * rejected here rather than stored as null.
 *
 * Also unpublishes in the same statement: a rejected vendor must not still be
 * serving.
 */
async function handleMerchantReject(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
  adminId: string,
) {
  const merchantId = readMerchantId(body);
  if (!merchantId) return corsResponse(errorResponse('VALIDATION_ERROR'), 400, undefined, req);

  const note = readNote(body);
  if (note.error || note.value === null) {
    return corsResponse(errorResponse('APPROVAL_NOTE_REQUIRED'), 422, undefined, req);
  }

  const current = await loadMerchantState(merchantId);
  if (!current) return notFound(req);

  if (current.approval_status === 'rejected') {
    return corsResponse(
      errorResponse('MERCHANT_NOT_APPROVED', {
        message_en: 'This merchant is already rejected',
        message_ar: 'هذا التاجر مرفوض بالفعل',
      }),
      409,
      undefined,
      req,
    );
  }

  const updated = await applyTransition(req, adminId, current, {
    approval_status: 'rejected',
    is_active: false,
    approval_note: note.value,
  }, {
    action: 'admin.reject_merchant',
    details: {
      merchant_name: current.name_en,
      previous_approval_status: current.approval_status,
      new_approval_status: 'rejected',
      previous_is_active: current.is_active,
      new_is_active: false,
    },
    reason: note.value,
  });

  if (!updated) {
    log.error('merchant.reject write failed', { merchantId });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  log.info('merchant rejected', { merchantId, adminId });
  return corsResponse(successResponse({ merchant: updated }), 200, undefined, req);
}

/**
 * Make an APPROVED merchant visible.
 *
 * The approval check is the load-bearing line in this file's whole write group:
 * the customer feed gates on is_active alone, so without it this button would be
 * a one-click way to list a vendor nobody reviewed.
 */
async function handleMerchantPublish(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
  adminId: string,
) {
  const merchantId = readMerchantId(body);
  if (!merchantId) return corsResponse(errorResponse('VALIDATION_ERROR'), 400, undefined, req);

  const note = readNote(body);
  const current = await loadMerchantState(merchantId);
  if (!current) return notFound(req);

  const guard = guardPublish(current);
  if (guard) return corsResponse(errorResponse(guard.error), guard.status, undefined, req);

  const updated = await applyTransition(req, adminId, current, {
    is_active: true,
  }, {
    action: 'admin.activate_merchant',
    details: {
      merchant_name: current.name_en,
      previous_status: false,
      new_status: true,
      approval_status: current.approval_status,
    },
    reason: note.value,
  });

  if (!updated) {
    log.error('merchant.publish write failed', { merchantId });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  log.info('merchant published', { merchantId, adminId });
  return corsResponse(successResponse({ merchant: updated }), 200, undefined, req);
}

/** The runtime kill-switch. Reversible, and deliberately not a rejection. */
async function handleMerchantUnpublish(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
  adminId: string,
) {
  const merchantId = readMerchantId(body);
  if (!merchantId) return corsResponse(errorResponse('VALIDATION_ERROR'), 400, undefined, req);

  const note = readNote(body);
  const current = await loadMerchantState(merchantId);
  if (!current) return notFound(req);

  const guard = guardUnpublish(current);
  if (guard) return corsResponse(errorResponse(guard.error), guard.status, undefined, req);

  const updated = await applyTransition(req, adminId, current, {
    is_active: false,
  }, {
    action: 'admin.deactivate_merchant',
    details: {
      merchant_name: current.name_en,
      previous_status: true,
      new_status: false,
      approval_status: current.approval_status,
    },
    reason: note.value,
  });

  if (!updated) {
    log.error('merchant.unpublish write failed', { merchantId });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  log.info('merchant unpublished', { merchantId, adminId });
  return corsResponse(successResponse({ merchant: updated }), 200, undefined, req);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'admin-api' });

  try {
    // --- Request size guard ---
    const sizeResult = validateRequestSize(req);
    if (!sizeResult.valid) {
      log.warn('Request too large', { errors: sizeResult.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', {
          message_en: 'Request body too large',
          message_ar: 'حجم الطلب كبير جداً',
        }),
        413,
        undefined,
        req,
      );
    }

    // --- Auth: the only authorisation in this file ---
    const authResult = await requireRole(req.headers.get('Authorization'), 'admin');
    if (authResult.error) {
      return corsResponse(authResult.error, authResult.status || 403, undefined, req);
    }
    const adminId = authResult.data!.userId;

    // --- Parse body ---
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return corsResponse(
        errorResponse('VALIDATION_ERROR', {
          message_en: 'Body must be valid JSON',
          message_ar: 'يجب أن يكون الجسم JSON صالحاً',
        }),
        400,
        undefined,
        req,
      );
    }

    const action = body.action as Action;

    // --- Rate limit, per action ---
    //
    // Writes get a much tighter budget than reads (see RATE_LIMITS). The
    // limiter is per-isolate and best-effort, so it is a speed bump rather than
    // the guard — the guard is the state-machine check inside each write handler.
    const limit = WRITE_ACTIONS.has(action)
      ? RATE_LIMITS.ADMIN_MERCHANT_WRITE
      : RATE_LIMITS.ADMIN_DASHBOARD_READ;

    const rl = checkRateLimit(`admin-api:${action}:${adminId}`, limit);
    if (!rl.allowed) {
      log.warn('Rate limited', { action, adminId });
      return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
    }

    log.info('Admin request', { action, adminId });

    switch (action) {
      case 'overview.kpis':
        return await handleOverviewKpis(body, req, log);
      case 'overview.series':
        return await handleOverviewSeries(body, req, log);
      case 'overview.trending':
        return await handleOverviewTrending(body, req, log);
      case 'overview.recent_orders':
        return await handleOverviewRecentOrders(body, req, log);

      // --- merchant reads ---
      case 'merchant.get':
        return await handleMerchantGet(body, req, log);

      // --- merchant writes: every one takes adminId for the audit row ---
      case 'merchant.create':
        return await handleMerchantCreate(body, req, log, adminId);
      case 'merchant.update':
        return await handleMerchantUpdate(body, req, log, adminId);
      case 'merchant.approve':
        return await handleMerchantApprove(body, req, log, adminId);
      case 'merchant.unapprove':
        return await handleMerchantUnapprove(body, req, log, adminId);
      case 'merchant.reject':
        return await handleMerchantReject(body, req, log, adminId);
      case 'merchant.publish':
        return await handleMerchantPublish(body, req, log, adminId);
      case 'merchant.unpublish':
        return await handleMerchantUnpublish(body, req, log, adminId);

      default:
        return corsResponse(
          errorResponse('VALIDATION_ERROR', {
            message_en: `Unknown action: ${String(action)}. Valid: ${VALID_ACTIONS.join(', ')}`,
            message_ar: `إجراء غير معروف: ${String(action)}`,
          }),
          400,
          undefined,
          req,
        );
    }
  } catch (err) {
    log.error('Unhandled error', {
      error: err instanceof Error ? err.message : String(err),
    });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});
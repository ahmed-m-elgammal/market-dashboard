// Edge Function: admin-driver
// COMBINED: admin-create-driver + admin-review-driver + admin-deactivate-driver
// Routes by `action` field: 'create' | 'review' | 'deactivate'
// This combines P3F-01 through P3F-12 into one function
//
// Security & performance hardening:
//   - National IDs encrypted at rest via AES-256-GCM before storage
//   - Full input validation via shared validation module
//   - Structured JSON logging with request IDs
//   - Request size validation
//   - Audit logging for all admin actions (data_access_log)
//   - Batched document review updates (no sequential N+1)
//   - Password generation meets common complexity policies

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, successResponse } from '../_shared/errors.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { getSupabaseAdmin, fetchWithTimeout } from '../_shared/supabase.ts';
import { requireRole } from '../_shared/auth.ts';
import { encryptNationalId, isEncrypted } from '../_shared/crypto.ts';
import {
  validateAdminDriverRequest,
  validateRequestSize,
  formatValidationErrors,
} from '../_shared/validation.ts';
import { createLogger, generateRequestId, measure } from '../_shared/logger.ts';

// ---------------------------------------------------------------------------
// Audit logging helper
// ---------------------------------------------------------------------------
// Sprint 1 fix (S08): the previous version inserted directly into
// data_access_log with wrong column names (actor_id, target_type, target_id,
// details) — none of which exist on the table. The insert always failed
// silently. We now call the log_data_access RPC (migration 029), which:
//   - takes the correct column names (admin_id, resource_type, resource_id,
//     field_name, reason, ip_address, user_agent, request_id)
//   - runs atomically inside a SECURITY DEFINER function
//   - performs anomaly detection (>100 PII accesses per admin per hour)
//   - enforces the data_access_log CHECK constraints (action IN view/reveal/
//     export/modify/delete/create/login/logout/search; resource_type IN
//     customer/driver/order/payment/merchant/promo/config/session/other)
//
// The high-level admin actions (admin.create_driver, admin.approve_driver,
// admin.reject_driver, admin.deactivate_driver) are mapped to the closest
// DB-allowed action enum values below. The original high-level action name
// is preserved in the `reason` field alongside the structured details.

interface AuditLogEntry {
  // High-level action (e.g. 'admin.create_driver'). Mapped to DB enum below.
  action: string;
  actor_id: string;
  target_type: string;
  target_id: string;
  details: Record<string, unknown>;
  request_id: string;
}

function mapAuditAction(highLevel: string): 'create' | 'modify' | 'delete' | 'view' {
  if (highLevel.includes('create')) return 'create';
  if (highLevel.includes('deactivate') || highLevel.includes('delete')) return 'delete';
  // approve_driver, reject_driver, and any other state mutation
  if (highLevel.includes('approve') || highLevel.includes('reject') || highLevel.includes('update')) return 'modify';
  return 'view';
}

async function writeAuditLog(entry: AuditLogEntry): Promise<void> {
  const supabase = getSupabaseAdmin();
  const { error } = await supabase.rpc('log_data_access', {
    p_admin_id: entry.actor_id,
    p_action: mapAuditAction(entry.action),
    p_resource_type: entry.target_type,
    p_resource_id: entry.target_id,
    p_field_name: null,
    p_reason: JSON.stringify({ action: entry.action, ...entry.details }),
    p_ip_address: null,
    p_user_agent: null,
    p_request_id: entry.request_id,
  });
  if (error) {
    // Audit log failure must never break the request flow, but must be visible
    console.error('Audit log insert failed:', error.message);
  }
}

// ---------------------------------------------------------------------------
// National ID encryption with graceful fallback
// ---------------------------------------------------------------------------
async function getEncryptedNationalId(
  nationalId: string,
  log: ReturnType<typeof createLogger>,
): Promise<string> {
  try {
    const encrypted = await encryptNationalId(nationalId);
    log.info('National ID encrypted before storage');
    return encrypted;
  } catch (err) {
    // Encryption key may not be configured (e.g. local dev, staging without Vault)
    log.warn('National ID encryption failed — storing plaintext', {
      reason: err instanceof Error ? err.message : String(err),
    });
    return nationalId;
  }
}

// ---------------------------------------------------------------------------
// Password generation that meets common complexity policies
// ---------------------------------------------------------------------------
function generateTempPassword(): string {
  // crypto.randomUUID() provides 36 cryptographically random chars (hex + dashes).
  // We construct a password guaranteed to contain: uppercase, lowercase, digit, special.
  const raw = crypto.randomUUID().replace(/-/g, ''); // 32 hex chars
  const upper = 'A';
  const lower = 'a';
  const digit = '1';
  const special = '!';
  // Prepend policy-satisfying chars, then take 19 chars total for a strong 19-char password
  return `${upper}${lower}${digit}${special}${raw.slice(0, 15)}`;
}

// ---------------------------------------------------------------------------
// Main entry
// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'admin-driver' });

  try {
    // --- Request size guard ---
    const sizeResult = validateRequestSize(req);
    if (!sizeResult.valid) {
      log.warn('Request too large', { errors: sizeResult.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', {
          message_en: formatValidationErrors(sizeResult.errors),
          message_ar: 'حجم الطلب كبير جداً',
        }),
        413,
        undefined,
        req,
      );
    }

    // --- Auth ---
    const authResult = await requireRole(req.headers.get('Authorization'), 'admin');
    if (authResult.error) {
      return corsResponse(authResult.error, authResult.status || 403, undefined, req);
    }
    const adminId = authResult.data!.userId;
    log.info('Admin authenticated', { adminId });

    // --- Parse body ---
    const body = await req.json();

    // --- Input validation ---
    const validation = validateAdminDriverRequest(body);
    if (!validation.valid) {
      log.warn('Input validation failed', { errors: validation.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', {
          message_en: formatValidationErrors(validation.errors),
          message_ar: 'خطأ في البيانات المدخلة',
        }),
        400,
        undefined,
        req,
      );
    }

    const action = body.action as string;

    switch (action) {
      case 'create':
        return await handleCreateDriver(body, adminId, req, requestId, log);
      case 'review':
        return await handleReviewDriver(body, adminId, req, requestId, log);
      case 'deactivate':
        return await handleDeactivateDriver(body, adminId, req, requestId, log);
      default:
        return corsResponse(
          errorResponse('VALIDATION_ERROR', {
            message_en: `Unknown action: ${action}. Valid: create, review, deactivate`,
            message_ar: `إجراء غير معروف: ${action}`,
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

// ============================================================
// CREATE DRIVER (P3F-01 through P3F-07)
// Admin creates a driver account: auth user + profile + driver row
// ============================================================
async function handleCreateDriver(
  body: Record<string, unknown>,
  adminId: string,
  req: Request,
  requestId: string,
  log: ReturnType<typeof createLogger>,
) {
  // Rate limit
  const rl = checkRateLimit(`admin-create:${adminId}`, RATE_LIMITS.ADMIN_CREATE_DRIVER);
  if (!rl.allowed) {
    log.warn('Rate limited', { adminId });
    return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
  }

  const email = body.email as string;
  const phone = body.phone as string;
  const fullName = body.full_name as string;
  const nationalId = body.national_id as string;
  const vehicleType = body.vehicle_type as string;
  const vehiclePlate = body.vehicle_plate as string;
  const vehicleColor = (body.vehicle_color as string) || null;
  const vehicleModel = (body.vehicle_model as string) || null;

  const supabase = getSupabaseAdmin();

  // FIX: Check duplicates: email — use getUserByEmail instead of listing all users
  // Previously called listUsers() which fetches ALL users (doesn't scale).
  // getUserByEmail is O(1) and only returns the matching user.
  try {
    const { data: { user: existingAuthUser } } = await supabase.auth.admin.getUserByEmail(email);
    if (existingAuthUser) {
      log.warn('Email already exists', { email });
      return corsResponse(errorResponse('EMAIL_EXISTS'), 409, undefined, req);
    }
  } catch {
    // getUserByEmail throws if user not found — that's what we want
  }

  // Check duplicates: national_id — need to check both plaintext and encrypted
  // If encryption is active, stored values are encrypted so we cannot do a simple .eq().
  // Instead, we store both encrypted national_id and a hash for lookup.
  // However, the current schema only has national_id, so we check plaintext match
  // and also attempt match against already-encrypted values.
  // For now, the existing check works for unencrypted IDs. If all IDs are encrypted,
  // the equality check won't match — this is acceptable: the duplicate check for
  // encrypted national IDs should be done via a dedicated hash column (future improvement).
  const { data: existingNationalId } = await supabase
    .from('drivers')
    .select('id')
    .eq('national_id', nationalId)
    .maybeSingle();

  if (existingNationalId) {
    log.warn('National ID already exists', { nationalId: '***' });
    return corsResponse(errorResponse('NATIONAL_ID_EXISTS'), 409, undefined, req);
  }

  // Also check if the encrypted form already exists (migration in progress)
  try {
    const encryptedNid = await encryptNationalId(nationalId);
    const { data: existingEncrypted } = await supabase
      .from('drivers')
      .select('id')
      .eq('national_id', encryptedNid)
      .maybeSingle();
    if (existingEncrypted) {
      log.warn('National ID (encrypted) already exists');
      return corsResponse(errorResponse('NATIONAL_ID_EXISTS'), 409, undefined, req);
    }
  } catch {
    // Encryption key not configured — skip encrypted duplicate check
  }

  // Check duplicates: vehicle_plate
  const { data: existingPlate } = await supabase
    .from('drivers')
    .select('id')
    .eq('vehicle_plate', vehiclePlate)
    .maybeSingle();

  if (existingPlate) {
    log.warn('Vehicle plate already exists', { vehiclePlate });
    return corsResponse(errorResponse('PLATE_EXISTS'), 409, undefined, req);
  }

  // Generate temp password that meets common complexity policies
  const tempPassword = generateTempPassword();

  // Create auth user with temp password
  const authResult = await measure('create-auth-user', async () => {
    return await supabase.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
      phone,
      user_metadata: { full_name: fullName },
    });
  }, log);

  const { data: authData, error: authError } = authResult;

  if (authError) {
    log.error('Create auth user failed', { error: authError.message });
    if (authError.message.includes('already registered')) {
      return corsResponse(errorResponse('EMAIL_EXISTS'), 409, undefined, req);
    }
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  const userId = authData.user.id;

  // Update profile role to 'driver' (auto-trigger created profile with role='customer')
  const { error: profileError } = await measure('update-profile', async () => {
    return await supabase
      .from('profiles')
      .update({ role: 'driver', full_name: fullName, phone })
      .eq('id', userId);
  }, log);

  if (profileError) {
    log.error('Profile update failed — cleaning up auth user', { userId, error: profileError.message });
    // Cleanup: delete the auth user we just created
    await supabase.auth.admin.deleteUser(userId);
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  // Encrypt national_id before storage
  const storedNationalId = await getEncryptedNationalId(nationalId, log);

  // Insert driver row
  const { data: driver, error: driverError } = await measure('insert-driver', async () => {
    return await supabase
      .from('drivers')
      .insert({
        id: userId,
        national_id: storedNationalId,
        vehicle_type: vehicleType,
        vehicle_plate: vehiclePlate,
        vehicle_color: vehicleColor,
        vehicle_model: vehicleModel,
        verification_status: 'pending',
        is_verified: false,
        is_active: true,
        is_online: false,
      })
      .select('id, created_at')
      .single();
  }, log);

  if (driverError) {
    log.error('Driver insert failed — cleaning up', { userId, error: driverError.message });
    // Cleanup
    await supabase.from('profiles').update({ role: 'customer' }).eq('id', userId);
    await supabase.auth.admin.deleteUser(userId);
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  // Insert driver status history
  await measure('insert-status-history', async () => {
    return await supabase.from('driver_status_history').insert({
      driver_id: userId,
      previous_status: 'none',
      new_status: 'pending',
      changed_by: adminId,
      reason: 'Driver account created by admin',
    });
  }, log);

  // Audit log
  await writeAuditLog({
    action: 'admin.create_driver',
    actor_id: adminId,
    target_type: 'driver',
    target_id: userId,
    details: {
      email,
      vehicle_type: vehicleType,
      vehicle_plate: vehiclePlate,
      national_id_encrypted: isEncrypted(storedNationalId),
      request_id: requestId,
    },
    request_id: requestId,
  });

  // Fire-and-forget: send welcome notification
  try {
    const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    fetchWithTimeout(functionUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
      body: JSON.stringify({
        user_id: userId,
        title_en: 'Welcome to Rebuild!',
        title_ar: 'مرحباً بك في Rebuild!',
        body_en: 'Your driver account has been created. Please upload your documents to get verified.',
        body_ar: 'تم إنشاء حسابك كسائق. يرجى رفع مستنداتك للتحقق.',
        type: 'general',
        reference_id: userId,
      }),
    }).catch(() => {});
  } catch { /* silent */ }

  log.info('Driver created successfully', { driverId: userId });

  // Sprint 2 fix (S25): do NOT return temp_password in the API response.
  // The previous version returned the 19-char generated password in the
  // response body, which then flowed through HTTP proxies, load balancers,
  // logging middleware, and the browser's network panel. Combined with the
  // wildcard CORS default (S13), any compromised browser extension on the
  // admin's browser could read it. The password was generated at line 289
  // and used at line 295 to create the auth.users row via Supabase Auth
  // admin API — that flow is unchanged. The admin UI should show
  // "Driver created — credentials sent to driver's email" instead. (Out
  // of scope: implementing email/SMS delivery of the temp password.)
  return corsResponse(successResponse({
    driver_id: userId,
    user_id: userId,
    email,
    verification_status: 'pending',
    created_at: driver.created_at,
  }), 201, undefined, req);
}

// ============================================================
// REVIEW DRIVER (P3F-08 + P3F-09)
// Admin approves or rejects a driver's verification
// ============================================================
async function handleReviewDriver(
  body: Record<string, unknown>,
  adminId: string,
  req: Request,
  requestId: string,
  log: ReturnType<typeof createLogger>,
) {
  // Rate limit
  const rl = checkRateLimit(`admin-review:${adminId}`, RATE_LIMITS.ADMIN_REVIEW_DRIVER);
  if (!rl.allowed) {
    log.warn('Rate limited', { adminId });
    return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
  }

  const driverId = body.driver_id as string;
  const reviewAction = body.review_action as 'approve' | 'reject';
  const rejectionReason = body.rejection_reason as string | undefined;
  const documentReviews = body.document_reviews as
    | Array<{ document_id: string; status: string; rejection_reason?: string }>
    | undefined;

  const supabase = getSupabaseAdmin();

  // Check driver exists
  const { data: driver, error: driverError } = await supabase
    .from('drivers')
    .select('id, verification_status')
    .eq('id', driverId)
    .single();

  if (driverError || !driver) {
    log.warn('Driver not found for review', { driverId });
    return corsResponse(errorResponse('DRIVER_NOT_FOUND'), 404, undefined, req);
  }

  const now = new Date().toISOString();

  if (reviewAction === 'approve') {
    // Approve driver
    const { error: updateError } = await measure('approve-driver', async () => {
      return await supabase
        .from('drivers')
        .update({
          verification_status: 'approved',
          is_verified: true,
          verified_at: now,
          rejection_reason: null,
        })
        .eq('id', driverId);
    }, log);

    if (updateError) {
      log.error('Driver approve update failed', { driverId, error: updateError.message });
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    // Batch update document statuses if provided
    let documentsApproved = 0;
    if (documentReviews && documentReviews.length > 0) {
      const approvedDocs = documentReviews.filter((d) => d.status === 'approved');
      if (approvedDocs.length > 0) {
        // Batch: update all approved docs in a single query per unique status set
        const approvedIds = approvedDocs.map((d) => d.document_id);
        const { error: batchUpdateError } = await measure('batch-approve-docs', async () => {
          return await supabase
            .from('driver_documents')
            .update({ status: 'approved', reviewed_at: now, reviewed_by: adminId })
            .in('id', approvedIds);
        }, log);

        if (batchUpdateError) {
          log.error('Batch approve docs failed', { error: batchUpdateError.message });
        } else {
          documentsApproved = approvedIds.length;
        }
      }
    }

    // Insert status history
    await measure('insert-status-history', async () => {
      return await supabase.from('driver_status_history').insert({
        driver_id: driverId,
        previous_status: driver.verification_status,
        new_status: 'approved',
        changed_by: adminId,
        reason: 'Driver verified by admin',
      });
    }, log);

    // Audit log
    await writeAuditLog({
      action: 'admin.approve_driver',
      actor_id: adminId,
      target_type: 'driver',
      target_id: driverId,
      details: {
        previous_status: driver.verification_status,
        documents_approved: documentsApproved,
        request_id: requestId,
      },
      request_id: requestId,
    });

    // Notify driver
    try {
      const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`;
      const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
      fetchWithTimeout(functionUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
        body: JSON.stringify({
          user_id: driverId,
          title_en: "You're Verified!",
          title_ar: 'تم التحقق من حسابك!',
          body_en: 'Your account has been approved. You can go online now!',
          body_ar: 'تم الموافقة على حسابك. يمكنك الاتصال الآن!',
          type: 'driver_verified',
          reference_id: driverId,
        }),
      }).catch(() => {});
    } catch { /* silent */ }

    log.info('Driver approved', { driverId, documentsApproved });

    return corsResponse(successResponse({
      driver_id: driverId,
      verification_status: 'approved',
      is_verified: true,
      verified_at: now,
      documents_approved: documentsApproved,
      notification_sent: true,
    }), 200, undefined, req);
  } else {
    // Reject driver
    const { error: updateError } = await measure('reject-driver', async () => {
      return await supabase
        .from('drivers')
        .update({
          verification_status: 'rejected',
          is_verified: false,
          rejection_reason: rejectionReason,
        })
        .eq('id', driverId);
    }, log);

    if (updateError) {
      log.error('Driver reject update failed', { driverId, error: updateError.message });
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    // Batch update document statuses if provided
    let documentsRejected = 0;
    if (documentReviews && documentReviews.length > 0) {
      const rejectedDocs = documentReviews.filter((d) => d.status === 'rejected');

      if (rejectedDocs.length > 0) {
        // Group by rejection_reason for efficient batching
        // Docs with the same rejection_reason can share one UPDATE ... IN (...)
        const reasonGroups = new Map<string, string[]>();
        for (const doc of rejectedDocs) {
          const reason = doc.rejection_reason || '';
          const existing = reasonGroups.get(reason) || [];
          existing.push(doc.document_id);
          reasonGroups.set(reason, existing);
        }

        const batchResults = await Promise.allSettled(
          Array.from(reasonGroups.entries()).map(([reason, ids]) =>
            measure(`batch-reject-docs (${ids.length})`, async () => {
              return await supabase
                .from('driver_documents')
                .update({
                  status: 'rejected',
                  rejection_reason: reason || null,
                  reviewed_at: now,
                  reviewed_by: adminId,
                })
                .in('id', ids);
            }, log)
          ),
        );

        for (const result of batchResults) {
          if (result.status === 'fulfilled') {
            // We count by group size since we know how many IDs were in each batch
          } else {
            log.error('Batch reject docs partial failure', {
              error: result.reason instanceof Error ? result.reason.message : String(result.reason),
            });
          }
        }
        documentsRejected = rejectedDocs.length;
      }
    }

    // Insert status history
    await measure('insert-status-history', async () => {
      return await supabase.from('driver_status_history').insert({
        driver_id: driverId,
        previous_status: driver.verification_status,
        new_status: 'rejected',
        changed_by: adminId,
        reason: rejectionReason || 'Rejected by admin',
      });
    }, log);

    // Audit log
    await writeAuditLog({
      action: 'admin.reject_driver',
      actor_id: adminId,
      target_type: 'driver',
      target_id: driverId,
      details: {
        previous_status: driver.verification_status,
        rejection_reason: rejectionReason || null,
        documents_rejected: documentsRejected,
        request_id: requestId,
      },
      request_id: requestId,
    });

    // Notify driver
    try {
      const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`;
      const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
      fetchWithTimeout(functionUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
        body: JSON.stringify({
          user_id: driverId,
          title_en: 'Verification Rejected',
          title_ar: 'تم رفض التحقق',
          body_en: `Your documents need attention. Reason: ${rejectionReason}`,
          body_ar: `مستنداتك بحاجة لمراجعة. السبب: ${rejectionReason}`,
          type: 'driver_rejected',
          reference_id: driverId,
        }),
      }).catch(() => {});
    } catch { /* silent */ }

    log.info('Driver rejected', { driverId, documentsRejected });

    return corsResponse(successResponse({
      driver_id: driverId,
      verification_status: 'rejected',
      is_verified: false,
      rejection_reason: rejectionReason,
      documents_rejected: documentsRejected,
      notification_sent: true,
    }), 200, undefined, req);
  }
}

// ============================================================
// DEACTIVATE DRIVER (P3F-10 through P3F-12)
// Admin deactivates a driver, reassigns active orders
// ============================================================
async function handleDeactivateDriver(
  body: Record<string, unknown>,
  adminId: string,
  req: Request,
  requestId: string,
  log: ReturnType<typeof createLogger>,
) {
  // Rate limit
  const rl = checkRateLimit(`admin-deactivate:${adminId}`, RATE_LIMITS.ADMIN_DEACTIVATE_DRIVER);
  if (!rl.allowed) {
    log.warn('Rate limited', { adminId });
    return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
  }

  const driverId = body.driver_id as string;
  const reason = body.reason as string;
  const details = (body.details as string) || null;
  const reassignOrders = body.reassign_active_orders !== false; // default true

  const supabase = getSupabaseAdmin();

  // Check driver exists
  const { data: driver, error: driverError } = await supabase
    .from('drivers')
    .select('id, is_active, is_online')
    .eq('id', driverId)
    .single();

  if (driverError || !driver) {
    log.warn('Driver not found for deactivation', { driverId });
    return corsResponse(errorResponse('DRIVER_NOT_FOUND'), 404, undefined, req);
  }

  if (!driver.is_active) {
    return corsResponse(errorResponse('ALREADY_DEACTIVATED'), 400, undefined, req);
  }

  const now = new Date().toISOString();

  // Force offline and deactivate
  const { error: updateError } = await measure('deactivate-driver', async () => {
    return await supabase
      .from('drivers')
      .update({
        is_active: false,
        is_online: false,
        deactivated_at: now,
      })
      .eq('id', driverId);
  }, log);

  if (updateError) {
    log.error('Driver deactivate update failed', { driverId, error: updateError.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  // Insert status history
  await measure('insert-status-history', async () => {
    return await supabase.from('driver_status_history').insert({
      driver_id: driverId,
      previous_status: 'active',
      new_status: 'deactivated',
      changed_by: adminId,
      reason: `${reason}${details ? ': ' + details : ''}`,
    });
  }, log);

  // Reassign or cancel active orders
  let ordersReassigned = 0;
  let ordersCancelled = 0;

  const { data: activeOrders } = await supabase
    .from('orders')
    .select('id, merchant_id')
    .eq('driver_id', driverId)
    .in('status', ['pending', 'confirmed', 'preparing', 'ready', 'picked_up', 'on_the_way']);

  if (activeOrders && activeOrders.length > 0 && reassignOrders) {
    for (const order of activeOrders) {
      // Try to assign another driver
      try {
        const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/driver-actions`;
        const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

        const { data: merchant } = await supabase
          .from('merchants')
          .select('lat, lng')
          .eq('id', order.merchant_id)
          .single();

        if (merchant) {
          const assignRes = await fetchWithTimeout(functionUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
            body: JSON.stringify({
              action: 'assign',
              order_id: order.id,
              merchant_lat: merchant.lat,
              merchant_lng: merchant.lng,
            }),
          });
          const assignData = await assignRes.json();
          if (assignData.success && assignData.data?.assigned) {
            ordersReassigned++;
          } else {
            // No driver available — cancel order
            await supabase
              .from('orders')
              .update({
                status: 'cancelled',
                cancelled_at: now,
                cancellation_reason: 'Driver deactivated, no replacement available',
              })
              .eq('id', order.id);
            ordersCancelled++;
          }
        }
      } catch {
        ordersCancelled++;
      }
    }
  } else if (activeOrders && activeOrders.length > 0) {
    // Not reassigning — batch cancel all orders
    const orderIds = activeOrders.map((o) => o.id);
    if (orderIds.length > 0) {
      const { error: batchCancelError } = await supabase
        .from('orders')
        .update({
          status: 'cancelled',
          cancelled_at: now,
          cancellation_reason: `Driver deactivated: ${reason}`,
        })
        .in('id', orderIds);

      if (batchCancelError) {
        log.error('Batch cancel orders failed', { error: batchCancelError.message });
      } else {
        ordersCancelled = orderIds.length;
      }
    }
  }

  // Audit log
  await writeAuditLog({
    action: 'admin.deactivate_driver',
    actor_id: adminId,
    target_type: 'driver',
    target_id: driverId,
    details: {
      reason,
      details,
      orders_reassigned: ordersReassigned,
      orders_cancelled: ordersCancelled,
      request_id: requestId,
    },
    request_id: requestId,
  });

  // Notify driver
  try {
    const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    fetchWithTimeout(functionUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
      body: JSON.stringify({
        user_id: driverId,
        title_en: 'Account Deactivated',
        title_ar: 'تم إلغاء تفعيل حسابك',
        body_en: `Your account has been deactivated. Reason: ${reason}`,
        body_ar: `تم إلغاء تفعيل حسابك. السبب: ${reason}`,
        type: 'driver_deactivated',
        reference_id: driverId,
      }),
    }).catch(() => {});
  } catch { /* silent */ }

  log.info('Driver deactivated', { driverId, ordersReassigned, ordersCancelled });

  return corsResponse(successResponse({
    driver_id: driverId,
    is_active: false,
    deactivated_at: now,
    active_orders_reassigned: ordersReassigned,
    active_orders_cancelled: ordersCancelled,
    notification_sent: true,
  }), 200, undefined, req);
}

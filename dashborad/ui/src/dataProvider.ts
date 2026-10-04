/**
 * Refine dataProvider: a REST client for the admin-api Edge Function.
 *
 * WHY A PROXY AND NOT DIRECT SUPABASE
 *   The browser holds the anon key, and RLS correctly hides what the dashboard
 *   needs — pending merchants, moderation queues, and the migration 120 Overview
 *   RPCs are service_role only. admin-api verifies the caller is an admin and
 *   forwards with service_role. So every read below is a POST to one URL.
 *
 * RESOURCES
 *   Refine's dataProvider is resource-oriented; admin-api is action-oriented.
 *   RESOURCE_ACTION (in constants.ts) maps one to the other, so the Overview
 *   components call useList('overview-kpis') rather than knowing the wire format.
 *
 * The response envelope is { success, data } / { success: false, error }, the
 * same one every other Edge Function uses (_shared/errors.ts), so error messages
 * arrive bilingual and we can surface message_ar when the UI is Arabic.
 */
import type { DataProvider } from '@refinedev/core';
import { ADMIN_API_URL, RESOURCE_ACTION } from './constants';
import type { AdminApiErrorBody, AdminApiSuccess } from './constants';
import { supabase } from './lib/supabase';

/** Error carrying the bilingual message so the UI can pick the right one. */
export class AdminApiError extends Error {
  constructor(
    readonly code: string,
    readonly messageEn: string,
    readonly messageAr: string,
    readonly status: number,
  ) {
    super(messageEn);
    this.name = 'AdminApiError';
  }
}

/**
 * Internal failures the operator should never see verbatim.
 *
 * These are transport-level problems, not domain errors — domain errors come
 * from admin-api as a bilingual ErrorResponse and are shown as-is.
 */
const TRANSPORT_ERRORS = {
  UNAUTHORIZED: ['Not signed in', 'غير مسجل الدخول'],
  UPSTREAM_ERROR: [
    'The server could not complete the request',
    'تعذر على الخادم تنفيذ الطلب',
  ],
  BAD_RESPONSE: [
    'The server returned an unreadable response',
    'أعاد الخادم استجابة غير قابلة للقراءة',
  ],
  UNMAPPED_RESOURCE: [
    'This screen is not wired up yet',
    'هذه الشاشة غير متاحة بعد',
  ],
  NOT_IMPLEMENTED: ['Not available yet', 'غير متاح بعد'],
} as const satisfies Record<string, readonly [string, string]>;

function transportError(
  key: keyof typeof TRANSPORT_ERRORS,
  status: number,
  enOverride?: string,
  arOverride?: string,
): AdminApiError {
  const [en, ar] = TRANSPORT_ERRORS[key];
  return new AdminApiError(
    key,
    enOverride ?? en,
    arOverride ?? ar,
    status,
  );
}

async function authHeaders(): Promise<Record<string, string>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) {
    throw transportError('UNAUTHORIZED', 401);
  }
  return {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
  };
}

async function call<T>(action: string, payload: Record<string, unknown> = {}): Promise<T> {
  const response = await fetch(ADMIN_API_URL, {
    method: 'POST',
    headers: await authHeaders(),
    body: JSON.stringify({ action, ...payload }),
  });

  // A 5xx body is often not JSON at all (gateway, cold start, crash), so this
  // is checked before parsing.
  if (!response.ok && response.status >= 500) {
    throw transportError('UPSTREAM_ERROR', response.status);
  }

  let body: AdminApiSuccess<T> | AdminApiErrorBody;
  try {
    body = (await response.json()) as AdminApiSuccess<T> | AdminApiErrorBody;
  } catch {
    throw transportError('BAD_RESPONSE', response.status);
  }

  if (!body.success) {
    const err = body.error;
    throw new AdminApiError(err.code, err.message_en, err.message_ar, response.status);
  }

  return body.data;
}

/**
 * Normalise an admin-api payload into the array Refine expects from getList.
 *
 *   admin-api returns one of three shapes:
 *     - a bare array            (not used by the Overview, but the natural case)
 *     - { rows: [...] }         (series, trending, recent_orders)
 *     - a bare object           (kpis — an aggregate with no FROM clause)
 *
 *   A missing/unexpected shape resolves to [] rather than throwing: this is a
 *   read path, and an empty table plus an error banner beats a blank screen.
 */
function toRows(resource: string, data: unknown): unknown[] {
  if (Array.isArray(data)) return data;
  if (SINGLE_OBJECT_RESOURCES.has(resource) && data && typeof data === 'object') {
    return [data];
  }
  const rows = (data as { rows?: unknown } | null)?.rows;
  return Array.isArray(rows) ? rows : [];
}

/**
 * Only the Overview resources exist so far. Anything else — merchants, items,
 * categories — will be added as its own set of admin-api actions rather than
 * guessed at here, so an unmapped resource fails loudly instead of silently
 * returning the wrong data.
 */
function actionFor(resource: string): string {
  const action = RESOURCE_ACTION[resource];
  if (!action) {
    throw transportError(
      'UNMAPPED_RESOURCE',
      501,
      `No admin-api action is mapped for "${resource}" yet`,
      `لا يوجد إجراء معيّن للمورد "${resource}" بعد`,
    );
  }
  return action;
}

/**
 * RESOURCES THAT RETURN A SINGLE OBJECT
 *
 *   Refine's getList is shaped for collections, but overview.kpis calls a
 *   function that returns exactly one row. get_platform_kpis (migration 120) is
 *   an aggregate: it has no FROM clause over multiple rows, so there is nothing
 *   to iterate.
 *
 *   Without this mapping the KPI cards render 0 for a platform with real
 *   revenue, because data.rows is undefined and the list resolves to []. The
 *   single row is wrapped so useList sees the same shape as every other
 *   resource and the page can read data.data[0].
 */
const SINGLE_OBJECT_RESOURCES = new Set(['overview-kpis']);

export const dataProvider: DataProvider = {
  getApiUrl: () => ADMIN_API_URL,

  async getList({ resource, pagination, meta }) {
    const payload: Record<string, unknown> = { ...(meta ?? {}) };

    // Refine always sends a pageSize (default 10). meta.limit wins, because the
    // Overview passes the limit it actually means and letting Refine's default
    // overwrite it would silently truncate a future server-side default.
    if (pagination?.pageSize && payload.limit === undefined) {
      payload.limit = pagination.pageSize;
    }

    const data = await call<unknown>(actionFor(resource), payload);
    const rows = toRows(resource, data);

    return {
      data: rows as never,
      // Every Overview query is windowed or clamped server-side, so there is no
      // real total to report; the row count is the honest answer.
      total: rows.length,
    };
  },

  async getOne({ resource, id, meta }) {
    const data = await call<unknown>(actionFor(resource), { id, ...(meta ?? {}) });
    return { data: data as never };
  },

  // Not implemented yet. Throwing beats returning a fake success, which would
  // let the UI believe a write landed when nothing was sent.
  async create() {
    throw transportError('NOT_IMPLEMENTED', 501);
  },
  /**
   * Update, plus merchant approval and publication.
   *
   * Refine's DataProvider has no custom-method concept, so the state machine is
   * reached through `update` with an `action` discriminator in the payload. The
   * demo provider reads the same field, so a screen written against one behaves
   * identically against the other.
   *
   * The plain-update path deliberately refuses the state-machine columns. They
   * are not cosmetic: admin-api enforces publish-requires-approval, and a raw
   * column write would route around the only guard that keeps an unreviewed
   * merchant out of the customer feed.
   */
  async update({ resource, id, variables }) {
    const v = variables as Record<string, unknown>;
    const action = v.action as string | undefined;

    if (resource === 'merchants' && action) {
      const action_name = action as keyof typeof RESOURCE_ACTION;
      const mapped = RESOURCE_ACTION[`merchants.${action_name}` as keyof typeof RESOURCE_ACTION];
      if (!mapped) {
        throw transportError('UNMAPPED_RESOURCE', 501);
      }
      const data = await call<unknown>(mapped, { id, ...v });
      return { data: data as never };
    }

    const mapped = RESOURCE_ACTION[`${resource}.update` as keyof typeof RESOURCE_ACTION];
    if (!mapped) {
      throw transportError('UNMAPPED_RESOURCE', 501);
    }
    const data = await call<unknown>(mapped, { id, ...v });
    return { data: data as never };
  },
  async deleteOne() {
    throw transportError('NOT_IMPLEMENTED', 501);
  },
  async deleteMany() {
    throw transportError('NOT_IMPLEMENTED', 501);
  },
};
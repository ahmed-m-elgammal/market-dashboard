// Edge Function: send-notification
// P3G-01 through P3G-03: Sends in-app notification + push notification
// Called internally by other Edge Functions (service role)
// Rate limited (100/min/caller)
//
// FIX: Push notifications now respect the user's preferred_language from profile.
// Both English and Arabic variants are stored in the in-app notification record.
// The push notification (Expo) uses the user's preferred language for title/body.
// FIX: Service role key auth now uses timing-safe comparison to prevent
// timing attacks that could leak key information.
//
// Production hardening:
//   - Input validation via shared validation module
//   - Request size validation (Content-Length check)
//   - Structured JSON logging with request ID tracking
//   - Timing-safe comparison for service role key auth

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, errorStatus, successResponse } from '../_shared/errors.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { getSupabaseAdmin, fetchWithTimeout } from '../_shared/supabase.ts';
import { authenticate } from '../_shared/auth.ts';
import { validateSendNotificationRequest, validateRequestSize, formatValidationErrors } from '../_shared/validation.ts';
import { createLogger, generateRequestId } from '../_shared/logger.ts';

interface SendNotificationRequest {
  user_id?: string;
  title_en: string;
  title_ar: string;
  body_en: string;
  body_ar: string;
  // Must match the DB CHECK constraint on notifications.type (migration 013).
  // Sprint 0 fix (D01/D02): previous list contained values that don't exist
  // in the DB, causing every insert to fail silently.
  type: 'order_status' | 'order_assigned' | 'order_delivered' | 'order_cancelled'
      | 'promo' | 'driver_verified' | 'driver_rejected' | 'driver_deactivated'
      | 'driver_request' | 'review_request' | 'wallet' | 'general';
  reference_id?: string;
  data?: Record<string, string>;
  push_only?: boolean;
  broadcast?: boolean;
}

/**
 * Timing-safe string comparison to prevent timing attacks.
 * Compares two strings in constant time regardless of content.
 * Returns true if strings are equal, false otherwise.
 */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    // Still do a comparison to maintain constant time for same-length strings
    // For different lengths, the result is always false but we still
    // iterate over the shorter string to avoid length-based timing
    const maxLen = Math.max(a.length, b.length);
    let result = a.length !== b.length ? 1 : 0;
    for (let i = 0; i < maxLen; i++) {
      const charA = i < a.length ? a.charCodeAt(i) : 0;
      const charB = i < b.length ? b.charCodeAt(i) : 0;
      result |= charA ^ charB;
    }
    return result === 0;
  }
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

// Channel mapping helper
function getChannelIdForType(t: string): string {
  switch (t) {
    case 'order_status':
    case 'order_assigned':
    case 'order_delivered':
    case 'order_cancelled':
      return 'order_updates';
    case 'driver_request':
      return 'driver_requests';
    case 'driver_verified':
    case 'driver_rejected':
    case 'driver_deactivated':
      return 'verification';
    case 'promo':
      return 'promotions';
    case 'wallet':
      return 'payment';
    case 'review_request':
    case 'general':
    default:
      return 'system';
  }
}

// Category mapping helper
function getCategoryIdForType(t: string): string | undefined {
  switch (t) {
    case 'order_status':
    case 'order_assigned':
    case 'order_delivered':
    case 'order_cancelled':
      return 'ORDER_STATUS';
    case 'driver_request':
      return 'DRIVER_REQUEST';
    default:
      return undefined;
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'send-notification' });

  try {
    log.info('Request received', { method: req.method });

    // === REQUEST SIZE VALIDATION ===
    const sizeValidation = validateRequestSize(req);
    if (!sizeValidation.valid) {
      log.warn('Request too large', { errors: sizeValidation.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', { message_en: formatValidationErrors(sizeValidation.errors) }),
        413,
        undefined,
        req,
      );
    }

    // Auth: SERVICE ROLE ONLY.
    // This function is called internally by other Edge Functions (place-order,
    // driver-actions, admin-driver) using the service role key. It must NEVER
    // accept an authenticated-but-not-service-role caller, because the
    // `body.user_id` is the notification's recipient — a regular user could
    // otherwise push arbitrary notifications to any other user's device.
    // (Sprint 0 security fix — S03.)
    const authHeader = req.headers.get('Authorization');
    const authResult = await authenticate(authHeader);
    let isServiceRole = false;

    if (authResult.error) {
      // Caller did not present a valid user JWT — fall through to service-role
      // key check below. This is the path the internal callers take.
      const authKey = authHeader?.replace('Bearer ', '') || '';
      const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
      if (!timingSafeEqual(authKey, serviceKey)) {
        log.warn('Auth failed — invalid token or service key');
        return corsResponse(authResult.error, errorStatus(authResult.error.error.code), undefined, req);
      }
      isServiceRole = true;
    } else {
      // Caller presented a valid user JWT. Reject — only service role may send
      // notifications on behalf of the platform.
      log.warn('Rejected authenticated caller — send-notification is service-role only', {
        userId: authResult.data?.userId,
      });
      return corsResponse(errorResponse('FORBIDDEN'), 403, undefined, req);
    }

    log.info('Authenticated', {
      userId: authResult.data?.userId || 'service-role',
      isServiceRole,
    });

    // Rate limit by caller (bypass for service role calls)
    if (!isServiceRole) {
      const callerKey = authResult.data?.userId || 'service';
      const rl = checkRateLimit(`notify:${callerKey}`, RATE_LIMITS.SEND_NOTIFICATION);
      if (!rl.allowed) {
        log.warn('Rate limited', { callerKey, retryAfterMs: rl.retryAfterMs });
        return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
      }
    }

    // Parse and validate request body
    const rawBody = await req.text();
    let body: SendNotificationRequest;
    try {
      body = JSON.parse(rawBody);
    } catch {
      log.warn('Invalid JSON body');
      return corsResponse(errorResponse('VALIDATION_ERROR', { message_en: 'Invalid JSON in request body' }), 400, undefined, req);
    }

    // === INPUT VALIDATION ===
    const validation = validateSendNotificationRequest(body);
    if (!validation.valid) {
      log.warn('Validation failed', { errors: validation.errors });
      return corsResponse(
        errorResponse('VALIDATION_ERROR', { message_en: formatValidationErrors(validation.errors) }),
        400,
        undefined,
        req,
      );
    }

    const { user_id, title_en, title_ar, body_en, body_ar, type, reference_id, data, push_only, broadcast } = body;

    const supabase = getSupabaseAdmin();

    // =========================================================================
    // BROADCAST PATH (Send to all users)
    // =========================================================================
    if (broadcast) {
      log.info('Starting broadcast notification campaign', { type });

      // Fetch all profiles
      const { data: profiles, error: profileError } = await supabase
        .from('profiles')
        .select('id, expo_push_token, preferred_language');

      if (profileError || !profiles) {
        log.error('Failed to fetch profiles for broadcast', { error: profileError?.message });
        return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
      }

      log.info('Profiles retrieved for broadcast', { count: profiles.length });

      const CONCURRENCY_LIMIT = 5;

      // 1. Bulk insert in-app notifications (unless push_only is true)
      if (!push_only && profiles.length > 0) {
        const insertPayloads = profiles.map((p) => ({
          user_id: p.id,
          type: type || 'general',
          title_en,
          title_ar: title_ar || title_en,
          body_en,
          body_ar: body_ar || body_en,
          data: data || null,
          reference_id: reference_id || null,
          is_read: false,
        }));

        // Chunk insertions
        const insertChunks: any[][] = [];
        for (let i = 0; i < insertPayloads.length; i += 500) {
          insertChunks.push(insertPayloads.slice(i, i + 500));
        }

        // Parallelize bulk DB inserts with a concurrency limit
        for (let i = 0; i < insertChunks.length; i += CONCURRENCY_LIMIT) {
          const group = insertChunks.slice(i, i + CONCURRENCY_LIMIT);
          await Promise.all(
            group.map(async (chunk) => {
              const { error: bulkInsertError } = await supabase
                .from('notifications')
                .insert(chunk);
              if (bulkInsertError) {
                log.error('Bulk in-app insert chunk failed', { error: bulkInsertError.message });
              }
            })
          );
        }
        log.info('Broadcast in-app notifications created in DB', { count: profiles.length });
      }

      // 2. Batch send push notifications via Expo (only users with tokens)
      const pushProfiles = profiles.filter((p) => p.expo_push_token);
      const tickets: string[] = [];

      if (pushProfiles.length > 0) {
        const pushMessages = pushProfiles.map((p) => {
          const preferredLanguage = p.preferred_language || 'en';
          const pushTitle = preferredLanguage === 'ar' ? (title_ar || title_en) : title_en;
          const pushBody = preferredLanguage === 'ar' ? (body_ar || body_en) : body_en;

          const payload: Record<string, unknown> = {
            to: p.expo_push_token,
            title: pushTitle,
            body: pushBody,
            data: {
              type,
              reference_id: reference_id || undefined,
              ...data,
            },
            sound: 'default',
            channelId: getChannelIdForType(type),
          };

          const categoryId = getCategoryIdForType(type);
          if (categoryId) {
            payload.categoryId = categoryId;
          }
          return payload;
        });

        // Chunk push messages
        const pushChunks: any[][] = [];
        for (let i = 0; i < pushMessages.length; i += 100) {
          pushChunks.push(pushMessages.slice(i, i + 100));
        }

        // Parallelize push requests to Expo with a concurrency limit
        for (let i = 0; i < pushChunks.length; i += CONCURRENCY_LIMIT) {
          const group = pushChunks.slice(i, i + CONCURRENCY_LIMIT);
          await Promise.all(
            group.map(async (chunk) => {
              try {
                const pushRes = await fetchWithTimeout('https://exp.host/--/api/v2/push/send', {
                  method: 'POST',
                  headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                  },
                  body: JSON.stringify(chunk),
                });

                const pushData = await pushRes.json();
                if (pushData.data) {
                  pushData.data.forEach((ticket: any) => {
                    if (ticket.id) tickets.push(ticket.id);
                  });
                }
              } catch (pushError) {
                log.error('Failed to send push batch to Expo', { error: String(pushError) });
              }
            })
          );
        }
        log.info('Broadcast push messages completed', { pushRecipients: pushProfiles.length, ticketsCreated: tickets.length });
      }

      return corsResponse(successResponse({
        broadcast: true,
        recipients_count: profiles.length,
        push_tickets_count: tickets.length,
      }), 201, undefined, req);
    }

    // =========================================================================
    // SINGLE RECIPIENT PATH (Default)
    // =========================================================================

    // Fetch user profile to get preferred_language AND expo_push_token in one query
    const { data: profile } = await supabase
      .from('profiles')
      .select('expo_push_token, preferred_language')
      .eq('id', user_id)
      .single();

    const preferredLanguage = profile?.preferred_language || 'en';

    // Insert in-app notification (unless push_only is requested)
    let notificationId: string | null = null;
    if (!push_only) {
      const { data: notification, error: insertError } = await supabase
        .from('notifications')
        .insert({
          user_id,
          type: type || 'general',
          title_en,
          title_ar: title_ar || title_en,
          body_en,
          body_ar: body_ar || body_en,
          data: data || null,
          reference_id: reference_id || null,
          is_read: false,
        })
        .select('id')
        .single();

      if (insertError) {
        log.error('Notification insert error', { error: insertError.message, userId: user_id });
        return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
      }
      notificationId = notification.id;
      log.info('In-app notification created', { notificationId, userId: user_id, type });
    } else {
      log.info('Push-only notification requested, skipping DB insert', { userId: user_id, type });
    }

    // Query exact unread count to update the app icon badge count
    let unreadCount = 0;
    const { count: dbUnreadCount, error: countError } = await supabase
      .from('notifications')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', user_id)
      .eq('is_read', false);

    if (countError) {
      log.warn('Failed to query unread count for badge', { error: countError.message, userId: user_id });
    } else {
      unreadCount = dbUnreadCount || 0;
    }

    // Send push notification via Expo Push API
    let pushSent = false;
    let pushDeliveryId: string | undefined;

    try {
      if (profile?.expo_push_token) {
        // Select language based on user preference
        const pushTitle = preferredLanguage === 'ar' ? (title_ar || title_en) : title_en;
        const pushBody = preferredLanguage === 'ar' ? (body_ar || body_en) : body_en;

        const payload: Record<string, unknown> = {
          to: profile.expo_push_token,
          title: pushTitle,
          body: pushBody,
          data: {
            type,
            reference_id: reference_id || undefined,
            ...data,
          },
          sound: 'default',
          badge: unreadCount,
          channelId: getChannelIdForType(type),
        };

        const categoryId = getCategoryIdForType(type);
        if (categoryId) {
          payload.categoryId = categoryId;
        }

        const pushRes = await fetchWithTimeout('https://exp.host/--/api/v2/push/send', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: JSON.stringify(payload),
        });

        const pushData = await pushRes.json();
        if (pushData.data) {
          pushSent = true;
          pushDeliveryId = pushData.data.id;
        }

        log.info('Push notification sent', { pushSent, userId: user_id, preferredLanguage, unreadCount });
      }
    } catch (pushError) {
      log.error('Push notification error', {
        error: pushError instanceof Error ? pushError.message : String(pushError),
        userId: user_id,
      });
      // Don't fail — the operation should complete regardless of push API delivery
    }

    return corsResponse(successResponse({
      notification_id: notificationId,
      push_sent: pushSent,
      push_delivery_id: pushDeliveryId,
    }), 201, undefined, req);
  } catch (err) {
    log.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});

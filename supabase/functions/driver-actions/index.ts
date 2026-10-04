// Edge Function: driver-actions
// COMBINED: assign-driver + driver-respond + update-location + complete-delivery
// Routes by `action` field: 'assign' | 'respond' | 'update_location' | 'complete_delivery'
//
// PRODUCTION FIXES:
// - Removed duplicate haversine (imports from _shared/geo.ts)
// - Driver location update uses SQL-only skip optimization (no SELECT before UPDATE)
// - Atomic increment for driver stats (via RPC with read-then-write fallback)
// - Promo usage increment removed (authoritative at order creation in place_order_with_items RPC, migration 049 — gap A1-G1)
// - Input validation on all actions via validateDriverActionsRequest
// - Request size limits enforced
// - Structured JSON logging with request ID and timing
// - Timing-safe service role key comparison for assign action
// - Optimistic concurrency on assign-driver to prevent double-assignment

import { corsResponse, handleOptions } from '../_shared/cors.ts';
import { errorResponse, errorStatus, successResponse } from '../_shared/errors.ts';
import { checkRateLimit, RATE_LIMITS } from '../_shared/rate-limit.ts';
import { getSupabaseAdmin, fetchWithTimeout } from '../_shared/supabase.ts';
import { haversineDistanceKm } from '../_shared/geo.ts'; // FIX: use shared import, removed inline copy
import { authenticate, requireRole, requireVerifiedDriver } from '../_shared/auth.ts';
import { validateDriverActionsRequest, validateRequestSize, formatValidationErrors } from '../_shared/validation.ts';
import { createLogger, generateRequestId, measure } from '../_shared/logger.ts';

// ---------------------------------------------------------------------------
// Timing-safe string comparison to prevent timing attacks on key comparison.
// Constant-time for equal-length strings (service role keys have fixed length).
// ---------------------------------------------------------------------------
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

// ---------------------------------------------------------------------------
// Required database migration for atomic driver-stats increment (RED-03):
//   increment_driver_stats(p_driver_id UUID, p_earnings NUMERIC) — migration 038
//   (hardened in migration 044). Used by handleCompleteDelivery.
//
// Promo usage is NOT incremented here — it is incremented atomically by the
// place_order_with_items RPC (migration 049) at order creation time. See
// gap A1-G1 in session-a-order-mutation-paths-analysis.md.
// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions(req);

  const requestId = generateRequestId();
  const log = createLogger({ requestId, functionName: 'driver-actions' });
  const startTime = performance.now();

  try {
    // FIX: Request size validation
    const sizeCheck = validateRequestSize(req);
    if (!sizeCheck.valid) {
      log.warn('Request size exceeded', { errors: sizeCheck.errors });
      return corsResponse(errorResponse('VALIDATION_ERROR', {
        message_en: formatValidationErrors(sizeCheck.errors),
        message_ar: 'حجم الطلب كبير جداً',
      }), 413, undefined, req);
    }

    const body = await req.json();
    const action = body.action as string;

    // FIX: Input validation on all actions
    const validation = validateDriverActionsRequest(body);
    if (!validation.valid) {
      log.warn('Validation failed', { action, errors: validation.errors });
      return corsResponse(errorResponse('VALIDATION_ERROR', {
        message_en: formatValidationErrors(validation.errors),
        message_ar: 'بيانات الإدخال غير صالحة',
      }), 400, undefined, req);
    }

    let response: Response;
    switch (action) {
      case 'assign':
        response = await handleAssignDriver(body, req, log);
        break;
      case 'respond':
        response = await handleDriverRespond(body, req, log);
        break;
      case 'update_location':
        response = await handleUpdateLocation(body, req, log);
        break;
      case 'complete_delivery':
        response = await handleCompleteDelivery(body, req, log);
        break;
      case 'mark_picked_up':
        response = await handleMarkPickedUp(body, req, log);
        break;
      case 'mark_on_the_way':
        response = await handleMarkOnTheWay(body, req, log);
        break;
      default:
        response = corsResponse(errorResponse('VALIDATION_ERROR', {
          message_en: `Unknown action: ${action}. Valid: assign, respond, update_location, complete_delivery, mark_picked_up, mark_on_the_way`,
          message_ar: `إجراء غير معروف: ${action}`,
        }), 400, undefined, req);
    }

    const duration = Math.round(performance.now() - startTime);
    log.info('Request completed', { action, durationMs: duration });

    return response;
  } catch (err) {
    const duration = Math.round(performance.now() - startTime);
    log.error('Unhandled error', {
      durationMs: duration,
      error: err instanceof Error ? err.message : String(err),
    });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }
});

// ============================================================
// ASSIGN DRIVER (P3E-01 through P3E-04)
// Called by place-order (service role) or admin
// FIX: Uses timing-safe key comparison, structured logging
// FIX: Optimistic concurrency — update only if driver_id is still null
// ============================================================
async function handleAssignDriver(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  // FIX: Auth — try admin role first, then timing-safe service role key check
  const authHeader = req.headers.get('Authorization');
  const authResult = await authenticate(authHeader);

  if (authResult.error) {
    // Auth failed — might be a service role key (no profile in auth.users)
    // Use timing-safe comparison to avoid leaking key via timing or logs
    const token = authHeader?.replace('Bearer ', '') ?? '';
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    if (!timingSafeEqual(token, serviceKey)) {
      log.warn('Assign auth failed', { reason: 'invalid_credentials' });
      return corsResponse(errorResponse('FORBIDDEN'), 403, undefined, req);
    }
    // Service role key matches — allow internal call
    log.info('Authenticated via service role key');
  } else if (authResult.data!.role !== 'admin' && authResult.data!.role !== 'service_role') {
    log.warn('Assign auth failed', {
      reason: 'insufficient_role',
      role: authResult.data!.role,
    });
    return corsResponse(errorResponse('FORBIDDEN'), 403, undefined, req);
  }

  // Rate limit
  const rl = checkRateLimit('assign-driver:system', RATE_LIMITS.ASSIGN_DRIVER);
  if (!rl.allowed) {
    log.warn('Rate limited', { key: 'assign-driver:system' });
    return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
  }

  const orderId = body.order_id as string;
  const merchantLat = body.merchant_lat as number;
  const merchantLng = body.merchant_lng as number;
  const maxRadiusKm = (body.max_radius_km as number) || 5;

  const supabase = getSupabaseAdmin();

  // Check order hasn't already been assigned (prevent double-assignment race)
  const { data: existingOrder } = await measure('check-existing-order', () =>
    supabase
      .from('orders')
      .select('id, driver_id, status')
      .eq('id', orderId)
      .single(),
  log);

  if (existingOrder?.driver_id) {
    log.info('Order already assigned', { orderId, driverId: existingOrder.driver_id });
    return corsResponse(successResponse({
      assigned: false,
      reason: 'already_assigned',
      order_id: orderId,
      driver_id: existingOrder.driver_id,
    }));
  }

  // Find nearest online + verified + active drivers.
  // A4-G6: also exclude suspended drivers via suspended_until filter.
  //   The suspension logic (handleDriverRespond decline path) sets
  //   is_online=false when suspending, so .eq('is_online', true) already
  //   excludes them. However, if a future bug or migration accidentally
  //   allows is_online=true while suspended_until > NOW(), this filter
  //   prevents assigning orders to suspended drivers — defense in depth.
  const nowIso = new Date().toISOString();
  const { data: candidates, error: driverError } = await measure('find-candidates', () =>
    supabase
      .from('drivers')
      .select('id, current_lat, current_lng')
      .eq('is_online', true)
      .eq('is_verified', true)
      .eq('is_active', true)
      .not('current_lat', 'is', null)
      .not('current_lng', 'is', null)
      .or(`suspended_until.is.null,suspended_until.lt.${nowIso}`),
  log);

  if (driverError) {
    log.error('Driver query error', { error: driverError.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  if (!candidates || candidates.length === 0) {
    log.info('No online drivers', { orderId });
    return corsResponse(successResponse({
      assigned: false,
      reason: 'no_online_drivers',
      order_id: orderId,
    }));
  }

  // Filter by distance and sort
  const driversWithDistance = candidates
    .map((d: { id: string; current_lat: number; current_lng: number }) => {
      const lat = d.current_lat;
      const lng = d.current_lng;
      const distKm = haversineDistanceKm(merchantLat, merchantLng, lat, lng);
      return { ...d, distance_km: distKm };
    })
    .filter((d: { distance_km: number }) => d.distance_km <= maxRadiusKm)
    .sort((a: { distance_km: number }, b: { distance_km: number }) => a.distance_km - b.distance_km);

  if (driversWithDistance.length === 0) {
    log.info('No drivers in range', { orderId, maxRadiusKm });
    return corsResponse(successResponse({
      assigned: false,
      reason: 'no_drivers_in_range',
      order_id: orderId,
    }));
  }

  // Check which drivers don't have active orders
  const candidateIds = driversWithDistance.slice(0, 5).map((d: { id: string }) => d.id);
  const { data: activeOrders } = await measure('check-active-orders', () =>
    supabase
      .from('orders')
      .select('driver_id')
      .in('driver_id', candidateIds)
      .in('status', ['pending', 'confirmed', 'preparing', 'ready', 'picked_up', 'on_the_way']),
  log);

  const busyDriverIds = new Set((activeOrders || []).map((o: { driver_id: string }) => o.driver_id));
  const availableDrivers = driversWithDistance.filter((d: { id: string }) => !busyDriverIds.has(d.id));

  if (availableDrivers.length === 0) {
    log.info('All drivers busy', { orderId, candidateCount: candidateIds.length });
    return corsResponse(successResponse({
      assigned: false,
      reason: 'all_drivers_busy',
      order_id: orderId,
    }));
  }

  // Assign the nearest available driver
  const driver = availableDrivers[0];

  // Optimistic concurrency — only update if driver_id is still null AND the
  // order is in a pre-delivery status. A3-G4: without the status check, this
  // UPDATE could un-cancel a cancelled order (driver_id is null on cancelled
  // orders, so the .is('driver_id', null) guard alone is insufficient).
  const { data: updatedOrder, error: updateError } = await measure('assign-driver', () =>
    supabase
      .from('orders')
      .update({
        driver_id: driver.id,
        status: 'confirmed',
      })
      .eq('id', orderId)
      .is('driver_id', null) // Only update if no driver assigned yet
      .in('status', ['pending', 'confirmed']) // A3-G4: don't assign to cancelled/delivered/post-pickup
      .select('id, driver_id')
      .single(),
  log);

  if (updateError || !updatedOrder) {
    // Order was already assigned by a concurrent request, or the order is no
    // longer in a valid status for assignment (cancelled, delivered, etc.)
    log.info('Concurrent assignment or invalid status', { orderId });
    return corsResponse(successResponse({
      assigned: false,
      reason: 'already_assigned_concurrent',
      order_id: orderId,
    }));
  }

  // A4-G4: Persist the assignment request for audit trail.
  await measure('insert-driver-order-request', () =>
    supabase
      .from('driver_order_requests')
      .insert({
        order_id: orderId,
        driver_id: driver.id,
        status: 'pending',
      }),
  log);

  // B2-G3: Broadcast the new assignment request to the driver's realtime
  // channel. The mobile app subscribes to `driver-requests:{driverId}` via
  // a broadcast channel (apps/mobile/lib/realtime.ts:subscribeToDriverRequests).
  // Without this broadcast, the driver never receives a push notification for
  // the assignment — they would only see it on the next manual refresh.
  // Fire-and-forget: a broadcast failure must NOT block the assignment.
  try {
    const channel = supabase.channel(`driver-requests:${driver.id}`);
    await channel.subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        channel.send({
          type: 'broadcast',
          event: 'new-order-request',
          payload: {
            order_id: orderId,
            order_number: existingOrder.order_number,
            merchant_name: '', // populated by the driver's accept response
            pickup_address: '',
            delivery_address: '',
            estimated_fee: 0,
            expires_at: new Date(Date.now() + 30_000).toISOString(),
          },
        });
      }
    });
    // Remove the channel after a short delay to allow the broadcast to flush.
    // The channel is ephemeral — we only need it long enough to send the event.
    setTimeout(() => {
      try { supabase.removeChannel(channel); } catch { /* ignore */ }
    }, 5_000);
  } catch (err) {
    log.warn('Failed to broadcast driver request', {
      driverId: driver.id,
      orderId,
      error: err instanceof Error ? err.message : String(err),
    });
  }

  // A4-G5: Explicit order_status_history insert with actor.
  // The DB trigger on_order_status_change (migration 018, modified by 060)
  // fires for non-cancel transitions but sets changed_by=NULL and
  // changed_by_role=NULL — the admin timeline shows "Status changed from
  // pending to confirmed" with no indication of who triggered it.
  // We insert an explicit row with changed_by=driver.id and
  // changed_by_role='system' so the timeline identifies the auto-assign
  // system as the actor. (Only inserted when status actually changed from
  // 'pending' to 'confirmed'; if the order was already 'confirmed', the
  // trigger doesn't fire and we don't need a history row for re-assignment.)
  if (existingOrder.status === 'pending') {
    await measure('insert-assign-history', () =>
      supabase
        .from('order_status_history')
        .insert({
          order_id: orderId,
          status: 'confirmed',
          changed_by: driver.id,
          changed_by_role: 'system',
          note: 'Auto-assigned to driver by driver-actions EF',
        }),
    log);
  }

  // Get driver profile for name
  const { data: driverProfile } = await measure('get-driver-profile', () =>
    supabase
      .from('profiles')
      .select('full_name')
      .eq('id', driver.id)
      .single(),
  log);

  log.info('Driver assigned', {
    orderId,
    driverId: driver.id,
    distanceMeters: Math.round(driver.distance_km * 1000),
  });

  return corsResponse(successResponse({
    assigned: true,
    driver_id: driver.id,
    driver_name: driverProfile?.full_name || 'Driver',
    distance_meters: Math.round(driver.distance_km * 1000),
    request_expires_at: new Date(Date.now() + 30_000).toISOString(),
  }));
}

// ============================================================
// DRIVER RESPOND TO ORDER (P3E-05 through P3E-08)
// Driver accepts or declines an order request
// ============================================================
async function handleDriverRespond(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  const authResult = await requireVerifiedDriver(req.headers.get('Authorization'));
  if (authResult.error) {
    return corsResponse(authResult.error, authResult.status || 403, undefined, req);
  }

  const driverId = authResult.data!.driverId;

  // Rate limit
  const rl = checkRateLimit(`respond:${driverId}`, RATE_LIMITS.DRIVER_RESPOND);
  if (!rl.allowed) {
    log.warn('Rate limited', { key: `respond:${driverId}` });
    return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
  }

  const orderId = body.order_id as string;
  const action = body.driver_action as 'accept' | 'decline';

  const supabase = getSupabaseAdmin();

  // Check order exists and is assigned to this driver
  const { data: order, error: orderError } = await measure('get-order', () =>
    supabase
      .from('orders')
      .select('id, status, driver_id, customer_id, order_number, merchant_id, delivery_address, total, payment_method')
      .eq('id', orderId)
      .single(),
  log);

  if (orderError || !order) {
    log.warn('Order not found', { orderId });
    return corsResponse(errorResponse('ORDER_NOT_FOUND'), 404, undefined, req);
  }

  if (action === 'accept') {
    if (order.driver_id && order.driver_id !== driverId) {
      log.warn('Order already taken by another driver', { orderId, assignedTo: order.driver_id });
      return corsResponse(errorResponse('ORDER_ALREADY_TAKEN'), 409, undefined, req);
    }
    if (order.status === 'cancelled' || order.status === 'delivered') {
      log.warn('Order in invalid status for accept', { orderId, status: order.status });
      return corsResponse(errorResponse('ORDER_INVALID_STATUS'), 400, undefined, req);
    }

    // Assign driver and update status. A3-G2: guard with .eq('status', order.status)
    // so the UPDATE is a no-op if the order was cancelled (or transitioned to
    // any other status) between the read above and this write. Without this
    // guard, a driver accept could un-cancel a cancelled order.
    const { count, error: updateError } = await measure('accept-order', () =>
      supabase
        .from('orders')
        .update({
          driver_id: driverId,
          status: 'confirmed',
        }, { count: 'exact' })
        .eq('id', orderId)
        .eq('status', order.status),
    log);

    if (updateError) {
      log.error('Order accept update error', { orderId, error: updateError.message });
      return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
    }

    if (count === 0) {
      // Status changed between read and write — order was likely cancelled concurrently.
      log.warn('Order status changed during accept', { orderId, readStatus: order.status });
      return corsResponse(errorResponse('ORDER_INVALID_STATUS', {
        message_en: 'Order status has changed, cannot accept.',
        message_ar: 'تغيرت حالة الطلب، لا يمكن القبول.',
      }), 409, undefined, req);
    }

    // A4-G4: Update the driver_order_requests row from 'pending' to 'accepted'.
    await measure('update-driver-order-request-accepted', () =>
      supabase
        .from('driver_order_requests')
        .update({ status: 'accepted', responded_at: new Date().toISOString() })
        .eq('order_id', orderId)
        .eq('driver_id', driverId)
        .eq('status', 'pending'),
    log);

    // A4-G5: Explicit order_status_history insert with actor.
    // Only inserted when the status actually changed (e.g., pending → confirmed).
    // If the order was already 'confirmed' (driver re-accepting after a
    // previous accept), no history row is needed.
    if (order.status !== 'confirmed') {
      await measure('insert-accept-history', () =>
        supabase
          .from('order_status_history')
          .insert({
            order_id: orderId,
            status: 'confirmed',
            changed_by: driverId,
            changed_by_role: 'driver',
            note: 'Order accepted by driver',
          }),
      log);
    }

    // Reset decline counter on successful acceptance
    await supabase
      .from('drivers')
      .update({ consecutive_declines: 0 })
      .eq('id', driverId);

    // Get merchant info for driver
    const { data: merchant } = await measure('get-merchant', () =>
      supabase
        .from('merchants')
        .select('name_en, name_ar, address, lat, lng')
        .eq('id', order.merchant_id)
        .single(),
    log);

    const deliveryAddr = order.delivery_address as Record<string, unknown>;

    log.info('Order accepted', { orderId, driverId });

    // Fire-and-forget: send notification to customer
    try {
      const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`;
      const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
      fetchWithTimeout(functionUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
        body: JSON.stringify({
          user_id: order.customer_id,
          title_en: 'Driver Assigned',
          title_ar: 'تم تعيين سائق',
          body_en: `A driver has accepted your order #${order.order_number} and is heading to the store.`,
          body_ar: `قبل السائق طلبك #${order.order_number} وهو في طريقه إلى المتجر.`,
          type: 'order_status',
          reference_id: orderId,
        }),
      }).catch(() => {});
    } catch { /* silent */ }

    return corsResponse(successResponse({
      accepted: true,
      order_id: orderId,
      merchant_name: merchant?.name_en || '',
      merchant_address: merchant?.address || '',
      merchant_lat: merchant?.lat,
      merchant_lng: merchant?.lng,
      customer_address: (deliveryAddr?.address as string) || '',
      customer_lat: deliveryAddr?.lat as number,
      customer_lng: deliveryAddr?.lng as number,
      order_total: order.total,
      payment_method: order.payment_method,
    }));
  } else {
    // Decline — try next driver
    log.info('Order declined', { orderId, driverId });

    // A4-G4: Update the driver_order_requests row from 'pending' to 'declined'.
    await measure('update-driver-order-request-declined', () =>
      supabase
        .from('driver_order_requests')
        .update({ status: 'declined', responded_at: new Date().toISOString() })
        .eq('order_id', orderId)
        .eq('driver_id', driverId)
        .eq('status', 'pending'),
    log);

    // A4-G2: Atomically increment consecutive_declines via RPC.
    // Previously used a non-atomic read-then-write (SELECT current → compute
    // +1 → UPDATE) which lost increments under concurrent declines by the
    // same driver. The new increment_driver_declines RPC (migration 062)
    // does a single atomic UPDATE ... RETURNING and returns the new count.
    // The suspension logic (3-strike → suspend + kick offline + reset) stays
    // here in the EF because it involves a timestamp computation that's
    // cleaner in TypeScript, but the counter is now race-free.
    try {
      const { data: newCount, error: rpcErr } = await measure('increment-driver-declines', () =>
        supabase.rpc('increment_driver_declines', { p_driver_id: driverId }),
      log);

      if (rpcErr) {
        log.warn('increment_driver_declines RPC not available, skipping suspension', {
          error: rpcErr.message,
          note: 'Deploy migration 062 to enable atomic decline tracking',
        });
      } else if ((newCount ?? 0) >= 3) {
        // Apply 3-strike suspension: kick offline + suspend 1 hour + reset counter.
        const suspendedUntil = new Date(Date.now() + 60 * 60 * 1000).toISOString();
        await supabase
          .from('drivers')
          .update({
            suspended_until: suspendedUntil,
            is_online: false,
            consecutive_declines: 0,
          })
          .eq('id', driverId);
        log.warn('Driver suspended due to 3 consecutive declines', { driverId, suspendedUntil });
      }
    } catch (err) {
      log.error('Decline counter increment failed', { error: String(err) });
    }

    // Fire-and-forget: try to assign another driver.
    // A4-G3: wrap the fetch in EdgeRuntime.waitUntil so the Deno Edge Runtime
    // doesn't terminate the isolate before the re-assign request completes.
    // Previously this was a naked fetchWithTimeout(...).catch(() => {}) that
    // the runtime could kill when the function returned — the re-assignment
    // silently failed and the order sat with no driver. Mirrors the pattern
    // in place-order/index.ts:360-421.
    try {
      const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/driver-actions`;
      const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
      const { data: merchant } = await supabase
        .from('merchants')
        .select('lat, lng')
        .eq('id', order.merchant_id)
        .single();

      if (merchant) {
        const reassignPromise = fetchWithTimeout(functionUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
          body: JSON.stringify({
            action: 'assign',
            order_id: orderId,
            merchant_lat: merchant.lat,
            merchant_lng: merchant.lng,
          }),
        }).then((res) => {
          if (!res.ok) {
            log.warn('decline re-assign returned non-OK', { status: res.status });
          }
        }).catch((err) => {
          log.warn('decline re-assign failed', {
            error: err instanceof Error ? err.message : String(err),
          });
        });

        // Keep the promise alive past the HTTP response so the runtime
        // doesn't kill the isolate mid-fetch. Falls back to inline await
        // if EdgeRuntime.waitUntil isn't available (older runtime).
        try {
          (EdgeRuntime as { waitUntil?: (p: Promise<unknown>) => void }).waitUntil?.(reassignPromise);
        } catch {
          await Promise.allSettled([reassignPromise]);
        }
      }
    } catch { /* silent */ }

    return corsResponse(successResponse({
      accepted: false,
      order_id: orderId,
      next_action: 'waiting_for_another_driver',
    }));
  }
}

// ============================================================
// UPDATE DRIVER LOCATION (P3E-09 through P3E-11)
// Fast, targeted UPDATE on lat/lng/last_location_at only
// FIX: SQL-only skip optimization — single UPDATE with WHERE clause
//      eliminates the SELECT query entirely (RED-03)
// ============================================================
async function handleUpdateLocation(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  const authResult = await requireVerifiedDriver(req.headers.get('Authorization'));
  if (authResult.error) {
    return corsResponse(authResult.error, authResult.status || 403, undefined, req);
  }

  const driverId = authResult.data!.driverId;

  // Rate limit
  const rl = checkRateLimit(`location:${driverId}`, RATE_LIMITS.DRIVER_LOCATION);
  if (!rl.allowed) {
    log.warn('Rate limited', { key: `location:${driverId}` });
    return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
  }

  const lat = body.lat as number;
  const lng = body.lng as number;

  const supabase = getSupabaseAdmin();

  // FIX: SQL-only skip optimization (RED-03)
  // Instead of SELECT → check → UPDATE, we do a single UPDATE with a WHERE
  // clause that only matches rows where the location changed enough or the
  // last update was stale. If 0 rows are affected, the location was unchanged.
  //
  // Equivalent SQL:
  //   UPDATE drivers SET current_lat = $1, current_lng = $2, last_location_at = NOW()
  //   WHERE id = $3 AND (
  //     current_lat IS NULL OR current_lng IS NULL
  //     OR ABS(current_lat - $1) > 0.00005  -- ~5m latitude change
  //     OR ABS(current_lng - $2) > 0.00005  -- ~5m longitude change
  //     OR last_location_at < NOW() - INTERVAL '3 seconds'
  //   )
  //
  // PostgREST doesn't support ABS() in filters, so we express it as:
  //   current_lat < lat - delta OR current_lat > lat + delta (same as ABS check)
  const LOCATION_DELTA = 0.00005; // ~5 meters
  const threeSecondsAgo = new Date(Date.now() - 3000).toISOString();
  const now = new Date().toISOString();

  const { count, error: updateError } = await measure('update-location', () =>
    supabase
      .from('drivers')
      .update({
        current_lat: lat,
        current_lng: lng,
        last_location_at: now,
      }, { count: 'exact' })
      .eq('id', driverId)
      .or(
        `current_lat.is.null,current_lng.is.null,` +
        `current_lat.lt.${lat - LOCATION_DELTA},current_lat.gt.${lat + LOCATION_DELTA},` +
        `current_lng.lt.${lng - LOCATION_DELTA},current_lng.gt.${lng + LOCATION_DELTA},` +
        `last_location_at.lt.${threeSecondsAgo}`,
      ),
  log);

  if (updateError) {
    log.error('Location update error', { driverId, error: updateError.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  // If count is 0, the location was unchanged — this is a skip, not an error
  const skipped = count === 0;
  log.debug('Location update', { driverId, skipped });

  return corsResponse(successResponse({ updated: true, skipped }));
}

// ============================================================
// COMPLETE DELIVERY (P3E-12 through P3E-17)
// Driver confirms delivery, calculate earnings, update statuses
// FIX: Atomic increments for driver stats and promo usage (RED-03)
// FIX: Uses RPC with read-then-write fallback + race condition comment
// ============================================================
async function handleCompleteDelivery(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  const authResult = await requireVerifiedDriver(req.headers.get('Authorization'));
  if (authResult.error) {
    return corsResponse(authResult.error, authResult.status || 403, undefined, req);
  }

  const driverId = authResult.data!.driverId;

  // Rate limit
  const rl = checkRateLimit(`complete:${driverId}`, RATE_LIMITS.COMPLETE_DELIVERY);
  if (!rl.allowed) {
    log.warn('Rate limited', { key: `complete:${driverId}` });
    return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
  }

  const orderId = body.order_id as string;

  const supabase = getSupabaseAdmin();

  // Validate order belongs to this driver and status is 'on_the_way'
  const { data: order, error: orderError } = await measure('get-order', () =>
    supabase
      .from('orders')
      .select('id, driver_id, status, payment_method, payment_status, delivery_fee, promo_code_id, customer_id')
      .eq('id', orderId)
      .single(),
  log);

  if (orderError || !order) {
    log.warn('Order not found', { orderId });
    return corsResponse(errorResponse('ORDER_NOT_FOUND'), 404, undefined, req);
  }

  if (order.driver_id !== driverId) {
    log.warn('Order not assigned to this driver', { orderId, driverId, assignedTo: order.driver_id });
    return corsResponse(errorResponse('ORDER_NOT_ASSIGNED_TO_YOU'), 400, undefined, req);
  }

  if (order.status !== 'on_the_way') {
    log.warn('Order in invalid status for completion', { orderId, status: order.status });
    return corsResponse(errorResponse('ORDER_INVALID_STATUS', {
      message_en: `Order status is '${order.status}', expected 'on_the_way'`,
      message_ar: `حالة الطلب '${order.status}'، المتوقعة 'في الطريق'`,
    }), 400, undefined, req);
  }

  // Get driver earnings config
  const { data: earningsPctConfig } = await measure('get-earnings-config', () =>
    supabase
      .from('platform_config')
      .select('value')
      .eq('key', 'driver_earnings_pct')
      .single(),
  log);
  const earningsPct = Number(earningsPctConfig?.value || 80) / 100;

  const { data: minEarningsConfig } = await measure('get-min-earnings-config', () =>
    supabase
      .from('platform_config')
      .select('value')
      .eq('key', 'driver_min_earnings')
      .single(),
  log);
  const minEarnings = Number(minEarningsConfig?.value || 10);

  // Calculate driver earnings: delivery_fee * earnings_pct
  const deliveryFee = Number(order.delivery_fee) || 0;
  const driverEarnings = Math.max(deliveryFee * earningsPct, minEarnings);
  const platformFeeFromDelivery = deliveryFee - driverEarnings;

  // Update order status
  const now = new Date().toISOString();
  const { count, error: updateOrderError } = await measure('update-order-status', () =>
    supabase
      .from('orders')
      .update({
        status: 'delivered',
        delivered_at: now,
        payment_status: order.payment_method === 'cash' ? 'paid' : order.payment_status,
      }, { count: 'exact' })
      .eq('id', orderId)
      .eq('status', 'on_the_way'),
  log);

  if (updateOrderError) {
    log.error('Order status update error', { orderId, error: updateOrderError.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  if (count === 0) {
    log.warn('Order status update skipped, likely already cancelled', { orderId });
    return corsResponse(errorResponse('ORDER_INVALID_STATUS', {
      message_en: 'Order status has changed, cannot complete delivery.',
      message_ar: 'تغيرت حالة الطلب، لا يمكن إكمال التوصيل.',
    }), 400, undefined, req);
  }

  // A4-G5: Explicit order_status_history insert with actor.
  // The trigger now skips transitions TO 'delivered' (migration 063), so
  // this EF owns the history row. changed_by=driver.id, changed_by_role='driver'.
  await measure('insert-delivered-history', () =>
    supabase
      .from('order_status_history')
      .insert({
        order_id: orderId,
        status: 'delivered',
        changed_by: driverId,
        changed_by_role: 'driver',
        note: 'Delivery completed by driver',
      }),
  log);

  // Insert driver earnings
  await measure('insert-driver-earnings', () =>
    supabase.from('driver_earnings').insert({
      driver_id: driverId,
      order_id: orderId,
      delivery_fee_earned: deliveryFee,
      platform_fee_deducted: platformFeeFromDelivery,
      net_earnings: driverEarnings,
      earnings_pct_used: earningsPct * 100,
    }),
  log);

  // FIX: Atomic increment for driver stats (RED-03)
  // Prefer RPC for true atomic increment; fall back to read-then-write if
  // the RPC doesn't exist yet (requires migration — see file header).
  //
  // ⚠️ RACE CONDITION WARNING (fallback path):
  // The read-then-write pattern is NOT atomic. Concurrent completions could
  // cause lost increments (two requests read the same value, both write +1).
  // Deploy the `increment_driver_stats` RPC (see migration in file header)
  // to eliminate this race condition.
  const { error: rpcError } = await measure('increment-driver-stats', () =>
    supabase.rpc('increment_driver_stats', {
      p_driver_id: driverId,
      p_earnings: driverEarnings,
    }),
  log);

  if (rpcError) {
    // RPC doesn't exist yet — fall back to read-then-write
    log.warn('increment_driver_stats RPC not available, using read-then-write fallback', {
      error: rpcError.message,
      note: 'Deploy the migration in the file header for atomic increments',
    });

    const { data: currentDriver } = await supabase
      .from('drivers')
      .select('total_deliveries, total_earnings')
      .eq('id', driverId)
      .single();

    if (currentDriver) {
      await supabase
        .from('drivers')
        .update({
          total_deliveries: (currentDriver.total_deliveries || 0) + 1,
          total_earnings: (Number(currentDriver.total_earnings) || 0) + driverEarnings,
        })
        .eq('id', driverId);
    }
  }

  // NOTE: Promo usage is incremented atomically by the place_order_with_items
  // RPC (migration 049) at order creation time — that is the authoritative
  // incrementor. Previously this block called increment_promo_usage again on
  // delivery completion, which double-counted every promo order and exhausted
  // promo max_usage at 2× the real rate. Removed per Session A gap A1-G1.

  // Fire-and-forget: send notification to customer
  try {
    const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    fetchWithTimeout(functionUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
      body: JSON.stringify({
        user_id: order.customer_id,
        title_en: 'Order Delivered',
        title_ar: 'تم تسليم الطلب',
        body_en: 'Your order has been delivered. Rate your experience!',
        body_ar: 'تم تسليم طلبك. قيّم تجربتك!',
        type: 'review_request',
        reference_id: orderId,
      }),
    }).catch(() => {});
  } catch { /* silent */ }

  log.info('Delivery completed', {
    orderId,
    driverId,
    driverEarnings,
    platformFee: platformFeeFromDelivery,
  });

  return corsResponse(successResponse({
    order_id: orderId,
    status: 'delivered',
    delivered_at: now,
    driver_earning: {
      amount: driverEarnings,
      platform_fee: platformFeeFromDelivery,
      net_amount: driverEarnings,
    },
  }));
}

// ============================================================
// MARK PICKED UP (A3-G1)
// Driver confirms they picked up the order from the merchant.
// Transition: ready → picked_up
// ============================================================
async function handleMarkPickedUp(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  const authResult = await requireVerifiedDriver(req.headers.get('Authorization'));
  if (authResult.error) {
    return corsResponse(authResult.error, authResult.status || 403, undefined, req);
  }

  const driverId = authResult.data!.driverId;

  const rl = checkRateLimit(`respond:${driverId}`, RATE_LIMITS.DRIVER_RESPOND);
  if (!rl.allowed) {
    log.warn('Rate limited', { key: `respond:${driverId}` });
    return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
  }

  const orderId = body.order_id as string;
  const supabase = getSupabaseAdmin();

  const { data: order, error: orderError } = await measure('get-order', () =>
    supabase
      .from('orders')
      .select('id, status, driver_id, customer_id, order_number')
      .eq('id', orderId)
      .single(),
  log);

  if (orderError || !order) {
    log.warn('Order not found', { orderId });
    return corsResponse(errorResponse('ORDER_NOT_FOUND'), 404, undefined, req);
  }

  if (order.driver_id !== driverId) {
    log.warn('Order not assigned to this driver', { orderId, driverId, assignedTo: order.driver_id });
    return corsResponse(errorResponse('ORDER_NOT_ASSIGNED_TO_YOU'), 400, undefined, req);
  }

  if (order.status !== 'ready') {
    log.warn('Order in invalid status for mark_picked_up', { orderId, status: order.status });
    return corsResponse(errorResponse('ORDER_INVALID_STATUS', {
      message_en: `Order status is '${order.status}', expected 'ready'`,
      message_ar: `حالة الطلب '${order.status}'، المتوقعة 'جاهز'`,
    }), 400, undefined, req);
  }

  const { count, error: updateError } = await measure('mark-picked-up', () =>
    supabase
      .from('orders')
      .update({ status: 'picked_up' }, { count: 'exact' })
      .eq('id', orderId)
      .eq('status', 'ready'),
  log);

  if (updateError) {
    log.error('Mark picked_up update error', { orderId, error: updateError.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  if (count === 0) {
    log.warn('Mark picked_up skipped, status changed concurrently', { orderId });
    return corsResponse(errorResponse('ORDER_INVALID_STATUS', {
      message_en: 'Order status has changed, cannot mark as picked up.',
      message_ar: 'تغيرت حالة الطلب، لا يمكن تأكيد الاستلام.',
    }), 409, undefined, req);
  }

  log.info('Order marked as picked_up', { orderId, driverId });

  // Fire-and-forget: send notification to customer
  try {
    const functionUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/send-notification`;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    fetchWithTimeout(functionUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${serviceKey}` },
      body: JSON.stringify({
        user_id: order.customer_id,
        title_en: 'Order Picked Up',
        title_ar: 'تم استلام الطلب',
        body_en: `Your order #${order.order_number} has been picked up by the driver and is on the way.`,
        body_ar: `تم استلام طلبك #${order.order_number} من قبل السائق وهو في الطريق إليك.`,
        type: 'order_status',
        reference_id: orderId,
      }),
    }).catch(() => {});
  } catch { /* silent */ }

  return corsResponse(successResponse({
    order_id: orderId,
    status: 'picked_up',
  }));
}

// ============================================================
// MARK ON THE WAY (A3-G1)
// Driver confirms they are en route to the customer.
// Transition: picked_up → on_the_way
// ============================================================
async function handleMarkOnTheWay(
  body: Record<string, unknown>,
  req: Request,
  log: ReturnType<typeof createLogger>,
) {
  const authResult = await requireVerifiedDriver(req.headers.get('Authorization'));
  if (authResult.error) {
    return corsResponse(authResult.error, authResult.status || 403, undefined, req);
  }

  const driverId = authResult.data!.driverId;

  const rl = checkRateLimit(`respond:${driverId}`, RATE_LIMITS.DRIVER_RESPOND);
  if (!rl.allowed) {
    log.warn('Rate limited', { key: `respond:${driverId}` });
    return corsResponse(errorResponse('RATE_LIMITED'), 429, undefined, req);
  }

  const orderId = body.order_id as string;
  const supabase = getSupabaseAdmin();

  const { data: order, error: orderError } = await measure('get-order', () =>
    supabase
      .from('orders')
      .select('id, status, driver_id')
      .eq('id', orderId)
      .single(),
  log);

  if (orderError || !order) {
    log.warn('Order not found', { orderId });
    return corsResponse(errorResponse('ORDER_NOT_FOUND'), 404, undefined, req);
  }

  if (order.driver_id !== driverId) {
    log.warn('Order not assigned to this driver', { orderId, driverId, assignedTo: order.driver_id });
    return corsResponse(errorResponse('ORDER_NOT_ASSIGNED_TO_YOU'), 400, undefined, req);
  }

  if (order.status !== 'picked_up') {
    log.warn('Order in invalid status for mark_on_the_way', { orderId, status: order.status });
    return corsResponse(errorResponse('ORDER_INVALID_STATUS', {
      message_en: `Order status is '${order.status}', expected 'picked_up'`,
      message_ar: `حالة الطلب '${order.status}'، المتوقعة 'تم الاستلام'`,
    }), 400, undefined, req);
  }

  const { count, error: updateError } = await measure('mark-on-the-way', () =>
    supabase
      .from('orders')
      .update({ status: 'on_the_way' }, { count: 'exact' })
      .eq('id', orderId)
      .eq('status', 'picked_up'),
  log);

  if (updateError) {
    log.error('Mark on_the_way update error', { orderId, error: updateError.message });
    return corsResponse(errorResponse('INTERNAL_ERROR'), 500, undefined, req);
  }

  if (count === 0) {
    log.warn('Mark on_the_way skipped, status changed concurrently', { orderId });
    return corsResponse(errorResponse('ORDER_INVALID_STATUS', {
      message_en: 'Order status has changed, cannot mark as on the way.',
      message_ar: 'تغيرت حالة الطلب، لا يمكن تأكيد الانطلاق.',
    }), 409, undefined, req);
  }

  log.info('Order marked as on_the_way', { orderId, driverId });

  return corsResponse(successResponse({
    order_id: orderId,
    status: 'on_the_way',
  }));
}

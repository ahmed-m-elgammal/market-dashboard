// CORS headers for Edge Functions
// Origin is configurable via ALLOWED_ORIGINS env var (comma-separated).
// Defaults to '*' for mobile app compatibility.
// For web admin panel, set ALLOWED_ORIGINS=https://admin.example.com
//
// B1-G3: In production, if ALLOWED_ORIGINS is not set, a one-time warning is
// logged to stderr so the misconfiguration is visible. The wildcard is still
// returned (mobile apps don't enforce CORS), but the warning surfaces the
// risk for web clients that share the same Edge Functions.

let _corsWarningLogged = false;

function getAllowedOrigin(req: Request): string {
  const allowedOrigins = Deno.env.get('ALLOWED_ORIGINS');
  if (!allowedOrigins || allowedOrigins === '*') {
    // B1-G3: log a one-time warning in production when using wildcard CORS.
    if (!_corsWarningLogged) {
      _corsWarningLogged = true;
      console.warn(
        '[cors] ALLOWED_ORIGINS is not set — using wildcard "*". ' +
          'This allows ANY website to make cross-origin requests to Edge Functions. ' +
          'Set ALLOWED_ORIGINS=https://your-admin-domain.com in production.'
      );
    }
    return '*';
  }

  const origin = req.headers.get('Origin') || '';
  const origins = allowedOrigins.split(',').map((o) => o.trim());

  if (origin && origins.includes(origin)) {
    return origin;
  }

  // Return first origin as fallback if no match
  return origins[0] || '*';
}

export function getCorsHeaders(req: Request): Record<string, string> {
  const origin = getAllowedOrigin(req);
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type, x-app-version, idempotency-key',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    // Reflect the origin back for credentialed requests
    ...(origin !== '*' ? { 'Vary': 'Origin' } : {}),
  };
}

// Legacy export for backwards compatibility (uses request-agnostic wildcard)
// Prefer corsResponseWithReq() or getCorsHeaders(req) for origin-aware CORS
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-app-version, idempotency-key',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export { CORS_HEADERS };

export function corsResponse(body: unknown, status = 200, extraHeaders?: Record<string, string>, req?: Request) {
  const corsHeaders = req ? getCorsHeaders(req) : CORS_HEADERS;
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders,
      ...extraHeaders,
    },
  });
}

export function handleOptions(req?: Request) {
  const corsHeaders = req ? getCorsHeaders(req) : CORS_HEADERS;
  return new Response('ok', { headers: corsHeaders });
}

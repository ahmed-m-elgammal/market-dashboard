// Supabase client creation for Edge Functions
// Creates admin client with service role key for internal operations

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

let _adminClient: SupabaseClient | null = null;

export function getSupabaseAdmin(): SupabaseClient {
  if (_adminClient) return _adminClient;
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  _adminClient = createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  return _adminClient;
}

export function getSupabaseClient(authHeader?: string): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_ANON_KEY')!;
  const options: Record<string, unknown> = {
    auth: { autoRefreshToken: false, persistSession: false },
  };
  if (authHeader) {
    options.global = { headers: { Authorization: authHeader } };
  }
  return createClient(url, key, options);
}

export async function fetchWithTimeout(
  url: string,
  options: RequestInit = {},
  timeoutMs = 30000
): Promise<Response> {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      ...options,
      signal: controller.signal,
    });
    return response;
  } finally {
    clearTimeout(id);
  }
}

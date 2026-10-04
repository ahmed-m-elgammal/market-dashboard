/**
 * Supabase client for the BROWSER.
 *
 * Deliberately the anon key only. The service_role key bypasses RLS entirely,
 * so anything shipped to a browser holding it is a full database compromise.
 * Every privileged read goes through the admin-api Edge Function instead.
 *
 * WHY THE CLIENT IS LAZY
 *   `providers.ts` statically imports the live authProvider in order to offer
 *   either it or the demo one. That import graph reaches this module even in
 *   demo mode, where Supabase is never contacted. Constructing the client — and
 *   throwing on missing env — at module load therefore broke the demo app for
 *   anyone who had not configured Supabase yet, which is exactly the person the
 *   demo exists to serve.
 *
 *   So the client is built on first use and the missing-env error surfaces then,
 *   at the one place that actually needs the network. A demo-mode session never
 *   triggers it; a live-mode session always does.
 */
import { createClient } from '@supabase/supabase-js';
import type { SupabaseClient } from '@supabase/supabase-js';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from '../constants';

let client: SupabaseClient | null = null;

/**
 * The shared client, built on first call.
 *
 * Cached because createClient sets up its own auth listeners and storage
 * handling — building a second one would mean two clients fighting over the
 * same persisted session.
 */
export function getSupabase(): SupabaseClient {
  if (client) return client;

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    throw new Error(
      'VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY are not set. ' +
        'Copy .env.example to .env and fill them in, or run in demo mode ' +
        '(VITE_DATA_MODE=demo, the default) which needs neither.',
    );
  }

  client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      // Refine routes on auth state, so the session must survive a reload.
      detectSessionInUrl: false,
    },
  });

  return client;
}

/**
 * Named `supabase` so call sites read as before. A Proxy rather than a plain
 * function call at every site, because authProvider.ts and dataProvider.ts both
 * use it several times and rewriting them all to getSupabase() would be churn
 * with no benefit.
 *
 * The trap forwards property access to the real client, so `supabase.auth`,
 * `supabase.from` and `.rpc` all behave identically — the only difference is
 * that nothing is constructed until something is actually read.
 */
export const supabase: SupabaseClient = new Proxy({} as SupabaseClient, {
  get(_target, property: string | symbol) {
    // Indexed through a widened view because a symbol key (a Symbol.iterator, a
    // well-known symbol used by a spread or a promise check) has no meaning on a
    // SupabaseClient and TypeScript will not allow the lookup.
    const source = getSupabase() as unknown as Record<string | symbol, unknown>;
    const value = source[property];
    return typeof value === 'function'
      ? (value as (...args: unknown[]) => unknown).bind(getSupabase())
      : value;
  },
});
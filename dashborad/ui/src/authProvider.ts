/**
 * Refine authProvider backed by Supabase Auth.
 *
 * Login is email + password, then a ROLE CHECK: the signed-in user must have
 * profiles.role = 'admin'. Signing in successfully is not enough — without this
 * any customer could sign in and land on a dashboard that renders, then fail
 * every privileged call.
 *
 * The role is read with the ANON client on purpose. profiles has RLS enabled
 * (migration 019), so anon can read its own row and nobody else's — which is
 * exactly the check we want, and it means no service_role key is involved.
 */
import type { AuthProvider } from '@refinedev/core';
import { supabase } from './lib/supabase';

export interface AdminIdentity {
  id: string;
  email: string;
  fullName: string | null;
  role: string;
}

/**
 * auth.users is not readable with the anon key (only service_role can select
 * from it), so the email comes from the JWT-backed session rather than the
 * profiles row. Pass it in; callers that already hold the session have it.
 */
async function fetchIdentity(userId: string, email: string): Promise<AdminIdentity | null> {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, full_name, role')
    .eq('id', userId)
    .maybeSingle();

  if (error) throw new AuthError(error.message, 'UNKNOWN');
  if (!data) return null;

  return {
    id: data.id,
    email,
    fullName: data.full_name,
    role: data.role,
  };
}

/** Thrown for failures the login form should render inline. */
export class AuthError extends Error {
  constructor(
    message: string,
    readonly code: 'INVALID_CREDENTIALS' | 'NOT_ADMIN' | 'UNKNOWN',
  ) {
    super(message);
    this.name = 'AuthError';
  }
}

export const authProvider: AuthProvider = {
  async login({ email, username, password }) {
    const address = username ?? email;
    if (!address) {
      throw new AuthError('Email is required', 'INVALID_CREDENTIALS');
    }

    const { data, error } = await supabase.auth.signInWithPassword({
      email: address,
      password: password ?? '',
    });

    if (error || !data.user) {
      // Deliberately vague: distinguishing "no such user" from "wrong password"
      // tells an attacker which emails exist.
      throw new AuthError('Incorrect email or password', 'INVALID_CREDENTIALS');
    }

    const identity = await fetchIdentity(data.user.id, data.user.email ?? '');
    if (!identity) {
      await supabase.auth.signOut();
      throw new AuthError('No profile for this account', 'NOT_ADMIN');
    }
    if (identity.role !== 'admin') {
      // Sign out immediately: the session is valid but the account has no
      // business here, and leaving it open would keep a live JWT in storage.
      await supabase.auth.signOut();
      throw new AuthError('This account is not an admin', 'NOT_ADMIN');
    }

    return {
      success: true,
      redirectTo: '/',
    };
  },

  async logout() {
    await supabase.auth.signOut();
    return { success: true, redirectTo: '/login' };
  },

  async check() {
    const { data } = await supabase.auth.getSession();
    if (!data.session) {
      return { authenticated: false, redirectTo: '/login' };
    }
    // Re-verify the role on every route entry, not just login: a demoted admin
    // must lose access on their next navigation, not keep it until re-login.
    const identity = await fetchIdentity(
      data.session.user.id,
      data.session.user.email ?? '',
    );
    if (!identity || identity.role !== 'admin') {
      await supabase.auth.signOut();
      return { authenticated: false, redirectTo: '/login' };
    }
    return { authenticated: true };
  },

  async onError(error) {
    // 401 from admin-api means the JWT expired or was revoked mid-session.
    if (error?.status === 401 || error?.status === 403) {
      await supabase.auth.signOut();
      return { redirectTo: '/login' };
    }
    return {};
  },

  async getPermissions() {
    // Refine calls this from useCan. The database is the real gate — this only
    // keeps the UI from rendering controls that would 403.
    return ['admin'];
  },

  async getIdentity() {
    const { data } = await supabase.auth.getSession();
    if (!data.session) return null;
    return fetchIdentity(data.session.user.id, data.session.user.email ?? '');
  },
};
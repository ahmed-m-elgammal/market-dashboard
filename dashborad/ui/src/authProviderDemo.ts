/**
 * Refine authProvider for demo mode.
 *
 * WHY THIS EXISTS
 *   "Demo mode makes no network request" is only true if sign-in does not hit
 *   Supabase either. Supabase Auth is a network call, so a real provider would
 *   leave the dashboard unable to open with the network off — which is the
 *   situation the demo exists to support.
 *
 * WHAT IS *NOT* STUBBED
 *   The role gate. A real sign-in succeeds for ANY valid account, so the only
 *   thing separating a customer from the dashboard is the profiles.role check in
 *   authProvider.ts. Mocking that away would mean the demo never exercises the
 *   check, and the check is the security boundary. So the demo enforces it too,
 *   against a fixed allowlist: an email that is not a demo admin is rejected
 *   with the same NOT_ADMIN error the live provider raises.
 *
 *   In other words the demo is a DIFFERENT ANSWER to "is this an admin?", not a
 *   different QUESTION. Nothing here weakens the live path, and nothing here
 *   should ever be used to authenticate a real request.
 *
 * WHAT IS STUBBED
 *   Credential verification. Any password is accepted for a listed email. There
 *   is no password to check offline, and pretending otherwise would mean
 *   inventing a credential store, which is worse than saying plainly that demo
 *   mode has no passwords.
 */
import type { AuthProvider } from '@refinedev/core';
import type { AdminIdentity } from './authProvider';
import { AuthError } from './authProvider';

const SESSION_KEY = 'marketak-admin-demo-session';

/**
 * Demo admins.
 *
 * Overridable with VITE_DEMO_ADMINS (comma-separated) so several people can
 * sign in as different operators without a code change.
 */
const DEFAULT_ADMINS = ['admin@marketak.test'];

function demoAdmins(): string[] {
  const configured = import.meta.env.VITE_DEMO_ADMINS as string | undefined;
  const list = (configured ?? '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  return list.length > 0 ? list : DEFAULT_ADMINS;
}

/** The address shown on the login screen as the demo hint. */
export function demoAdminHint(): string {
  return demoAdmins()[0];
}

function readSession(): string | null {
  if (typeof window === 'undefined') return null;
  return window.localStorage.getItem(SESSION_KEY);
}

export const demoAuthProvider: AuthProvider = {
  async login({ email, username, password }) {
    const address = (username ?? email ?? '').trim();

    if (!address) {
      throw new AuthError('Email is required', 'INVALID_CREDENTIALS');
    }
    // Checked so the form's own required/validation rules are mirrored here and
    // an empty submit fails with a message rather than an allowlist miss.
    if (!password) {
      throw new AuthError('Password is required', 'INVALID_CREDENTIALS');
    }

    const admins = demoAdmins();
    if (!admins.includes(address.toLowerCase())) {
      // Same error the live provider raises for a signed-in non-admin, so the
      // login screen renders it through the identical path.
      throw new AuthError('This account is not an admin', 'NOT_ADMIN');
    }

    window.localStorage.setItem(SESSION_KEY, address.toLowerCase());
    return { success: true, redirectTo: '/' };
  },

  async logout() {
    window.localStorage.removeItem(SESSION_KEY);
    return { success: true, redirectTo: '/login' };
  },

  async check() {
    const email = readSession();
    if (!email || !demoAdmins().includes(email)) {
      return { authenticated: false, redirectTo: '/login' };
    }
    return { authenticated: true };
  },

  async onError(error) {
    if (error?.status === 401 || error?.status === 403) {
      window.localStorage.removeItem(SESSION_KEY);
      return { redirectTo: '/login' };
    }
    return {};
  },

  async getPermissions() {
    return ['admin'];
  },

  async getIdentity(): Promise<AdminIdentity | null> {
    const email = readSession();
    if (!email) return null;
    return {
      id: 'demo-admin',
      email,
      fullName: 'Demo Operator',
      // The role is a constant here because reaching this function already
      // required passing the allowlist above. Stated rather than implied.
      role: 'admin',
    };
  },
};
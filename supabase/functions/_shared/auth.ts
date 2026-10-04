// Authentication helpers for Edge Functions
// Validates JWT and extracts user info + role

import { getSupabaseAdmin } from './supabase.ts';
import { errorResponse, errorStatus } from './errors.ts';

interface AuthResult {
  userId: string;
  email: string;
  role: string;
  profile: {
    full_name: string | null;
    phone: string | null;
    preferred_language: string;
  };
}

/**
 * Validate JWT from Authorization header and return user info + role.
 * Returns { data: AuthResult } on success or { error: ErrorResponse } on failure.
 */
export async function authenticate(authHeader: string | null): Promise<{
  data: AuthResult | null;
  error: ReturnType<typeof errorResponse> | null;
}> {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return { data: null, error: errorResponse('UNAUTHORIZED') };
  }

  const token = authHeader.replace('Bearer ', '');
  const supabase = getSupabaseAdmin();

  // Verify JWT and get user
  const { data: { user }, error: authError } = await supabase.auth.getUser(token);
  if (authError || !user) {
    return { data: null, error: errorResponse('INVALID_TOKEN') };
  }

  // Get profile with role
  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('id, full_name, phone, preferred_language, role')
    .eq('id', user.id)
    .single();

  if (profileError || !profile) {
    return { data: null, error: errorResponse('UNAUTHORIZED') };
  }

  return {
    data: {
      userId: user.id,
      email: user.email ?? '',
      role: profile.role,
      profile: {
        full_name: profile.full_name,
        phone: profile.phone,
        preferred_language: profile.preferred_language,
      },
    },
    error: null,
  };
}

/**
 * Require a specific role. Returns auth result if role matches, error otherwise.
 */
export async function requireRole(
  authHeader: string | null,
  role: string,
): Promise<{
  data: AuthResult | null;
  error: ReturnType<typeof errorResponse> | null;
  status?: number;
}> {
  const result = await authenticate(authHeader);
  if (result.error) return result;

  if (result.data!.role !== role) {
    if (role === 'admin') return { data: null, error: errorResponse('NOT_ADMIN'), status: 403 };
    if (role === 'customer') return { data: null, error: errorResponse('NOT_CUSTOMER'), status: 403 };
    if (role === 'driver') return { data: null, error: errorResponse('NOT_DRIVER'), status: 403 };
    return { data: null, error: errorResponse('FORBIDDEN'), status: 403 };
  }

  return result;
}

/**
 * Require driver role + verified + active.
 */
export async function requireVerifiedDriver(authHeader: string | null): Promise<{
  data: (AuthResult & { driverId: string; isVerified: boolean; isActive: boolean }) | null;
  error: ReturnType<typeof errorResponse> | null;
  status?: number;
}> {
  const result = await requireRole(authHeader, 'driver');
  if (result.error) return result;

  const supabase = getSupabaseAdmin();
  const { data: driver, error: driverError } = await supabase
    .from('drivers')
    .select('id, is_verified, is_active')
    .eq('id', result.data!.userId)
    .single();

  if (driverError || !driver) {
    return { data: null, error: errorResponse('DRIVER_NOT_FOUND'), status: 404 };
  }

  if (!driver.is_verified) {
    return { data: null, error: errorResponse('DRIVER_NOT_VERIFIED'), status: 403 };
  }

  if (!driver.is_active) {
    return { data: null, error: errorResponse('DRIVER_NOT_ACTIVE'), status: 403 };
  }

  return {
    data: {
      ...result.data!,
      driverId: driver.id,
      isVerified: driver.is_verified,
      isActive: driver.is_active,
    },
    error: null,
  };
}

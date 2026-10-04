/**
 * Chooses which auth and data provider the app mounts.
 *
 * Import these from here rather than reaching for the individual modules
 * directly, so there is exactly one place that knows which backend is live.
 * Every screen imports from this module and does not know or care which it got.
 *
 * See DATA_MODE in constants.ts for what each mode means.
 */
import type { AuthProvider, DataProvider } from '@refinedev/core';
import { DATA_MODE } from './constants';
import { authProvider as supabaseAuthProvider } from './authProvider';
import { demoAuthProvider } from './authProviderDemo';
import { dataProvider as restDataProvider } from './dataProvider';
import { demoDataProvider } from './dataProviderDemo';

const isDemo = DATA_MODE === 'demo';

export const authProvider: AuthProvider = isDemo ? demoAuthProvider : supabaseAuthProvider;
export const dataProvider: DataProvider = isDemo ? demoDataProvider : restDataProvider;

export { DATA_MODE };
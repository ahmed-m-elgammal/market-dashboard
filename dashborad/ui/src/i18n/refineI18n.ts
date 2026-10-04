/**
 * Refine i18nProvider, wired to the app's own language state.
 *
 * WHY THIS IS NEEDED
 *   Every string this app renders goes through i18n/strings.ts — except the
 *   chrome that @refinedev/antd draws itself. ThemedLayoutV2 renders its Logout
 *   item from Refine's translation resources, so with no provider it stayed
 *   "Logout" in an otherwise fully Arabic UI. A bilingual app with one English
 *   label in the sidebar reads as broken, and it is the label an operator uses
 *   most.
 *
 * WHY IT DELEGATES RATHER THAN REPLACES
 *   Refine asks for dozens of keys — notifications, pagination, error pages,
 *   button labels — and a provider that answered all of them would be a second,
 *   competing translation file that could drift from strings.ts. So this one
 *   answers ONLY the keys the layout chrome actually shows and returns Refine's
 *   own `defaultMessage` for everything else.
 *
 *   Refine passes that defaultMessage as the third argument precisely so a
 *   provider can be partial. Returning it untouched means an untranslated key
 *   degrades to Refine's English rather than to a blank string.
 *
 * changeLocale / getLocale are delegated to LangProvider so Refine's internal
 * locale state cannot disagree with the document direction: two sources of truth
 * for "what language is this" is how a half-translated UI happens.
 */
import type { I18nProvider } from '@refinedev/core';
import type { Lang } from './strings';
import { t, type StringKey } from './strings';

/**
 * Refine's own keys -> our strings.
 *
 * These key names were read out of @refinedev/antd's own build rather than
 * guessed: the sidebar renders `buttons.logout`, and an earlier attempt at
 * `menu.logout` silently rendered the literal key in the UI — which is the
 * failure mode this mapping is most exposed to. Anything absent here falls back
 * to Refine's English, so a wrong key is visible but not fatal.
 *
 * Only keys something in THIS app actually renders are listed. The login,
 * register and password pages are not used (LoginPage is our own), so their keys
 * are deliberately absent rather than half-translated.
 */
const REFINE_KEYS: Record<string, StringKey> = {
  'buttons.logout': 'signOut',
  'buttons.save': 'save',
  'buttons.cancel': 'cancel',
  'buttons.clear': 'clear',
  'buttons.filter': 'filter',
  'dashboard.title': 'navDashboard',
  'pages.error.404': 'errorNotFoundBody',
  'pages.error.backHome': 'backToDashboard',
};

export function buildI18nProvider(
  lang: Lang,
  setLang: (lang: Lang) => void,
): I18nProvider {
  return {
    translate(key: string, _options?: unknown, defaultMessage?: string): string {
      const mapped = REFINE_KEYS[key];
      if (mapped) return t(mapped, lang);
      // Unknown key: Refine's own English, or the key itself if there is no
      // default. Never an empty string — a blank label is undebuggable.
      return defaultMessage ?? key;
    },

    // Synchronous: LangProvider persists to localStorage itself and flips
    // <html lang>/<html dir>, and every consumer already re-renders off that.
    // Awaiting a promise here would leave Refine one render behind the document.
    changeLocale(next: string) {
      setLang(next === 'ar' ? 'ar' : 'en');
    },

    getLocale() {
      return lang;
    },
  };
}
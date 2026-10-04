/**
 * Language context.
 *
 * Persisted to localStorage so a reload keeps the operator's choice, and applied
 * to <html lang> and <html dir> because Ant Design's RTL behaviour is driven by
 * the document direction, not by a prop.
 */
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import arEG from 'antd/locale/ar_EG';
import enUS from 'antd/locale/en_US';
import { DIRECTION, LOCALE, type Lang } from './strings';

const STORAGE_KEY = 'marketak-admin-lang';

interface LangContextValue {
  lang: Lang;
  setLang: (lang: Lang) => void;
  toggle: () => void;
  antdLocale: typeof enUS;
  direction: 'ltr' | 'rtl';
}

const LangContext = createContext<LangContextValue | null>(null);

function initialLang(): Lang {
  if (typeof window === 'undefined') return 'en';
  const stored = window.localStorage.getItem(STORAGE_KEY);
  if (stored === 'en' || stored === 'ar') return stored;
  return navigator.language?.startsWith('ar') ? 'ar' : 'en';
}

export function LangProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>(initialLang);

  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = DIRECTION[lang];
  }, [lang]);

  const setLang = useCallback((next: Lang) => {
    window.localStorage.setItem(STORAGE_KEY, next);
    setLangState(next);
  }, []);

  const value = useMemo<LangContextValue>(
    () => ({
      lang,
      setLang,
      toggle: () => setLang(lang === 'en' ? 'ar' : 'en'),
      antdLocale: lang === 'ar' ? arEG : enUS,
      direction: DIRECTION[lang],
    }),
    [lang, setLang],
  );

  return <LangContext.Provider value={value}>{children}</LangContext.Provider>;
}

export function useLang(): LangContextValue {
  const ctx = useContext(LangContext);
  if (!ctx) throw new Error('useLang must be used inside <LangProvider>');
  return ctx;
}

/** Convenience: the active locale string for Intl.NumberFormat / Date. */
export function useNumberLocale(): string {
  const { lang } = useLang();
  return LOCALE[lang];
}
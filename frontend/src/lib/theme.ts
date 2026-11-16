export type ThemePreference = 'system' | 'light' | 'dark';
export type ResolvedTheme = 'light' | 'dark';

const STORAGE_THEME_KEY = 'pve_panel_theme';

export function getThemePreference(): ThemePreference {
  if (typeof window === 'undefined') return 'system';
  const raw = window.localStorage.getItem(STORAGE_THEME_KEY);
  if (raw === 'light' || raw === 'dark' || raw === 'system') return raw;
  return 'system';
}

export function resolveTheme(pref: ThemePreference): ResolvedTheme {
  if (pref === 'light' || pref === 'dark') return pref;
  if (typeof window !== 'undefined' && window.matchMedia) {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  return 'dark';
}

export function applyThemePreference(pref: ThemePreference): ResolvedTheme {
  const resolved = resolveTheme(pref);
  if (typeof window !== 'undefined') {
    window.localStorage.setItem(STORAGE_THEME_KEY, pref);
  }
  if (typeof document !== 'undefined') {
    const root = document.documentElement;
    root.classList.remove('light', 'dark');
    root.classList.add(resolved);
    root.style.colorScheme = resolved;
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) {
      meta.setAttribute('content', resolved === 'dark' ? '#030712' : '#eef2f7');
    }
  }
  return resolved;
}

export function subscribeSystemTheme(callback: (resolved: ResolvedTheme) => void): () => void {
  if (typeof window === 'undefined' || !window.matchMedia) return () => {};
  const media = window.matchMedia('(prefers-color-scheme: dark)');
  const onChange = () => {
    const pref = getThemePreference();
    if (pref === 'system') {
      callback(applyThemePreference('system'));
    }
  };
  media.addEventListener('change', onChange);
  return () => media.removeEventListener('change', onChange);
}

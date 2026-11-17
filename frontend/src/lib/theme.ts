export type ThemePreference = 'system' | 'light' | 'dark';
export type ResolvedTheme = 'light' | 'dark';
export type AccentPreset = 'cyan' | 'cider' | 'indigo' | 'emerald' | 'amber' | 'purple';
export type GlassIntensity = 'balanced' | 'cider' | 'subtle';
export type DensityMode = 'comfortable' | 'compact';

const STORAGE_THEME_KEY = 'pve_panel_theme';
const STORAGE_ACCENT_KEY = 'pve_panel_accent';
const STORAGE_GLASS_KEY = 'pve_panel_glass';
const STORAGE_DENSITY_KEY = 'pve_panel_density';

export interface AccentPresetMeta {
  id: AccentPreset;
  label: string;
  swatchHex: string;
  secondaryHex: string;
  rgb: string;
  secondaryRgb: string;
}

export const ACCENT_PRESETS: AccentPresetMeta[] = [
  {
    id: 'cyan',
    label: 'Cyan PVE',
    swatchHex: '#06b6d4',
    secondaryHex: '#6366f1',
    rgb: '6 182 212',
    secondaryRgb: '99 102 241',
  },
  {
    id: 'cider',
    label: 'Cider Ruby',
    swatchHex: '#fa233b',
    secondaryHex: '#ec4899',
    rgb: '250 35 59',
    secondaryRgb: '236 72 153',
  },
  {
    id: 'indigo',
    label: 'Indigo Studio',
    swatchHex: '#6366f1',
    secondaryHex: '#38bdf8',
    rgb: '99 102 241',
    secondaryRgb: '56 189 248',
  },
  {
    id: 'emerald',
    label: 'Émeraude',
    swatchHex: '#10b981',
    secondaryHex: '#06b6d4',
    rgb: '16 185 129',
    secondaryRgb: '6 182 212',
  },
  {
    id: 'amber',
    label: 'Ambre Proxmox',
    swatchHex: '#f59e0b',
    secondaryHex: '#ef4444',
    rgb: '245 158 11',
    secondaryRgb: '239 68 68',
  },
  {
    id: 'purple',
    label: 'Améthyste',
    swatchHex: '#a855f7',
    secondaryHex: '#ec4899',
    rgb: '168 85 247',
    secondaryRgb: '236 72 153',
  },
];

export function getThemePreference(): ThemePreference {
  if (typeof window === 'undefined') return 'system';
  const raw = window.localStorage.getItem(STORAGE_THEME_KEY);
  if (raw === 'light' || raw === 'dark' || raw === 'system') return raw;
  return 'system';
}

export function getAccentPreset(): AccentPreset {
  if (typeof window === 'undefined') return 'cyan';
  const raw = window.localStorage.getItem(STORAGE_ACCENT_KEY) as AccentPreset | null;
  return ACCENT_PRESETS.some((p) => p.id === raw) ? raw! : 'cyan';
}

export function getGlassIntensity(): GlassIntensity {
  if (typeof window === 'undefined') return 'balanced';
  const raw = window.localStorage.getItem(STORAGE_GLASS_KEY);
  if (raw === 'balanced' || raw === 'cider' || raw === 'subtle') return raw;
  return 'balanced';
}

export function getDensityMode(): DensityMode {
  if (typeof window === 'undefined') return 'comfortable';
  const raw = window.localStorage.getItem(STORAGE_DENSITY_KEY);
  if (raw === 'comfortable' || raw === 'compact') return raw;
  return 'comfortable';
}

export function resolveTheme(pref: ThemePreference): ResolvedTheme {
  if (pref === 'light' || pref === 'dark') return pref;
  if (typeof window !== 'undefined' && window.matchMedia) {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  return 'dark';
}

export function applyAccentPreset(preset: AccentPreset): void {
  const meta = ACCENT_PRESETS.find((p) => p.id === preset) ?? ACCENT_PRESETS[0];
  if (typeof window !== 'undefined') {
    window.localStorage.setItem(STORAGE_ACCENT_KEY, meta.id);
  }
  if (typeof document !== 'undefined') {
    const root = document.documentElement;
    root.dataset.accent = meta.id;
    root.style.setProperty('--accent-rgb', meta.rgb);
    root.style.setProperty('--accent-2-rgb', meta.secondaryRgb);
    root.style.setProperty('--accent-hex', meta.swatchHex);
    root.style.setProperty('--accent-2-hex', meta.secondaryHex);
  }
}

export function applyGlassIntensity(intensity: GlassIntensity): void {
  if (typeof window !== 'undefined') {
    window.localStorage.setItem(STORAGE_GLASS_KEY, intensity);
  }
  if (typeof document !== 'undefined') {
    document.documentElement.dataset.glass = intensity;
  }
}

export function applyDensityMode(density: DensityMode): void {
  if (typeof window !== 'undefined') {
    window.localStorage.setItem(STORAGE_DENSITY_KEY, density);
  }
  if (typeof document !== 'undefined') {
    document.documentElement.dataset.density = density;
  }
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
  applyAccentPreset(getAccentPreset());
  applyGlassIntensity(getGlassIntensity());
  applyDensityMode(getDensityMode());
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

export type ThemePreference = 'system' | 'light' | 'dark';
export type ResolvedTheme = 'light' | 'dark';
export type AccentPreset = 'cyan' | 'cider' | 'indigo' | 'emerald' | 'amber' | 'purple';
export type GlassIntensity = 'balanced' | 'cider' | 'subtle';
export type DensityMode = 'comfortable' | 'compact';

const STORAGE_THEME_KEY = 'pve_panel_theme';
const STORAGE_ACCENT_KEY = 'pve_panel_accent';
const STORAGE_GLASS_KEY = 'pve_panel_glass';
const STORAGE_DENSITY_KEY = 'pve_panel_density';

export type AccentShadeKey =
  | 50
  | 100
  | 200
  | 300
  | 400
  | 500
  | 600
  | 700
  | 800
  | 900
  | 950;

export interface AccentPresetMeta {
  id: AccentPreset;
  label: string;
  swatchHex: string;
  secondaryHex: string;
  rgb: string;
  secondaryRgb: string;
  bgDark: string;
  bgLight: string;
  glassDarkRgb: string;
  sheetDarkRgb: string;
  glassLightRgb: string;
  shades: Record<AccentShadeKey, string>;
}

export const ACCENT_PRESETS: AccentPresetMeta[] = [
  {
    id: 'cyan',
    label: 'Cyan PVE',
    swatchHex: '#06b6d4',
    secondaryHex: '#6366f1',
    rgb: '6 182 212',
    secondaryRgb: '99 102 241',
    bgDark: '#030816',
    bgLight: '#eef4fa',
    glassDarkRgb: '15 23 42',
    sheetDarkRgb: '4 10 24',
    glassLightRgb: '241 247 252',
    shades: {
      50: '236 254 255',
      100: '207 250 254',
      200: '165 243 252',
      300: '103 232 249',
      400: '34 211 238',
      500: '6 182 212',
      600: '8 145 178',
      700: '14 116 144',
      800: '21 94 117',
      900: '22 78 99',
      950: '8 51 68',
    },
  },
  {
    id: 'cider',
    label: 'Cider Ruby',
    swatchHex: '#fa233b',
    secondaryHex: '#ec4899',
    rgb: '250 35 59',
    secondaryRgb: '236 72 153',
    bgDark: '#120409',
    bgLight: '#fdf2f5',
    glassDarkRgb: '40 12 22',
    sheetDarkRgb: '22 6 12',
    glassLightRgb: '253 242 246',
    shades: {
      50: '255 241 243',
      100: '255 228 232',
      200: '254 205 214',
      300: '253 164 180',
      400: '251 113 137',
      500: '250 35 59',
      600: '225 29 72',
      700: '190 18 60',
      800: '159 18 57',
      900: '136 19 55',
      950: '76 5 25',
    },
  },
  {
    id: 'indigo',
    label: 'Indigo Studio',
    swatchHex: '#6366f1',
    secondaryHex: '#38bdf8',
    rgb: '99 102 241',
    secondaryRgb: '56 189 248',
    bgDark: '#06071c',
    bgLight: '#eff0fd',
    glassDarkRgb: '18 20 52',
    sheetDarkRgb: '9 10 30',
    glassLightRgb: '240 242 254',
    shades: {
      50: '238 242 255',
      100: '224 231 255',
      200: '199 210 254',
      300: '165 180 252',
      400: '129 140 248',
      500: '99 102 241',
      600: '79 70 229',
      700: '67 56 202',
      800: '55 48 163',
      900: '49 46 129',
      950: '30 27 75',
    },
  },
  {
    id: 'emerald',
    label: 'Émeraude',
    swatchHex: '#10b981',
    secondaryHex: '#06b6d4',
    rgb: '16 185 129',
    secondaryRgb: '6 182 212',
    bgDark: '#03120c',
    bgLight: '#ecfdf5',
    glassDarkRgb: '10 34 26',
    sheetDarkRgb: '5 20 15',
    glassLightRgb: '236 253 245',
    shades: {
      50: '236 253 245',
      100: '209 250 229',
      200: '167 243 208',
      300: '110 231 183',
      400: '52 211 153',
      500: '16 185 129',
      600: '5 150 105',
      700: '4 120 87',
      800: '6 95 70',
      900: '6 78 59',
      950: '2 44 34',
    },
  },
  {
    id: 'amber',
    label: 'Ambre Proxmox',
    swatchHex: '#f59e0b',
    secondaryHex: '#ef4444',
    rgb: '245 158 11',
    secondaryRgb: '239 68 68',
    bgDark: '#130a03',
    bgLight: '#fff8ec',
    glassDarkRgb: '40 23 10',
    sheetDarkRgb: '22 12 4',
    glassLightRgb: '255 247 237',
    shades: {
      50: '255 251 235',
      100: '254 243 199',
      200: '253 230 138',
      300: '252 211 77',
      400: '251 191 36',
      500: '245 158 11',
      600: '217 119 6',
      700: '180 83 9',
      800: '146 64 14',
      900: '120 53 15',
      950: '69 26 3',
    },
  },
  {
    id: 'purple',
    label: 'Améthyste',
    swatchHex: '#a855f7',
    secondaryHex: '#ec4899',
    rgb: '168 85 247',
    secondaryRgb: '236 72 153',
    bgDark: '#0e041a',
    bgLight: '#f6f0ff',
    glassDarkRgb: '29 13 46',
    sheetDarkRgb: '16 6 28',
    glassLightRgb: '245 240 255',
    shades: {
      50: '250 245 255',
      100: '243 232 255',
      200: '233 213 255',
      300: '216 180 254',
      400: '192 132 252',
      500: '168 85 247',
      600: '147 51 234',
      700: '126 34 206',
      800: '107 33 168',
      900: '88 28 135',
      950: '59 7 100',
    },
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
    root.style.setProperty('--theme-bg-dark', meta.bgDark);
    root.style.setProperty('--theme-bg-light', meta.bgLight);
    root.style.setProperty('--theme-glass-dark-rgb', meta.glassDarkRgb);
    root.style.setProperty('--theme-sheet-dark-rgb', meta.sheetDarkRgb);
    root.style.setProperty('--theme-glass-light-rgb', meta.glassLightRgb);
    for (const [shade, value] of Object.entries(meta.shades)) {
      root.style.setProperty(`--tw-accent-${shade}`, value);
    }
    const metaTag = document.querySelector('meta[name="theme-color"]');
    if (metaTag) {
      const isDark = root.classList.contains('dark');
      metaTag.setAttribute('content', isDark ? meta.bgDark : meta.bgLight);
    }
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

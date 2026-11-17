import { useEffect, useRef, useState } from 'react';
import {
  BellRing,
  ChevronDown,
  FileCode2,
  LogOut,
  Monitor,
  Moon,
  Pause,
  Play,
  QrCode,
  Radio,
  RefreshCw,
  Rocket,
  Search,
  Server,
  ShieldAlert,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  Sun,
  Terminal,
  Wrench,
  X,
} from 'lucide-react';
import type { ThemePreference } from '../lib/theme';
import type { AuthUser, RealtimeTransportMode } from '../types';

interface HeaderProps {
  user: AuthUser | null;
  search: string;
  onSearchChange: (value: string) => void;
  autoRefresh: boolean;
  onToggleAutoRefresh: () => void;
  isRefreshing: boolean;
  onRefreshNow: () => void;
  lastUpdated: Date | null;
  demoActive: boolean;
  needsSetup?: boolean;
  realtimeStatus: RealtimeTransportMode;
  activeIncidentsCount: number;
  theme: ThemePreference;
  onThemeChange: (theme: ThemePreference) => void;
  onOpenIncidents: () => void;
  onOpenNotifications: () => void;
  onOpenYamlEditor: () => void;
  onOpenOnboarding: () => void;
  onOpenServerConfig: () => void;
  onOpenSetupWizard: () => void;
  onSignOut?: () => void;
}

function realtimePillMeta(status: RealtimeTransportMode) {
  if (status === 'ws') {
    return {
      label: 'WS',
      dot: 'bg-emerald-500 animate-pulse',
      cls: 'border-emerald-500/35 bg-emerald-500/15 text-emerald-700 dark:text-emerald-200',
      title: 'WebSocket temps réel connecté',
    };
  }
  if (status === 'sse') {
    return {
      label: 'SSE',
      dot: 'bg-cyan-500 animate-pulse',
      cls: 'border-cyan-500/35 bg-cyan-500/15 text-cyan-700 dark:text-cyan-200',
      title: 'Flux Server-Sent Events connecté (fallback)',
    };
  }
  if (status === 'demo') {
    return {
      label: 'Démo',
      dot: 'bg-indigo-500',
      cls: 'border-indigo-500/35 bg-indigo-500/15 text-indigo-700 dark:text-indigo-200',
      title: 'Mode Démo simulé localement',
    };
  }
  if (status === 'connecting') {
    return {
      label: 'Sync…',
      dot: 'bg-amber-500 animate-pulse',
      cls: 'border-amber-500/35 bg-amber-500/15 text-amber-700 dark:text-amber-200',
      title: 'Connexion au flux temps réel en cours…',
    };
  }
  return {
    label: 'Hors flux',
    dot: 'bg-rose-500',
    cls: 'border-rose-500/35 bg-rose-500/15 text-rose-700 dark:text-rose-200',
    title: 'Flux temps réel déconnecté — repli polling actif',
  };
}

export function Header({
  user,
  search,
  onSearchChange,
  autoRefresh,
  onToggleAutoRefresh,
  isRefreshing,
  onRefreshNow,
  lastUpdated,
  demoActive,
  needsSetup = false,
  realtimeStatus,
  activeIncidentsCount,
  theme,
  onThemeChange,
  onOpenIncidents,
  onOpenNotifications,
  onOpenYamlEditor,
  onOpenOnboarding,
  onOpenServerConfig,
  onOpenSetupWizard,
  onSignOut,
}: HeaderProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const [toolsOpen, setToolsOpen] = useState(false);

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        inputRef.current?.focus();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  useEffect(() => {
    if (!toolsOpen) return;
    const onClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setToolsOpen(false);
      }
    };
    window.addEventListener('mousedown', onClickOutside);
    return () => window.removeEventListener('mousedown', onClickOutside);
  }, [toolsOpen]);

  const initials = (user?.name || user?.login || 'PV')
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() || '')
    .join('');

  const rtMeta = realtimePillMeta(realtimeStatus);
  const cycleTheme = () => {
    const next: Record<ThemePreference, ThemePreference> = {
      system: 'light',
      light: 'dark',
      dark: 'system',
    };
    onThemeChange(next[theme]);
  };

  const ThemeIcon = theme === 'light' ? Sun : theme === 'dark' ? Moon : Monitor;
  const themeLabel =
    theme === 'light' ? 'Clair' : theme === 'dark' ? 'Sombre' : 'Système';

  const canSignOut =
    Boolean(onSignOut) &&
    !demoActive &&
    (user?.auth_mode === 'session' || user?.auth_mode === 'api_token');

  return (
    <header className="liquid-glass-elevated safe-top sticky top-0 z-30 border-x-0 border-t-0">
      <div className="mx-auto flex max-w-7xl flex-col gap-3 px-4 pb-3.5 pt-2 sm:px-6 xl:flex-row xl:items-center xl:justify-between">
        <div className="flex items-center justify-between gap-2.5">
          <div className="flex min-w-0 items-center gap-3">
            <div className="cider-accent-ring flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border text-cyan-600 shadow-lg shadow-cyan-500/15 dark:text-cyan-300">
              <Server className="h-5 w-5" />
            </div>
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-1.5">
                <h1 className="truncate text-base font-semibold tracking-tight text-slate-900 dark:text-white sm:text-lg">
                  PVE Center
                </h1>

                <span
                  className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium ${
                    demoActive || user?.auth_mode === 'demo'
                      ? 'border border-indigo-500/35 bg-indigo-500/15 text-indigo-700 dark:text-indigo-200'
                      : user?.auth_mode === 'dev_bypass'
                        ? 'border border-amber-500/30 bg-amber-500/15 text-amber-700 dark:text-amber-300'
                        : 'border border-emerald-500/30 bg-emerald-500/15 text-emerald-700 dark:text-emerald-200'
                  }`}
                >
                  {demoActive || user?.auth_mode === 'demo' ? (
                    <>
                      <Sparkles className="h-3 w-3" />
                      Démo
                    </>
                  ) : user?.auth_mode === 'dev_bypass' ? (
                    <>
                      <Terminal className="h-3 w-3" />
                      Dev Local
                    </>
                  ) : user?.auth_mode === 'session' || user?.auth_mode === 'api_token' ? (
                    <>
                      <ShieldCheck className="h-3 w-3" />
                      Session LAN
                    </>
                  ) : (
                    <>
                      <ShieldCheck className="h-3 w-3" />
                      Tailscale SSO
                    </>
                  )}
                </span>

                <span
                  title={rtMeta.title}
                  className={`inline-flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-[10px] font-semibold ${rtMeta.cls}`}
                >
                  <span className={`h-1.5 w-1.5 rounded-full ${rtMeta.dot}`} />
                  <Radio className="h-2.5 w-2.5" />
                  <span>{rtMeta.label}</span>
                </span>
              </div>

              <p className="truncate text-xs text-slate-500 dark:text-slate-400">
                Supervision Proxmox VE &amp; Services
                {lastUpdated && (
                  <span className="ml-2 text-slate-400 dark:text-slate-500">
                    • MàJ {lastUpdated.toLocaleTimeString('fr-FR')}
                  </span>
                )}
              </p>
            </div>
          </div>

          {/* Mobile compact controls */}
          <div className="flex items-center gap-1.5 xl:hidden">
            <button
              type="button"
              onClick={cycleTheme}
              className="liquid-pill rounded-full p-2 text-slate-700 dark:text-slate-200"
              title={`Thème : ${themeLabel}`}
              aria-label={`Changer le thème (${themeLabel})`}
            >
              <ThemeIcon className="h-3.5 w-3.5 text-cyan-600 dark:text-cyan-300" />
            </button>
            <button
              type="button"
              onClick={onOpenServerConfig}
              className="liquid-pill inline-flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium text-slate-700 transition hover:text-slate-950 active:scale-95 dark:text-slate-200 dark:hover:text-white"
              title="Configurer le serveur ou activer le Mode Démo"
            >
              <SlidersHorizontal className="h-3.5 w-3.5 text-cyan-600 dark:text-cyan-300" />
              <span className="hidden sm:inline">Serveur</span>
            </button>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <div className="relative flex-1 sm:w-56 sm:flex-none">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
            <input
              ref={inputRef}
              type="text"
              value={search}
              onChange={(e) => onSearchChange(e.target.value)}
              placeholder="Filtrer… (⌘K)"
              className="w-full rounded-full border border-slate-300/80 bg-white/80 py-1.5 pl-9 pr-8 text-sm text-slate-900 placeholder-slate-400 transition focus:border-cyan-500/70 focus:bg-white focus:outline-none focus:ring-2 focus:ring-cyan-500/20 dark:border-white/15 dark:bg-white/[0.06] dark:text-white dark:placeholder-slate-400 dark:focus:border-cyan-400/60 dark:focus:bg-white/[0.1] dark:focus:ring-cyan-400/20"
            />
            {search && (
              <button
                type="button"
                onClick={() => onSearchChange('')}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-700 dark:hover:text-white"
                title="Effacer la recherche"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            )}
          </div>

          {/* Incidents badge */}
          <button
            type="button"
            onClick={onOpenIncidents}
            className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition active:scale-95 ${
              activeIncidentsCount > 0
                ? 'border-rose-500/40 bg-rose-500/15 text-rose-700 hover:bg-rose-500/25 dark:text-rose-200'
                : 'liquid-pill text-slate-700 hover:text-slate-950 dark:text-slate-200 dark:hover:text-white'
            }`}
            title="Voir les incidents et alertes"
          >
            <ShieldAlert
              className={`h-3.5 w-3.5 ${
                activeIncidentsCount > 0
                  ? 'animate-pulse text-rose-500 dark:text-rose-300'
                  : 'text-slate-500 dark:text-slate-400'
              }`}
            />
            <span className="hidden sm:inline">Incidents</span>
            {activeIncidentsCount > 0 && (
              <span className="rounded-full bg-rose-500 px-1.5 py-0.2 text-[10px] font-bold text-white">
                {activeIncidentsCount}
              </span>
            )}
          </button>

          {/* Notifications & QR */}
          <button
            type="button"
            onClick={onOpenNotifications}
            className="liquid-pill inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium text-slate-700 transition hover:text-slate-950 active:scale-95 dark:text-slate-200 dark:hover:text-white"
            title="Notifications, Webhooks & QR App Apple"
          >
            <BellRing className="h-3.5 w-3.5 text-indigo-600 dark:text-indigo-300" />
            <QrCode className="h-3.5 w-3.5 text-cyan-600 dark:text-cyan-300" />
            <span className="hidden md:inline">Alertes &amp; QR</span>
          </button>

          {/* Menu Configuration & Outils */}
          <div className="relative" ref={menuRef}>
            <button
              type="button"
              onClick={() => setToolsOpen((v) => !v)}
              className={`relative inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition active:scale-95 ${
                needsSetup
                  ? 'border-amber-500/45 bg-amber-500/15 text-amber-800 hover:bg-amber-500/25 dark:text-amber-200'
                  : 'liquid-pill text-slate-700 hover:text-slate-950 dark:text-slate-200 dark:hover:text-white'
              }`}
              title="Configuration, Onboarding & Éditeur YAML"
              aria-expanded={toolsOpen}
            >
              <Wrench
                className={`h-3.5 w-3.5 ${
                  needsSetup ? 'text-amber-500 dark:text-amber-300' : 'text-cyan-600 dark:text-cyan-300'
                }`}
              />
              <span>Config</span>
              {needsSetup && (
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-500" />
              )}
              <ChevronDown className="h-3 w-3 opacity-70" />
            </button>

            {toolsOpen && (
              <div className="liquid-glass-elevated absolute right-0 mt-2 w-64 space-y-1 rounded-2xl p-2 shadow-2xl">
                <button
                  type="button"
                  onClick={() => {
                    setToolsOpen(false);
                    onOpenOnboarding();
                  }}
                  className="flex w-full items-center gap-2.5 rounded-xl px-3 py-2 text-left text-xs font-medium text-slate-800 transition hover:bg-cyan-500/10 dark:text-slate-100"
                >
                  <Rocket className="h-4 w-4 text-cyan-500" />
                  <div>
                    <div>Assistant Initial (4 étapes)</div>
                    <div className="text-[10px] text-slate-500 dark:text-slate-400">
                      Onboarding, scan LAN &amp; jeton API
                    </div>
                  </div>
                </button>

                <button
                  type="button"
                  onClick={() => {
                    setToolsOpen(false);
                    onOpenSetupWizard();
                  }}
                  className="flex w-full items-center gap-2.5 rounded-xl px-3 py-2 text-left text-xs font-medium text-slate-800 transition hover:bg-cyan-500/10 dark:text-slate-100"
                >
                  <Wrench className="h-4 w-4 text-indigo-500" />
                  <div>
                    <div>Studio de Configuration</div>
                    <div className="text-[10px] text-slate-500 dark:text-slate-400">
                      Thème Cider, Proxmox, services &amp; icônes
                    </div>
                  </div>
                </button>

                <button
                  type="button"
                  onClick={() => {
                    setToolsOpen(false);
                    onOpenYamlEditor();
                  }}
                  className="flex w-full items-center gap-2.5 rounded-xl px-3 py-2 text-left text-xs font-medium text-slate-800 transition hover:bg-cyan-500/10 dark:text-slate-100"
                >
                  <FileCode2 className="h-4 w-4 text-emerald-500" />
                  <div>
                    <div>Éditeur config.yaml</div>
                    <div className="text-[10px] text-slate-500 dark:text-slate-400">
                      Valider, importer, exporter &amp; hot-reload
                    </div>
                  </div>
                </button>

                <button
                  type="button"
                  onClick={() => {
                    setToolsOpen(false);
                    onOpenServerConfig();
                  }}
                  className="flex w-full items-center gap-2.5 rounded-xl px-3 py-2 text-left text-xs font-medium text-slate-800 transition hover:bg-cyan-500/10 dark:text-slate-100"
                >
                  <SlidersHorizontal className="h-4 w-4 text-amber-500" />
                  <div>
                    <div>Serveur, Auth &amp; Mode Démo</div>
                    <div className="text-[10px] text-slate-500 dark:text-slate-400">
                      URL Tailscale, Token LAN ou Démo
                    </div>
                  </div>
                </button>
              </div>
            )}
          </div>

          {/* Theme switcher (Desktop) */}
          <button
            type="button"
            onClick={cycleTheme}
            className="liquid-pill hidden items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium text-slate-700 transition hover:text-slate-950 active:scale-95 dark:text-slate-200 dark:hover:text-white xl:inline-flex"
            title={`Thème : ${themeLabel} (cliquer pour basculer)`}
          >
            <ThemeIcon className="h-3.5 w-3.5 text-cyan-600 dark:text-cyan-300" />
            <span>{themeLabel}</span>
          </button>

          <button
            type="button"
            onClick={onToggleAutoRefresh}
            className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1.5 text-xs font-medium transition active:scale-95 ${
              autoRefresh
                ? 'border-emerald-500/35 bg-emerald-500/15 text-emerald-700 hover:bg-emerald-500/25 dark:text-emerald-200'
                : 'liquid-pill text-slate-600 hover:text-slate-950 dark:text-slate-300 dark:hover:text-white'
            }`}
            title="Activer/désactiver l'actualisation auto toutes les 5s"
          >
            {autoRefresh ? (
              <>
                <Pause className="h-3.5 w-3.5" />
                <span className="hidden sm:inline">Live 5s</span>
              </>
            ) : (
              <>
                <Play className="h-3.5 w-3.5" />
                <span className="hidden sm:inline">Pause</span>
              </>
            )}
          </button>

          <button
            type="button"
            onClick={onRefreshNow}
            disabled={isRefreshing}
            className="liquid-pill inline-flex items-center gap-1.5 rounded-full px-2.5 py-1.5 text-xs font-medium text-slate-700 transition hover:text-slate-950 active:scale-95 disabled:opacity-50 dark:text-slate-100 dark:hover:text-white"
            title="Rafraîchir maintenant"
          >
            <RefreshCw
              className={`h-3.5 w-3.5 ${
                isRefreshing ? 'animate-spin text-cyan-500 dark:text-cyan-300' : ''
              }`}
            />
          </button>

          {user && (
            <div className="liquid-pill hidden items-center gap-2 rounded-full py-1 pl-1.5 pr-3 sm:flex">
              {user.profile_pic ? (
                <img
                  src={user.profile_pic}
                  alt={user.name}
                  className="h-6 w-6 rounded-full object-cover"
                />
              ) : (
                <div className="cider-accent-btn flex h-6 w-6 items-center justify-center rounded-full text-[11px] font-semibold text-white">
                  {initials}
                </div>
              )}
              <div className="hidden leading-tight md:block">
                <div className="text-xs font-medium text-slate-900 dark:text-white">
                  {user.name}
                </div>
                <div className="text-[11px] text-slate-500 dark:text-slate-400">
                  {user.login}
                </div>
              </div>
              {canSignOut && (
                <button
                  type="button"
                  onClick={onSignOut}
                  className="ml-1 rounded-full p-1 text-slate-500 hover:bg-rose-500/15 hover:text-rose-500 dark:text-slate-400"
                  title="Déconnexion (effacer le jeton local)"
                >
                  <LogOut className="h-3.5 w-3.5" />
                </button>
              )}
            </div>
          )}
        </div>
      </div>
    </header>
  );
}

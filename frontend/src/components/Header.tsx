import { useEffect, useRef } from 'react';
import {
  Pause,
  Play,
  RefreshCw,
  Search,
  Server,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  Terminal,
  Wrench,
  X,
} from 'lucide-react';
import type { AuthUser } from '../types';

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
  onOpenServerConfig: () => void;
  onOpenSetupWizard: () => void;
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
  onOpenServerConfig,
  onOpenSetupWizard,
}: HeaderProps) {
  const inputRef = useRef<HTMLInputElement>(null);

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

  const initials = (user?.name || user?.login || 'PV')
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() || '')
    .join('');

  return (
    <header className="liquid-glass-elevated safe-top sticky top-0 z-30 border-x-0 border-t-0">
      <div className="mx-auto flex max-w-7xl flex-col gap-3 px-4 pb-3.5 pt-2 sm:px-6 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex items-center justify-between gap-2.5">
          <div className="flex min-w-0 items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border border-cyan-400/35 bg-gradient-to-br from-cyan-400/20 to-indigo-500/20 text-cyan-300 shadow-lg shadow-cyan-500/15">
              <Server className="h-5 w-5" />
            </div>
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="truncate text-base font-semibold tracking-tight text-white sm:text-lg">
                  PVE Center
                </h1>
                <span
                  className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium ${
                    demoActive || user?.auth_mode === 'demo'
                      ? 'border border-indigo-400/35 bg-indigo-500/15 text-indigo-200'
                      : user?.auth_mode === 'dev_bypass'
                        ? 'border border-amber-500/30 bg-amber-500/10 text-amber-300'
                        : 'border border-emerald-400/30 bg-emerald-500/15 text-emerald-200'
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
                  ) : (
                    <>
                      <ShieldCheck className="h-3 w-3" />
                      Tailscale SSO
                    </>
                  )}
                </span>
              </div>
              <p className="truncate text-xs text-slate-400">
                Supervision Proxmox VE &amp; Services
                {lastUpdated && (
                  <span className="ml-2 text-slate-500">
                    • MàJ {lastUpdated.toLocaleTimeString('fr-FR')}
                  </span>
                )}
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={onOpenServerConfig}
            className="liquid-pill inline-flex shrink-0 items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium text-slate-200 transition hover:text-white active:scale-95 lg:hidden"
            title="Configurer le serveur ou activer le Mode Démo"
          >
            <SlidersHorizontal className="h-3.5 w-3.5 text-cyan-300" />
            <span className="hidden sm:inline">Serveur / Démo</span>
            <span className="sm:hidden">Serveur</span>
          </button>
        </div>

        <div className="flex flex-wrap items-center gap-2">
          <div className="relative flex-1 sm:w-64 sm:flex-none">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
            <input
              ref={inputRef}
              type="text"
              value={search}
              onChange={(e) => onSearchChange(e.target.value)}
              placeholder="Filtrer services, LXC, VM… (⌘K)"
              className="w-full rounded-full border border-white/15 bg-white/[0.06] py-1.5 pl-9 pr-8 text-sm text-white placeholder-slate-400 transition focus:border-cyan-400/60 focus:bg-white/[0.1] focus:outline-none focus:ring-2 focus:ring-cyan-400/20"
            />
            {search && (
              <button
                type="button"
                onClick={() => onSearchChange('')}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-white"
                title="Effacer la recherche"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            )}
          </div>

          <button
            type="button"
            onClick={onOpenSetupWizard}
            className={`relative inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition active:scale-95 ${
              needsSetup
                ? 'border-amber-400/45 bg-amber-500/15 text-amber-200 hover:bg-amber-500/25'
                : 'liquid-pill text-slate-200 hover:text-white'
            }`}
            title="Assistant de configuration Proxmox, services, disques & apps"
            aria-label="Configuration"
          >
            <Wrench className={`h-3.5 w-3.5 ${needsSetup ? 'text-amber-300' : 'text-cyan-300'}`} />
            <span className="hidden sm:inline">Configuration</span>
            <span className="sm:hidden">Config</span>
            {needsSetup && (
              <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-400" />
            )}
          </button>

          <button
            type="button"
            onClick={onOpenServerConfig}
            className="liquid-pill hidden items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium text-slate-200 transition hover:text-white active:scale-95 lg:inline-flex"
            title="Configurer l’URL Tailscale Serve ou le Mode Démo"
          >
            <SlidersHorizontal className="h-3.5 w-3.5 text-cyan-300" />
            <span>Serveur / Démo</span>
          </button>

          <button
            type="button"
            onClick={onToggleAutoRefresh}
            className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition active:scale-95 ${
              autoRefresh
                ? 'border-emerald-400/35 bg-emerald-500/15 text-emerald-200 hover:bg-emerald-500/25'
                : 'liquid-pill text-slate-300 hover:text-white'
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
                <span className="hidden sm:inline">En pause</span>
              </>
            )}
          </button>

          <button
            type="button"
            onClick={onRefreshNow}
            disabled={isRefreshing}
            className="liquid-pill inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium text-slate-100 transition hover:text-white active:scale-95 disabled:opacity-50"
            title="Rafraîchir maintenant"
          >
            <RefreshCw
              className={`h-3.5 w-3.5 ${isRefreshing ? 'animate-spin text-cyan-300' : ''}`}
            />
            <span className="hidden sm:inline">Actualiser</span>
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
                <div className="flex h-6 w-6 items-center justify-center rounded-full bg-gradient-to-br from-cyan-400 to-indigo-500 text-[11px] font-semibold text-white">
                  {initials}
                </div>
              )}
              <div className="hidden leading-tight md:block">
                <div className="text-xs font-medium text-white">{user.name}</div>
                <div className="text-[11px] text-slate-400">{user.login}</div>
              </div>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}

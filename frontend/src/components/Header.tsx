import { useEffect, useRef } from 'react';
import {
  Pause,
  Play,
  RefreshCw,
  Search,
  Server,
  ShieldCheck,
  Terminal,
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

  const initials = (user?.name || user?.login || 'AC')
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() || '')
    .join('');

  return (
    <header className="sticky top-0 z-30 border-b border-slate-800/80 bg-slate-950/85 backdrop-blur-xl">
      <div className="mx-auto flex max-w-7xl flex-col gap-3 px-4 py-3.5 sm:px-6 lg:flex-row lg:items-center lg:justify-between">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-cyan-500/30 bg-cyan-500/10 text-cyan-400 shadow-lg shadow-cyan-500/10">
              <Server className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-base font-semibold tracking-tight text-slate-100 sm:text-lg">
                  PVE Command Center
                </h1>
                <span
                  className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium ${
                    user?.auth_mode === 'dev_bypass'
                      ? 'border border-amber-500/30 bg-amber-500/10 text-amber-300'
                      : 'border border-emerald-500/30 bg-emerald-500/10 text-emerald-300'
                  }`}
                >
                  {user?.auth_mode === 'dev_bypass' ? (
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
              <p className="text-xs text-slate-400">
                Supervision privée Proxmox VE &amp; Services
                {lastUpdated && (
                  <span className="ml-2 text-slate-500">
                    • MàJ {lastUpdated.toLocaleTimeString('fr-FR')}
                  </span>
                )}
              </p>
            </div>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2.5">
          <div className="relative flex-1 sm:w-64 sm:flex-none">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500" />
            <input
              ref={inputRef}
              type="text"
              value={search}
              onChange={(e) => onSearchChange(e.target.value)}
              placeholder="Filtrer services, LXC, VM… (⌘K)"
              className="w-full rounded-xl border border-slate-800 bg-slate-900/90 py-1.5 pl-9 pr-8 text-sm text-slate-100 placeholder-slate-500 transition focus:border-cyan-500/50 focus:outline-none focus:ring-2 focus:ring-cyan-500/20"
            />
            {search && (
              <button
                type="button"
                onClick={() => onSearchChange('')}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-300"
                title="Effacer la recherche"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            )}
          </div>

          <button
            type="button"
            onClick={onToggleAutoRefresh}
            className={`inline-flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-xs font-medium transition ${
              autoRefresh
                ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-300 hover:bg-emerald-500/20'
                : 'border-slate-800 bg-slate-900 text-slate-400 hover:bg-slate-800'
            }`}
            title="Activer/désactiver l'actualisation auto toutes les 5s"
          >
            {autoRefresh ? (
              <>
                <Pause className="h-3.5 w-3.5" />
                Live 5s
              </>
            ) : (
              <>
                <Play className="h-3.5 w-3.5" />
                En pause
              </>
            )}
          </button>

          <button
            type="button"
            onClick={onRefreshNow}
            disabled={isRefreshing}
            className="inline-flex items-center gap-1.5 rounded-xl border border-slate-800 bg-slate-900 px-3 py-1.5 text-xs font-medium text-slate-200 transition hover:border-slate-700 hover:bg-slate-800 disabled:opacity-50"
            title="Rafraîchir maintenant"
          >
            <RefreshCw
              className={`h-3.5 w-3.5 ${isRefreshing ? 'animate-spin text-cyan-400' : ''}`}
            />
            <span className="hidden sm:inline">Actualiser</span>
          </button>

          {user && (
            <div className="flex items-center gap-2.5 rounded-xl border border-slate-800 bg-slate-900/90 py-1 pl-1.5 pr-3">
              {user.profile_pic ? (
                <img
                  src={user.profile_pic}
                  alt={user.name}
                  className="h-7 w-7 rounded-lg object-cover"
                />
              ) : (
                <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-gradient-to-br from-cyan-500 to-indigo-600 text-xs font-semibold text-white">
                  {initials}
                </div>
              )}
              <div className="hidden leading-tight sm:block">
                <div className="text-xs font-medium text-slate-200">{user.name}</div>
                <div className="text-[11px] text-slate-400">{user.login}</div>
              </div>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}

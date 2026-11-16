import { useState } from 'react';
import {
  ArrowDown,
  ArrowUp,
  Check,
  Download,
  Film,
  Gauge,
  History,
  Pause,
  Play,
  RefreshCw,
  Sparkles,
  Tv,
  X,
} from 'lucide-react';
import { IncidentsSection } from './IncidentsSection';
import type { IncidentsResponse, OpsOverview } from '../types';

interface OperationsSectionProps {
  ops: OpsOverview | null;
  incidentsData: IncidentsResponse | null;
  search: string;
  onRefreshOps: () => Promise<void>;
  onRefreshIncidents: () => Promise<void>;
  onToast: (toast: { type: 'success' | 'error'; message: string }) => void;
}

type OpsSubView = 'all' | 'incidents' | 'activity';

function formatSpeed(bytesPerSec: number): string {
  if (bytesPerSec >= 1024 * 1024) return `${(bytesPerSec / (1024 * 1024)).toFixed(1)} Mo/s`;
  if (bytesPerSec >= 1024) return `${(bytesPerSec / 1024).toFixed(0)} Ko/s`;
  return `${bytesPerSec} o/s`;
}

function formatSize(bytes: number): string {
  if (!bytes || bytes <= 0) return '0 Mo';
  const gb = bytes / 1024 ** 3;
  if (gb >= 1) return `${gb.toFixed(1)} Go`;
  return `${(bytes / 1024 ** 2).toFixed(0)} Mo`;
}

function formatTimestamp(ts: number): string {
  if (!ts) return '—';
  return new Date(ts * 1000).toLocaleString('fr-FR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function isPausedState(state: string): boolean {
  return state.startsWith('paused') || state.startsWith('stopped');
}

function seerrStatusBadge(status: number, mediaStatus: number) {
  if (mediaStatus === 5) {
    return (
      <span className="rounded-full border border-emerald-500/30 bg-emerald-500/10 px-2 py-0.5 text-[10px] font-medium text-emerald-700 dark:text-emerald-300">
        Disponible
      </span>
    );
  }
  if (status === 1) {
    return (
      <span className="rounded-full border border-amber-500/30 bg-amber-500/10 px-2 py-0.5 text-[10px] font-medium text-amber-700 dark:text-amber-300">
        En attente
      </span>
    );
  }
  if (status === 2) {
    return (
      <span className="rounded-full border border-cyan-500/30 bg-cyan-500/10 px-2 py-0.5 text-[10px] font-medium text-cyan-700 dark:text-cyan-300">
        Approuvée
      </span>
    );
  }
  return (
    <span className="rounded-full border border-rose-500/30 bg-rose-500/10 px-2 py-0.5 text-[10px] font-medium text-rose-700 dark:text-rose-300">
      Refusée
    </span>
  );
}

export function OperationsSection({
  ops,
  incidentsData,
  search,
  onRefreshOps,
  onRefreshIncidents,
  onToast,
}: OperationsSectionProps) {
  const [busyKey, setBusyKey] = useState<string | null>(null);
  const [subView, setSubView] = useState<OpsSubView>('all');

  const runAction = async (
    key: string,
    url: string,
    successMessage: string
  ) => {
    setBusyKey(key);
    try {
      const resp = await fetch(url, { method: 'POST' });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      }
      onToast({ type: 'success', message: successMessage });
      await onRefreshOps();
    } catch (err) {
      onToast({
        type: 'error',
        message: err instanceof Error ? err.message : 'Erreur d’exécution.',
      });
    } finally {
      setBusyKey(null);
    }
  };

  const query = search.trim().toLowerCase();
  const requests = (ops?.seerr_requests || []).filter(
    (r) =>
      !query ||
      r.title.toLowerCase().includes(query) ||
      r.requested_by.toLowerCase().includes(query)
  );
  const torrents = (ops?.qbit_control.torrents || []).filter(
    (t) => !query || t.name.toLowerCase().includes(query)
  );
  const tasks = (ops?.pve_tasks || []).filter(
    (t) =>
      !query ||
      t.type.toLowerCase().includes(query) ||
      t.vmid.includes(query) ||
      t.user.toLowerCase().includes(query)
  );

  const activeIncidentsCount = incidentsData?.active_count ?? 0;

  return (
    <section className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="liquid-pill inline-flex items-center gap-1 rounded-full p-1 text-xs">
          {(
            [
              { id: 'all', label: 'Vue complète' },
              {
                id: 'incidents',
                label: `Incidents & Alertes${activeIncidentsCount > 0 ? ` (${activeIncidentsCount})` : ''}`,
              },
              { id: 'activity', label: 'Médias, Torrents & PVE' },
            ] as const
          ).map((item) => (
            <button
              key={item.id}
              type="button"
              onClick={() => setSubView(item.id)}
              className={`rounded-full px-3 py-1 font-medium transition ${
                subView === item.id
                  ? 'bg-cyan-500/20 text-cyan-800 dark:bg-white/15 dark:text-white'
                  : 'text-slate-600 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white'
              }`}
            >
              {item.label}
            </button>
          ))}
        </div>
      </div>

      {(subView === 'all' || subView === 'incidents') && (
        <IncidentsSection
          incidentsData={incidentsData}
          search={search}
          onRefresh={onRefreshIncidents}
          onToast={onToast}
        />
      )}

      {(subView === 'all' || subView === 'activity') &&
        (!ops ? (
          <div className="liquid-glass rounded-3xl p-6">
            <div className="animate-pulse text-sm text-slate-500 dark:text-slate-400">
              Chargement du centre d’activité et des actions rapides…
            </div>
          </div>
        ) : (
          <>
            {/* Barre d'actions rapides Médias & Torrents */}
            <div className="liquid-glass flex flex-wrap items-center justify-between gap-3 rounded-3xl p-4">
              <div>
                <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-900 dark:text-slate-200">
                  Actions Rapides Médias &amp; Téléchargements
                </h2>
                <p className="text-xs text-slate-500 dark:text-slate-400">
                  Scans manuels des bibliothèques et régulation de bande passante qBittorrent
                </p>
              </div>

              <div className="flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  disabled={busyKey !== null}
                  onClick={() =>
                    runAction(
                      'scan-jf',
                      '/api/ops/media/scan/jellyfin',
                      'Scan des médiathèques Jellyfin déclenché !'
                    )
                  }
                  className="inline-flex items-center gap-1.5 rounded-xl border border-cyan-500/35 bg-cyan-500/10 px-3 py-1.5 text-xs font-medium text-cyan-800 transition hover:bg-cyan-500/20 disabled:opacity-50 dark:text-cyan-200"
                >
                  <RefreshCw
                    className={`h-3.5 w-3.5 ${busyKey === 'scan-jf' ? 'animate-spin' : ''}`}
                  />
                  Scanner Jellyfin
                </button>

                <button
                  type="button"
                  disabled={busyKey !== null}
                  onClick={() =>
                    runAction(
                      'scan-plex',
                      '/api/ops/media/scan/plex',
                      'Scan des bibliothèques Plex lancé !'
                    )
                  }
                  className="inline-flex items-center gap-1.5 rounded-xl border border-amber-500/35 bg-amber-500/10 px-3 py-1.5 text-xs font-medium text-amber-800 transition hover:bg-amber-500/20 disabled:opacity-50 dark:text-amber-200"
                >
                  <RefreshCw
                    className={`h-3.5 w-3.5 ${busyKey === 'scan-plex' ? 'animate-spin' : ''}`}
                  />
                  Scanner Plex
                </button>

                {ops.qbit_control.available && (
                  <button
                    type="button"
                    disabled={busyKey !== null}
                    onClick={() =>
                      runAction(
                        'qbit-mode',
                        '/api/ops/qbit/toggle-speed-mode',
                        ops.qbit_control.alt_speed_enabled
                          ? 'Vitesse maximale qBittorrent rétablie.'
                          : 'Mode Tortue (limite alternative) qBittorrent activé.'
                      )
                    }
                    className={`inline-flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-xs font-medium transition disabled:opacity-50 ${
                      ops.qbit_control.alt_speed_enabled
                        ? 'border-emerald-500/40 bg-emerald-500/15 text-emerald-800 hover:bg-emerald-500/25 dark:text-emerald-200'
                        : 'border-slate-300/80 bg-white/70 text-slate-700 hover:bg-white dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700'
                    }`}
                  >
                    <Gauge className="h-3.5 w-3.5" />
                    Mode Tortue :{' '}
                    {ops.qbit_control.alt_speed_enabled ? 'Actif' : 'Désactivé'}
                  </button>
                )}
              </div>
            </div>

            {/* Demandes Jellyseerr & Contrôle Torrents */}
            <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
              {/* Colonne 1 : Demandes Jellyseerr */}
              <div className="liquid-glass rounded-3xl p-4">
                <div className="mb-3 flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Sparkles className="h-4 w-4 text-indigo-500 dark:text-indigo-400" />
                    <h3 className="text-sm font-semibold uppercase tracking-wider text-slate-800 dark:text-slate-300">
                      Demandes Jellyseerr ({requests.length})
                    </h3>
                  </div>
                </div>

                <div className="space-y-2">
                  {requests.map((req) => (
                    <div
                      key={req.id}
                      className="liquid-subcard flex items-center justify-between gap-3 px-3 py-2.5"
                    >
                      <div className="flex min-w-0 items-center gap-2.5">
                        <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg border border-slate-200 bg-white text-slate-600 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-300">
                          {req.media_type === 'tv' ? (
                            <Tv className="h-3.5 w-3.5 text-indigo-500 dark:text-indigo-400" />
                          ) : (
                            <Film className="h-3.5 w-3.5 text-cyan-500 dark:text-cyan-400" />
                          )}
                        </span>
                        <div className="min-w-0">
                          <div className="truncate text-xs font-semibold text-slate-900 dark:text-slate-100">
                            {req.title}
                          </div>
                          <div className="text-[11px] text-slate-500 dark:text-slate-400">
                            Par <span className="text-slate-700 dark:text-slate-300">{req.requested_by}</span> •{' '}
                            {req.created_at.slice(0, 10)}
                          </div>
                        </div>
                      </div>

                      <div className="flex shrink-0 items-center gap-1.5">
                        {req.status === 1 ? (
                          <>
                            <button
                              type="button"
                              disabled={busyKey !== null}
                              onClick={() =>
                                runAction(
                                  `approve-${req.id}`,
                                  `/api/ops/seerr/${req.id}/approve`,
                                  `Demande "${req.title}" approuvée.`
                                )
                              }
                              className="rounded-lg border border-emerald-500/35 bg-emerald-500/15 p-1.5 text-emerald-700 hover:bg-emerald-500/25 disabled:opacity-50 dark:text-emerald-300"
                              title="Approuver"
                            >
                              <Check className="h-3.5 w-3.5" />
                            </button>
                            <button
                              type="button"
                              disabled={busyKey !== null}
                              onClick={() =>
                                runAction(
                                  `decline-${req.id}`,
                                  `/api/ops/seerr/${req.id}/decline`,
                                  `Demande "${req.title}" refusée.`
                                )
                              }
                              className="rounded-lg border border-rose-500/35 bg-rose-500/15 p-1.5 text-rose-700 hover:bg-rose-500/25 disabled:opacity-50 dark:text-rose-300"
                              title="Refuser"
                            >
                              <X className="h-3.5 w-3.5" />
                            </button>
                          </>
                        ) : (
                          seerrStatusBadge(req.status, req.media_status)
                        )}
                      </div>
                    </div>
                  ))}

                  {requests.length === 0 && (
                    <div className="liquid-subcard p-4 text-center text-xs text-slate-500">
                      Aucune demande Jellyseerr trouvée.
                    </div>
                  )}
                </div>
              </div>

              {/* Colonne 2 : Torrents qBittorrent récents */}
              <div className="liquid-glass rounded-3xl p-4">
                <div className="mb-3 flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Download className="h-4 w-4 text-emerald-500 dark:text-emerald-400" />
                    <h3 className="text-sm font-semibold uppercase tracking-wider text-slate-800 dark:text-slate-300">
                      Torrents qBittorrent récents ({torrents.length})
                    </h3>
                  </div>
                </div>

                <div className="space-y-2">
                  {torrents.map((tor) => {
                    const paused = isPausedState(tor.state);
                    const action = paused ? 'resume' : 'pause';
                    return (
                      <div key={tor.hash} className="liquid-subcard px-3 py-2.5">
                        <div className="flex items-center justify-between gap-2">
                          <div className="min-w-0 flex-1">
                            <div className="truncate text-xs font-medium text-slate-900 dark:text-slate-100">
                              {tor.name}
                            </div>
                            <div className="mt-0.5 flex flex-wrap items-center gap-2 text-[11px] text-slate-500 dark:text-slate-400">
                              <span className="font-mono text-slate-700 dark:text-slate-300">
                                {tor.progress_pct}%
                              </span>
                              <span>• {formatSize(tor.size)}</span>
                              {tor.dlspeed > 0 && (
                                <span className="inline-flex items-center gap-0.5 text-emerald-700 dark:text-emerald-300">
                                  <ArrowDown className="h-3 w-3" />
                                  {formatSpeed(tor.dlspeed)}
                                </span>
                              )}
                              {tor.upspeed > 0 && (
                                <span className="inline-flex items-center gap-0.5 text-cyan-700 dark:text-cyan-300">
                                  <ArrowUp className="h-3 w-3" />
                                  {formatSpeed(tor.upspeed)}
                                </span>
                              )}
                              <span className="rounded bg-slate-200/80 px-1.5 py-0.2 text-[10px] text-slate-600 dark:bg-slate-800 dark:text-slate-400">
                                {tor.state}
                              </span>
                            </div>
                          </div>

                          <button
                            type="button"
                            disabled={busyKey !== null}
                            onClick={() =>
                              runAction(
                                `tor-${tor.hash}`,
                                `/api/ops/qbit/torrent/${tor.hash}/${action}`,
                                paused ? 'Torrent relancé.' : 'Torrent mis en pause.'
                              )
                            }
                            className={`shrink-0 rounded-lg border p-1.5 transition disabled:opacity-50 ${
                              paused
                                ? 'border-emerald-500/35 bg-emerald-500/10 text-emerald-700 hover:bg-emerald-500/20 dark:text-emerald-300'
                                : 'border-amber-500/35 bg-amber-500/10 text-amber-700 hover:bg-amber-500/20 dark:text-amber-300'
                            }`}
                            title={paused ? 'Reprendre' : 'Mettre en pause'}
                          >
                            {paused ? (
                              <Play className="h-3.5 w-3.5" />
                            ) : (
                              <Pause className="h-3.5 w-3.5" />
                            )}
                          </button>
                        </div>

                        <div className="mt-1.5 h-1 w-full overflow-hidden rounded-full bg-slate-200 dark:bg-slate-800">
                          <div
                            className={`h-full rounded-full ${
                              tor.progress_pct >= 100 ? 'bg-emerald-500' : 'bg-cyan-500'
                            }`}
                            style={{ width: `${Math.min(tor.progress_pct, 100)}%` }}
                          />
                        </div>
                      </div>
                    );
                  })}

                  {torrents.length === 0 && (
                    <div className="liquid-subcard p-4 text-center text-xs text-slate-500">
                      Aucun torrent actif ou récent.
                    </div>
                  )}
                </div>
              </div>
            </div>

            {/* Journal des tâches Proxmox VE */}
            <div className="liquid-glass overflow-hidden rounded-3xl">
              <div className="flex items-center gap-2 border-b border-slate-200/80 px-4 py-3 dark:border-slate-800/80">
                <History className="h-4 w-4 text-cyan-500 dark:text-cyan-400" />
                <h3 className="text-sm font-semibold uppercase tracking-wider text-slate-800 dark:text-slate-300">
                  Journal des tâches Proxmox VE ({tasks.length})
                </h3>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs">
                  <thead>
                    <tr className="border-b border-slate-200/70 bg-slate-100/70 text-[11px] uppercase text-slate-500 dark:border-slate-800/70 dark:bg-slate-950/40">
                      <th className="px-4 py-2.5">Action</th>
                      <th className="px-4 py-2.5">Cible</th>
                      <th className="hidden px-4 py-2.5 sm:table-cell">Utilisateur</th>
                      <th className="px-4 py-2.5">Date</th>
                      <th className="hidden px-4 py-2.5 md:table-cell">Durée</th>
                      <th className="px-4 py-2.5 text-right">Statut</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-200/60 dark:divide-slate-800/50">
                    {tasks.map((task) => {
                      const ok = task.status === 'OK';
                      return (
                        <tr key={task.upid} className="hover:bg-black/[0.02] dark:hover:bg-slate-800/30">
                          <td className="px-4 py-2 font-mono font-medium text-slate-800 dark:text-slate-200">
                            {task.type}
                          </td>
                          <td className="px-4 py-2 font-mono text-slate-600 dark:text-slate-400">
                            {task.vmid ? `#${task.vmid}` : 'Nœud'}
                          </td>
                          <td className="hidden px-4 py-2 text-slate-600 dark:text-slate-400 sm:table-cell">
                            {task.user}
                          </td>
                          <td className="px-4 py-2 text-slate-600 dark:text-slate-400">
                            {formatTimestamp(task.starttime)}
                          </td>
                          <td className="hidden px-4 py-2 font-mono text-slate-600 dark:text-slate-400 md:table-cell">
                            {task.duration_sec !== null ? `${task.duration_sec}s` : 'En cours'}
                          </td>
                          <td className="px-4 py-2 text-right">
                            <span
                              className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${
                                ok
                                  ? 'border border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300'
                                  : 'border border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300'
                              }`}
                            >
                              {task.status}
                            </span>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        ))}
    </section>
  );
}

import { useState } from 'react';
import {
  AlertOctagon,
  AlertTriangle,
  Bell,
  BellOff,
  Check,
  CheckCircle2,
  Clock,
  Info,
  Loader2,
  RefreshCw,
  ShieldAlert,
} from 'lucide-react';
import type { IncidentItem, IncidentsResponse, ServiceStateItem } from '../types';

interface IncidentsSectionProps {
  incidentsData: IncidentsResponse | null;
  search: string;
  onRefresh: () => Promise<void>;
  onToast: (toast: { type: 'success' | 'error'; message: string }) => void;
}

type IncidentFilter = 'all' | 'active' | 'unacked' | 'resolved';

function formatIsoDateTime(iso: string | null): string {
  if (!iso) return '—';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleString('fr-FR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function formatDuration(startIso: string, endIso: string | null): string {
  const start = new Date(startIso).getTime();
  const end = endIso ? new Date(endIso).getTime() : Date.now();
  if (Number.isNaN(start) || Number.isNaN(end)) return '—';
  const sec = Math.max(0, Math.floor((end - start) / 1000));
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min} min`;
  const hrs = Math.floor(min / 60);
  const remMin = min % 60;
  return remMin > 0 ? `${hrs}h ${remMin}m` : `${hrs}h`;
}

function isServiceMuted(mutedUntil: string | null): boolean {
  if (!mutedUntil) return false;
  const dt = new Date(mutedUntil).getTime();
  return !Number.isNaN(dt) && dt > Date.now();
}

function severityMeta(severity: string) {
  const norm = severity.toLowerCase();
  if (norm === 'critical') {
    return {
      label: 'Critique',
      icon: AlertOctagon,
      badge:
        'border-rose-500/35 bg-rose-500/15 text-rose-700 dark:text-rose-200',
      iconColor: 'text-rose-500 dark:text-rose-400',
    };
  }
  if (norm === 'warning' || norm === 'warn') {
    return {
      label: 'Alerte',
      icon: AlertTriangle,
      badge:
        'border-amber-500/35 bg-amber-500/15 text-amber-700 dark:text-amber-200',
      iconColor: 'text-amber-500 dark:text-amber-400',
    };
  }
  return {
    label: 'Info',
    icon: Info,
    badge:
      'border-cyan-500/35 bg-cyan-500/15 text-cyan-700 dark:text-cyan-200',
    iconColor: 'text-cyan-500 dark:text-cyan-400',
  };
}

export function IncidentsSection({
  incidentsData,
  search,
  onRefresh,
  onToast,
}: IncidentsSectionProps) {
  const [filter, setFilter] = useState<IncidentFilter>('all');
  const [busyKey, setBusyKey] = useState<string | null>(null);

  if (!incidentsData) {
    return (
      <section className="liquid-glass rounded-3xl p-6">
        <div className="animate-pulse text-sm text-slate-500 dark:text-slate-400">
          Chargement de la chronologie des incidents et des états d’alerte…
        </div>
      </section>
    );
  }

  const query = search.trim().toLowerCase();
  const stateByServiceId = new Map<string, ServiceStateItem>();
  for (const st of incidentsData.service_states || []) {
    stateByServiceId.set(st.service_id, st);
  }

  const filteredIncidents = (incidentsData.incidents || []).filter((inc) => {
    if (filter === 'active' && inc.resolved_at !== null) return false;
    if (filter === 'unacked' && (inc.acknowledged || inc.resolved_at !== null)) return false;
    if (filter === 'resolved' && inc.resolved_at === null) return false;
    if (!query) return true;
    return (
      inc.service_name.toLowerCase().includes(query) ||
      inc.title.toLowerCase().includes(query) ||
      inc.message.toLowerCase().includes(query)
    );
  });

  const monitoredStates = (incidentsData.service_states || []).filter(
    (st) =>
      !query ||
      st.service_name.toLowerCase().includes(query) ||
      st.service_id.toLowerCase().includes(query)
  );

  const handleAck = async (incident: IncidentItem) => {
    setBusyKey(`ack-${incident.id}`);
    try {
      const resp = await fetch(`/api/incidents/${encodeURIComponent(incident.id)}/ack`, {
        method: 'POST',
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      onToast({ type: 'success', message: `Incident « ${incident.title} » acquitté.` });
      await onRefresh();
    } catch (err) {
      onToast({
        type: 'error',
        message: err instanceof Error ? err.message : 'Échec de l’acquittement.',
      });
    } finally {
      setBusyKey(null);
    }
  };

  const handleToggleMute = async (serviceId: string, serviceName: string, currentlyMuted: boolean) => {
    setBusyKey(`mute-${serviceId}`);
    try {
      const resp = await fetch(
        `/api/incidents/services/${encodeURIComponent(serviceId)}/mute`,
        currentlyMuted
          ? { method: 'DELETE' }
          : {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ minutes: 60 }),
            }
      );
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      onToast({
        type: 'success',
        message: currentlyMuted
          ? `Alertes réactivées pour « ${serviceName} ».`
          : `Alertes coupées pendant 1h pour « ${serviceName} ».`,
      });
      await onRefresh();
    } catch (err) {
      onToast({
        type: 'error',
        message: err instanceof Error ? err.message : 'Impossible de modifier le mode silencieux.',
      });
    } finally {
      setBusyKey(null);
    }
  };

  return (
    <section id="incidents-timeline" className="space-y-4">
      <div className="liquid-glass rounded-3xl p-4 sm:p-5">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border border-rose-500/30 bg-rose-500/15 text-rose-600 dark:text-rose-300">
              <ShieldAlert className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-900 dark:text-white">
                  Chronologie des Incidents &amp; Alertes
                </h2>
                <span
                  className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                    incidentsData.active_count > 0
                      ? 'border border-rose-500/35 bg-rose-500/15 text-rose-700 dark:text-rose-200'
                      : 'border border-emerald-500/35 bg-emerald-500/15 text-emerald-700 dark:text-emerald-200'
                  }`}
                >
                  {incidentsData.active_count > 0
                    ? `${incidentsData.active_count} actif(s)`
                    : 'Nominal'}
                </span>
              </div>
              <p className="text-xs text-slate-500 dark:text-slate-400">
                Suivi temps réel des pannes, acquittement opérateur et mise en sourdine temporaire (Mute 1h)
              </p>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            <div className="liquid-pill flex items-center gap-1 rounded-full p-1 text-xs">
              {(
                [
                  { id: 'all', label: `Tous (${incidentsData.count})` },
                  { id: 'active', label: `Actifs (${incidentsData.active_count})` },
                  { id: 'unacked', label: 'À acquitter' },
                  { id: 'resolved', label: 'Résolus' },
                ] as const
              ).map((tab) => (
                <button
                  key={tab.id}
                  type="button"
                  onClick={() => setFilter(tab.id)}
                  className={`rounded-full px-2.5 py-1 text-[11px] font-medium transition ${
                    filter === tab.id
                      ? 'bg-cyan-500/20 text-cyan-800 dark:bg-white/15 dark:text-white'
                      : 'text-slate-600 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>

            <button
              type="button"
              onClick={() => void onRefresh()}
              className="liquid-pill rounded-full p-2 text-slate-600 hover:text-slate-900 dark:text-slate-300 dark:hover:text-white"
              title="Actualiser les incidents"
            >
              <RefreshCw className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>

        {/* États des services & boutons Mute 1h / Activer alertes */}
        {monitoredStates.length > 0 && (
          <div className="mt-4 flex flex-wrap gap-2 border-t border-slate-200/80 pt-3.5 dark:border-white/10">
            {monitoredStates.map((st) => {
              const muted = isServiceMuted(st.muted_until);
              const busy = busyKey === `mute-${st.service_id}`;
              const statusDot =
                st.current_status === 'up'
                  ? 'bg-emerald-500'
                  : st.current_status === 'degraded'
                    ? 'bg-amber-500'
                    : st.current_status === 'down'
                      ? 'bg-rose-500'
                      : 'bg-slate-400';

              return (
                <div
                  key={st.service_id}
                  className="liquid-subcard flex items-center gap-2 rounded-full px-3 py-1.5 text-xs"
                >
                  <span className={`h-2 w-2 shrink-0 rounded-full ${statusDot}`} />
                  <span className="font-medium text-slate-800 dark:text-slate-100">
                    {st.service_name}
                  </span>
                  {st.last_latency_ms !== null && st.current_status === 'up' && (
                    <span className="font-mono text-[10px] text-slate-500 dark:text-slate-400">
                      {st.last_latency_ms}ms
                    </span>
                  )}
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() =>
                      void handleToggleMute(st.service_id, st.service_name, muted)
                    }
                    className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold transition ${
                      muted
                        ? 'border border-amber-500/35 bg-amber-500/15 text-amber-700 hover:bg-amber-500/25 dark:text-amber-200'
                        : 'border border-slate-300/80 bg-white/70 text-slate-600 hover:text-slate-900 dark:border-white/15 dark:bg-white/[0.06] dark:text-slate-300 dark:hover:text-white'
                    }`}
                    title={
                      muted
                        ? `En sourdine jusqu'à ${formatIsoDateTime(st.muted_until)}`
                        : 'Couper les alertes pendant 1h'
                    }
                  >
                    {busy ? (
                      <Loader2 className="h-3 w-3 animate-spin" />
                    ) : muted ? (
                      <>
                        <Bell className="h-3 w-3" />
                        Activer alertes
                      </>
                    ) : (
                      <>
                        <BellOff className="h-3 w-3" />
                        Mute 1h
                      </>
                    )}
                  </button>
                </div>
              );
            })}
          </div>
        )}

        {/* Timeline des incidents */}
        <div className="mt-4 space-y-2.5">
          {filteredIncidents.length === 0 ? (
            <div className="liquid-subcard flex items-center justify-center gap-2 p-6 text-xs text-slate-500 dark:text-slate-400">
              <CheckCircle2 className="h-4 w-4 text-emerald-500" />
              <span>Aucun incident pour ce filtre.</span>
            </div>
          ) : (
            filteredIncidents.map((inc) => {
              const meta = severityMeta(inc.severity);
              const SevIcon = meta.icon;
              const isResolved = inc.resolved_at !== null;
              const svcState = stateByServiceId.get(inc.service_id);
              const muted = isServiceMuted(svcState?.muted_until || null);

              return (
                <div
                  key={inc.id}
                  className={`liquid-subcard flex flex-col justify-between gap-3 p-3.5 sm:flex-row sm:items-center ${
                    !isResolved ? 'ring-1 ring-rose-500/25' : 'opacity-85'
                  }`}
                >
                  <div className="flex min-w-0 items-start gap-3">
                    <div className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-slate-200/80 bg-white/75 dark:border-white/10 dark:bg-white/[0.05]">
                      <SevIcon className={`h-4 w-4 ${meta.iconColor}`} />
                    </div>
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-xs font-semibold text-slate-900 dark:text-white">
                          {inc.title}
                        </span>
                        <span
                          className={`rounded-full border px-2 py-0.5 text-[10px] font-semibold ${meta.badge}`}
                        >
                          {meta.label}
                        </span>
                        {isResolved ? (
                          <span className="rounded-full border border-emerald-500/30 bg-emerald-500/10 px-2 py-0.5 text-[10px] font-medium text-emerald-700 dark:text-emerald-300">
                            Résolu ({formatDuration(inc.started_at, inc.resolved_at)})
                          </span>
                        ) : (
                          <span className="rounded-full border border-rose-500/30 bg-rose-500/10 px-2 py-0.5 text-[10px] font-semibold text-rose-700 dark:text-rose-300">
                            En cours ({formatDuration(inc.started_at, null)})
                          </span>
                        )}
                        {inc.acknowledged && (
                          <span className="inline-flex items-center gap-1 rounded-full border border-indigo-500/30 bg-indigo-500/10 px-2 py-0.5 text-[10px] font-medium text-indigo-700 dark:text-indigo-200">
                            <Check className="h-3 w-3" />
                            Acquitté
                          </span>
                        )}
                      </div>

                      <p className="mt-1 text-xs text-slate-600 dark:text-slate-300">
                        {inc.message}
                      </p>

                      <div className="mt-1.5 flex flex-wrap items-center gap-3 text-[11px] text-slate-500 dark:text-slate-400">
                        <span className="font-mono">{inc.service_name}</span>
                        <span className="inline-flex items-center gap-1">
                          <Clock className="h-3 w-3" />
                          Début : {formatIsoDateTime(inc.started_at)}
                        </span>
                        {inc.resolved_at && (
                          <span>Fin : {formatIsoDateTime(inc.resolved_at)}</span>
                        )}
                      </div>
                    </div>
                  </div>

                  <div className="flex shrink-0 flex-wrap items-center gap-2">
                    {!inc.acknowledged && (
                      <button
                        type="button"
                        disabled={busyKey === `ack-${inc.id}`}
                        onClick={() => void handleAck(inc)}
                        className="inline-flex items-center gap-1.5 rounded-xl border border-cyan-500/35 bg-cyan-500/15 px-3 py-1.5 text-xs font-semibold text-cyan-800 transition hover:bg-cyan-500/25 disabled:opacity-50 dark:text-cyan-200"
                      >
                        {busyKey === `ack-${inc.id}` ? (
                          <Loader2 className="h-3.5 w-3.5 animate-spin" />
                        ) : (
                          <Check className="h-3.5 w-3.5" />
                        )}
                        Acquitter
                      </button>
                    )}

                    <button
                      type="button"
                      disabled={busyKey === `mute-${inc.service_id}`}
                      onClick={() =>
                        void handleToggleMute(inc.service_id, inc.service_name, muted)
                      }
                      className={`inline-flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-xs font-medium transition disabled:opacity-50 ${
                        muted
                          ? 'border-amber-500/35 bg-amber-500/15 text-amber-800 hover:bg-amber-500/25 dark:text-amber-200'
                          : 'border-slate-300/80 bg-white/70 text-slate-700 hover:bg-white dark:border-white/15 dark:bg-white/[0.06] dark:text-slate-200 dark:hover:bg-white/10'
                      }`}
                    >
                      {muted ? (
                        <>
                          <Bell className="h-3.5 w-3.5" />
                          Activer alertes
                        </>
                      ) : (
                        <>
                          <BellOff className="h-3.5 w-3.5" />
                          Mute 1h
                        </>
                      )}
                    </button>
                  </div>
                </div>
              );
            })
          )}
        </div>
      </div>
    </section>
  );
}

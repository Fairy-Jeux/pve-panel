import type { ComponentType } from 'react';
import {
  Activity,
  ArrowDown,
  ArrowUp,
  Clapperboard,
  Cloud,
  Download,
  ExternalLink,
  Film,
  Gamepad2,
  Globe,
  LayoutGrid,
  Play,
  Radar,
  Router,
  Server,
  Shield,
  Sparkles,
  Tv,
} from 'lucide-react';
import type {
  JellyfinWidget,
  PlexWidget,
  ProwlarrWidget,
  QbittorrentWidget,
  RadarrWidget,
  ServiceItem,
  SonarrWidget,
  WidgetsMap,
} from '../types';

const ICONS: Record<string, ComponentType<{ className?: string }>> = {
  Film,
  Play,
  Sparkles,
  Clapperboard,
  Tv,
  Radar,
  Download,
  Cloud,
  Shield,
  Gamepad2,
  Server,
  Globe,
  Activity,
  LayoutGrid,
  Router,
};

function formatSpeed(bytesPerSec: number | undefined): string {
  const val = bytesPerSec || 0;
  if (val >= 1024 * 1024) return `${(val / (1024 * 1024)).toFixed(1)} Mo/s`;
  if (val >= 1024) return `${(val / 1024).toFixed(0)} Ko/s`;
  return `${val} o/s`;
}

function MetricPill({
  label,
  value,
  highlight = false,
}: {
  label: string;
  value: string | number;
  highlight?: boolean;
}) {
  return (
    <div className="rounded-lg border border-slate-800/80 bg-slate-950/60 px-2.5 py-1.5">
      <div className="text-[10px] uppercase tracking-wider text-slate-500">{label}</div>
      <div
        className={`mt-0.5 font-mono text-xs font-semibold ${
          highlight ? 'text-cyan-300' : 'text-slate-200'
        }`}
      >
        {value}
      </div>
    </div>
  );
}

function renderWidget(widgetType: string | undefined, widgets: WidgetsMap) {
  if (!widgetType) return null;

  if (widgetType === 'jellyfin') {
    const data = widgets.jellyfin as JellyfinWidget | undefined;
    if (!data || data.status !== 'ok') {
      return <div className="text-xs text-slate-500">Métriques indisponibles</div>;
    }
    const streams = data.active_streams || [];
    return (
      <div className="space-y-2">
        <div className="grid grid-cols-3 gap-2">
          <MetricPill
            label="Flux actifs"
            value={data.active_streams_count ?? 0}
            highlight={(data.active_streams_count ?? 0) > 0}
          />
          <MetricPill label="Films" value={data.movies_count ?? 0} />
          <MetricPill label="Séries" value={data.series_count ?? 0} />
        </div>
        {streams.length > 0 && (
          <div className="space-y-1 rounded-lg border border-cyan-500/20 bg-cyan-500/5 p-2 text-[11px]">
            {streams.map((s, idx) => (
              <div key={idx} className="flex items-center justify-between gap-2">
                <span className="truncate font-medium text-cyan-200">
                  {s.is_paused ? '⏸ ' : '▶ '}
                  {s.title}
                </span>
                <span className="shrink-0 text-slate-400">{s.user}</span>
              </div>
            ))}
          </div>
        )}
      </div>
    );
  }

  if (widgetType === 'plex') {
    const data = widgets.plex as PlexWidget | undefined;
    if (!data || data.status !== 'ok') {
      return <div className="text-xs text-slate-500">Métriques indisponibles</div>;
    }
    return (
      <div className="grid grid-cols-3 gap-2">
        <MetricPill
          label="Flux actifs"
          value={data.active_streams_count ?? 0}
          highlight={(data.active_streams_count ?? 0) > 0}
        />
        <MetricPill label="Biblio." value={data.libraries_count ?? 0} />
        <MetricPill label="Version" value={data.version || 'OK'} />
      </div>
    );
  }

  if (widgetType === 'radarr') {
    const data = widgets.radarr as RadarrWidget | undefined;
    if (!data || data.status !== 'ok') {
      return <div className="text-xs text-slate-500">Métriques indisponibles</div>;
    }
    return (
      <div className="space-y-2">
        <div className="grid grid-cols-3 gap-2">
          <MetricPill label="Films" value={data.movies_downloaded ?? 0} />
          <MetricPill label="Manquants" value={data.movies_missing ?? 0} />
          <MetricPill
            label="En file"
            value={data.queue_count ?? 0}
            highlight={(data.queue_count ?? 0) > 0}
          />
        </div>
        {data.upcoming && data.upcoming.length > 0 && (
          <div className="truncate text-[11px] text-slate-400">
            Prochain : <span className="text-slate-200">{data.upcoming[0].title}</span>{' '}
            <span className="text-slate-500">({data.upcoming[0].date})</span>
          </div>
        )}
      </div>
    );
  }

  if (widgetType === 'sonarr') {
    const data = widgets.sonarr as SonarrWidget | undefined;
    if (!data || data.status !== 'ok') {
      return <div className="text-xs text-slate-500">Métriques indisponibles</div>;
    }
    return (
      <div className="space-y-2">
        <div className="grid grid-cols-3 gap-2">
          <MetricPill label="Séries" value={data.series_total ?? 0} />
          <MetricPill label="Épisodes" value={data.episodes_downloaded ?? 0} />
          <MetricPill
            label="En file"
            value={data.queue_count ?? 0}
            highlight={(data.queue_count ?? 0) > 0}
          />
        </div>
        {data.upcoming && data.upcoming.length > 0 && (
          <div className="truncate text-[11px] text-slate-400">
            À venir : <span className="text-slate-200">{data.upcoming[0].title}</span>{' '}
            <span className="text-slate-500">({data.upcoming[0].date})</span>
          </div>
        )}
      </div>
    );
  }

  if (widgetType === 'qbittorrent') {
    const data = widgets.qbittorrent as QbittorrentWidget | undefined;
    if (!data || data.status !== 'ok') {
      return <div className="text-xs text-slate-500">Métriques indisponibles</div>;
    }
    return (
      <div className="grid grid-cols-3 gap-2">
        <div className="rounded-lg border border-slate-800/80 bg-slate-950/60 px-2.5 py-1.5">
          <div className="flex items-center gap-1 text-[10px] uppercase text-slate-500">
            <ArrowDown className="h-3 w-3 text-emerald-400" />
            DL
          </div>
          <div className="mt-0.5 font-mono text-xs font-semibold text-emerald-300">
            {formatSpeed(data.dl_speed_bytes)}
          </div>
        </div>
        <div className="rounded-lg border border-slate-800/80 bg-slate-950/60 px-2.5 py-1.5">
          <div className="flex items-center gap-1 text-[10px] uppercase text-slate-500">
            <ArrowUp className="h-3 w-3 text-cyan-400" />
            UP
          </div>
          <div className="mt-0.5 font-mono text-xs font-semibold text-cyan-300">
            {formatSpeed(data.up_speed_bytes)}
          </div>
        </div>
        <MetricPill
          label="DL / Seed"
          value={`${data.downloading_count ?? 0} / ${data.seeding_count ?? 0}`}
        />
      </div>
    );
  }

  if (widgetType === 'prowlarr') {
    const data = widgets.prowlarr as ProwlarrWidget | undefined;
    if (!data || data.status !== 'ok') {
      return <div className="text-xs text-slate-500">Métriques indisponibles</div>;
    }
    return (
      <div className="grid grid-cols-3 gap-2">
        <MetricPill
          label="Indexeurs"
          value={`${data.indexers_enabled ?? 0}/${data.indexers_total ?? 0}`}
        />
        <MetricPill label="Requêtes" value={data.queries ?? 0} />
        <MetricPill label="Grabs" value={data.grabs ?? 0} highlight />
      </div>
    );
  }

  return null;
}

interface ServiceCardProps {
  service: ServiceItem;
  widgets: WidgetsMap;
}

export function ServiceCard({ service, widgets }: ServiceCardProps) {
  const Icon = ICONS[service.icon] || Server;

  return (
    <a
      href={service.url}
      target="_blank"
      rel="noopener noreferrer"
      className="group flex flex-col justify-between rounded-2xl border border-slate-800/80 bg-slate-900/65 p-4 backdrop-blur transition duration-200 hover:-translate-y-0.5 hover:border-cyan-500/40 hover:bg-slate-900"
    >
      <div>
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-slate-700/80 bg-slate-800/80 text-cyan-400 transition group-hover:border-cyan-500/40 group-hover:bg-cyan-500/10">
              <Icon className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-1.5">
                <h3 className="text-sm font-semibold text-slate-100 group-hover:text-cyan-300">
                  {service.name}
                </h3>
                <ExternalLink className="h-3 w-3 text-slate-500 opacity-0 transition group-hover:opacity-100" />
              </div>
              <p className="text-xs text-slate-400">{service.description}</p>
            </div>
          </div>

          <span
            className={`inline-flex shrink-0 items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-medium ${
              service.online
                ? 'border border-emerald-500/25 bg-emerald-500/10 text-emerald-300'
                : 'border border-rose-500/25 bg-rose-500/10 text-rose-300'
            }`}
          >
            <span
              className={`h-1.5 w-1.5 rounded-full ${
                service.online ? 'bg-emerald-400' : 'bg-rose-400'
              }`}
            />
            {service.online
              ? service.latency_ms !== null
                ? `${service.latency_ms} ms`
                : 'OK'
              : 'Hors ligne'}
          </span>
        </div>
      </div>

      {service.widget && (
        <div className="mt-3.5 border-t border-slate-800/80 pt-3">
          {renderWidget(service.widget, widgets)}
        </div>
      )}
    </a>
  );
}

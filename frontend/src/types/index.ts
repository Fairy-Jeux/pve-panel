export interface AuthUser {
  login: string;
  name: string;
  profile_pic: string;
  auth_mode: 'tailscale_serve' | 'dev_bypass' | string;
}

export interface StorageInfo {
  name: string;
  type: string;
  active: boolean;
  used_bytes: number;
  total_bytes: number;
  used_pct: number;
}

export interface NodeSummary {
  name: string;
  cpu_pct: number;
  cpu_model: string;
  cpu_threads: number;
  loadavg: string[];
  mem_used_bytes: number;
  mem_total_bytes: number;
  mem_pct: number;
  swap_used_bytes: number;
  swap_total_bytes: number;
  rootfs_used_bytes: number;
  rootfs_total_bytes: number;
  uptime_seconds: number;
  uptime_human: string;
  pve_version: string;
  storages: StorageInfo[];
}

export interface PveResource {
  vmid: number;
  name: string;
  type: 'lxc' | 'qemu';
  status: string;
  cpu_pct: number;
  cpus: number;
  mem_used_bytes: number;
  mem_total_bytes: number;
  mem_pct: number;
  disk_used_bytes: number;
  disk_total_bytes: number;
  uptime_seconds: number;
  uptime_human: string;
  tags: string[];
  is_self: boolean;
}

export interface MergerfsPoolInfo {
  name: string;
  mount: string;
  fstype: string;
  policy: string;
  drives_count: number;
  available: boolean;
  total_bytes: number;
  used_bytes: number;
  avail_bytes: number;
  used_pct: number;
}

export interface PhysicalDriveInfo {
  mount: string;
  label: string;
  wwn: string;
  devpath: string;
  model: string;
  vendor: string;
  serial: string;
  type: string;
  rpm: string;
  health: string;
  size_bytes: number;
  total_bytes: number;
  used_bytes: number;
  avail_bytes: number;
  used_pct: number;
}

export interface SystemSsdInfo {
  devpath: string;
  model: string;
  serial: string;
  health: string;
  size_bytes: number;
}

export interface ExternalStorageOverview {
  pool: MergerfsPoolInfo;
  drives: PhysicalDriveInfo[];
  system_ssd: SystemSsdInfo | null;
}

export interface PveOverview {
  online: boolean;
  node: NodeSummary;
  counts: {
    total: number;
    running: number;
    stopped: number;
    lxc: number;
    qemu: number;
  };
  resources: PveResource[];
  external_storage?: ExternalStorageOverview;
}

export type PveAction = 'start' | 'shutdown' | 'reboot' | 'stop';

export interface ServiceItem {
  id: string;
  name: string;
  description: string;
  url: string;
  ping_url?: string;
  icon: string;
  widget?: string;
  online: boolean;
  latency_ms: number | null;
  status_code: number | null;
}

export interface ServiceCategory {
  name: string;
  services: ServiceItem[];
}

export interface JellyfinStream {
  user: string;
  title: string;
  device: string;
  play_method: string;
  is_paused: boolean;
}

export interface JellyfinWidget {
  status: string;
  active_streams_count?: number;
  active_streams?: JellyfinStream[];
  movies_count?: number;
  series_count?: number;
  episodes_count?: number;
}

export interface PlexWidget {
  status: string;
  active_streams_count?: number;
  libraries_count?: number;
  libraries?: string[];
  version?: string;
}

export interface UpcomingItem {
  title: string;
  date: string;
}

export interface RadarrWidget {
  status: string;
  movies_total?: number;
  movies_downloaded?: number;
  movies_missing?: number;
  queue_count?: number;
  upcoming?: UpcomingItem[];
}

export interface SonarrWidget {
  status: string;
  series_total?: number;
  episodes_downloaded?: number;
  queue_count?: number;
  upcoming?: UpcomingItem[];
}

export interface ProwlarrWidget {
  status: string;
  indexers_enabled?: number;
  indexers_total?: number;
  queries?: number;
  grabs?: number;
}

export interface QbittorrentWidget {
  status: string;
  dl_speed_bytes?: number;
  up_speed_bytes?: number;
  dl_total_bytes?: number;
  up_total_bytes?: number;
  downloading_count?: number;
  seeding_count?: number;
  torrents_total?: number;
}

export interface WidgetsMap {
  jellyfin?: JellyfinWidget;
  plex?: PlexWidget;
  radarr?: RadarrWidget;
  sonarr?: SonarrWidget;
  prowlarr?: ProwlarrWidget;
  qbittorrent?: QbittorrentWidget;
  [key: string]: unknown;
}

export interface JellyfinLibrary {
  id: string;
  name: string;
}

export interface UnifiedUser {
  jellyfin_id: string;
  name: string;
  is_admin: boolean;
  is_protected?: boolean;
  is_disabled: boolean;
  enable_all_folders: boolean;
  enabled_folders: string[];
  enable_downloading: boolean;
  max_active_sessions: number;
  last_activity: string | null;
  in_jellyseerr: boolean;
  jellyseerr_id: number | null;
  request_count: number;
  auto_approve: boolean;
}

export interface UsersOverview {
  counts: {
    total_jellyfin: number;
    synced_jellyseerr: number;
    unsynced_count: number;
    disabled_count: number;
  };
  libraries: JellyfinLibrary[];
  users: UnifiedUser[];
}

export interface PveTaskItem {
  upid: string;
  type: string;
  vmid: string;
  user: string;
  status: string;
  starttime: number;
  endtime: number;
  duration_sec: number | null;
}

export interface SeerrRequestItem {
  id: number;
  status: number;
  media_type: string;
  title: string;
  requested_by: string;
  created_at: string;
  media_status: number;
}

export interface QbitTorrentItem {
  hash: string;
  name: string;
  state: string;
  progress_pct: number;
  dlspeed: number;
  upspeed: number;
  size: number;
  eta: number;
}

export interface OpsOverview {
  pve_tasks: PveTaskItem[];
  seerr_requests: SeerrRequestItem[];
  qbit_control: {
    available: boolean;
    alt_speed_enabled: boolean;
    torrents: QbitTorrentItem[];
  };
}

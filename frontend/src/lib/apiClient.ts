import type {
  AuthUser,
  OpsOverview,
  PveOverview,
  PveResource,
  PveTaskItem,
  QbitTorrentItem,
  SeerrRequestItem,
  ServiceCategory,
  UnifiedUser,
  UsersOverview,
  WidgetsMap,
} from '../types';

const STORAGE_SERVER_URL = 'pve_panel_server_url';
const STORAGE_DEMO_MODE = 'pve_panel_demo_mode';

let interceptorInstalled = false;
let nativeFetchRef: typeof window.fetch | null = null;

interface CapacitorGlobal {
  isNativePlatform?: () => boolean;
}

export function isNativePlatform(): boolean {
  if (typeof window === 'undefined') return false;
  const cap = (window as unknown as { Capacitor?: CapacitorGlobal }).Capacitor;
  return Boolean(cap?.isNativePlatform?.());
}

export function normalizeServerUrl(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) return '';
  let candidate = trimmed;
  if (!/^https?:\/\//i.test(candidate)) {
    candidate = `https://${candidate}`;
  }
  return candidate.replace(/\/+$/, '');
}

export function getServerUrl(): string {
  if (typeof window === 'undefined') return '';
  return normalizeServerUrl(window.localStorage.getItem(STORAGE_SERVER_URL) || '');
}

export function setServerUrl(url: string): void {
  if (typeof window === 'undefined') return;
  const normalized = normalizeServerUrl(url);
  if (normalized) {
    window.localStorage.setItem(STORAGE_SERVER_URL, normalized);
  } else {
    window.localStorage.removeItem(STORAGE_SERVER_URL);
  }
}

export function isDemoMode(): boolean {
  if (typeof window === 'undefined') return false;
  return window.localStorage.getItem(STORAGE_DEMO_MODE) === 'true';
}

export function setDemoMode(enabled: boolean): void {
  if (typeof window === 'undefined') return;
  if (enabled) {
    window.localStorage.setItem(STORAGE_DEMO_MODE, 'true');
  } else {
    window.localStorage.removeItem(STORAGE_DEMO_MODE);
  }
}

interface DemoState {
  resources: PveResource[];
  pveTasks: PveTaskItem[];
  seerrRequests: SeerrRequestItem[];
  qbitAltSpeed: boolean;
  qbitTorrents: QbitTorrentItem[];
  users: UnifiedUser[];
}

const GB = 1024 ** 3;
const TB = 1024 ** 4;

function createInitialDemoState(): DemoState {
  const nowSec = Math.floor(Date.now() / 1000);
  return {
    resources: [
      {
        vmid: 101,
        name: 'ct-reverse-proxy',
        type: 'lxc',
        status: 'running',
        cpu_pct: 4.2,
        cpus: 2,
        mem_used_bytes: Math.round(0.42 * GB),
        mem_total_bytes: 2 * GB,
        mem_pct: 21.0,
        disk_used_bytes: Math.round(4.2 * GB),
        disk_total_bytes: 16 * GB,
        uptime_seconds: 1842300,
        uptime_human: '21j 7h',
        tags: ['network', 'prod'],
        is_self: false,
      },
      {
        vmid: 102,
        name: 'ct-media-server',
        type: 'lxc',
        status: 'running',
        cpu_pct: 31.4,
        cpus: 8,
        mem_used_bytes: Math.round(6.8 * GB),
        mem_total_bytes: 16 * GB,
        mem_pct: 42.5,
        disk_used_bytes: 28 * GB,
        disk_total_bytes: 64 * GB,
        uptime_seconds: 914520,
        uptime_human: '10j 14h',
        tags: ['media', 'gpu'],
        is_self: false,
      },
      {
        vmid: 103,
        name: 'vm-docker-host',
        type: 'qemu',
        status: 'running',
        cpu_pct: 18.6,
        cpus: 6,
        mem_used_bytes: Math.round(11.2 * GB),
        mem_total_bytes: 16 * GB,
        mem_pct: 70.0,
        disk_used_bytes: 54 * GB,
        disk_total_bytes: 120 * GB,
        uptime_seconds: 1408120,
        uptime_human: '16j 7h',
        tags: ['docker', 'prod'],
        is_self: false,
      },
      {
        vmid: 104,
        name: 'ct-backup-node',
        type: 'lxc',
        status: 'stopped',
        cpu_pct: 0,
        cpus: 4,
        mem_used_bytes: 0,
        mem_total_bytes: 4 * GB,
        mem_pct: 0,
        disk_used_bytes: 14 * GB,
        disk_total_bytes: 40 * GB,
        uptime_seconds: 0,
        uptime_human: 'Arrêté',
        tags: ['backup'],
        is_self: false,
      },
      {
        vmid: 116,
        name: 'pve-panel',
        type: 'lxc',
        status: 'running',
        cpu_pct: 1.8,
        cpus: 2,
        mem_used_bytes: Math.round(0.35 * GB),
        mem_total_bytes: 2 * GB,
        mem_pct: 17.5,
        disk_used_bytes: Math.round(2.4 * GB),
        disk_total_bytes: 8 * GB,
        uptime_seconds: 604800,
        uptime_human: '7j 0h',
        tags: ['panel', 'tailscale'],
        is_self: true,
      },
    ],
    pveTasks: [
      {
        upid: 'UPID:pve-node-01:demo-vzdump-102',
        type: 'vzdump',
        vmid: '102',
        user: 'root@pam',
        status: 'OK',
        starttime: nowSec - 3200,
        endtime: nowSec - 2810,
        duration_sec: 390,
      },
      {
        upid: 'UPID:pve-node-01:demo-aptupdate',
        type: 'aptupdate',
        vmid: '',
        user: 'root@pam',
        status: 'OK',
        starttime: nowSec - 14400,
        endtime: nowSec - 14350,
        duration_sec: 50,
      },
      {
        upid: 'UPID:pve-node-01:demo-vzstart-101',
        type: 'vzstart',
        vmid: '101',
        user: 'root@pam',
        status: 'OK',
        starttime: nowSec - 86400,
        endtime: nowSec - 86392,
        duration_sec: 8,
      },
    ],
    seerrRequests: [
      {
        id: 401,
        status: 1,
        media_type: 'movie',
        title: 'Dune : Deuxième Partie (2024)',
        requested_by: 'Alex',
        created_at: new Date(Date.now() - 25 * 60_000).toISOString(),
        media_status: 2,
      },
      {
        id: 402,
        status: 2,
        media_type: 'tv',
        title: 'Severance - Saison 2',
        requested_by: 'Camille',
        created_at: new Date(Date.now() - 5 * 3600_000).toISOString(),
        media_status: 4,
      },
    ],
    qbitAltSpeed: false,
    qbitTorrents: [
      {
        hash: 'demo-hash-ubuntu-2404',
        name: 'ubuntu-24.04.2-live-server-amd64.iso',
        state: 'downloading',
        progress_pct: 74.2,
        dlspeed: 24_800_000,
        upspeed: 3_100_000,
        size: Math.round(2.9 * GB),
        eta: 32,
      },
      {
        hash: 'demo-hash-debian-12',
        name: 'debian-12.9.0-amd64-netinst.iso',
        state: 'uploading',
        progress_pct: 100,
        dlspeed: 0,
        upspeed: 5_400_000,
        size: Math.round(0.68 * GB),
        eta: 8640000,
      },
    ],
    users: [
      {
        jellyfin_id: 'demo-admin-01',
        name: 'Admin Démo',
        is_admin: true,
        is_protected: true,
        is_disabled: false,
        enable_all_folders: true,
        enabled_folders: [],
        enable_downloading: true,
        max_active_sessions: 0,
        last_activity: new Date(Date.now() - 120_000).toISOString(),
        in_jellyseerr: true,
        jellyseerr_id: 1,
        request_count: 14,
        auto_approve: true,
      },
      {
        jellyfin_id: 'demo-guest-02',
        name: 'Alex',
        is_admin: false,
        is_protected: false,
        is_disabled: false,
        enable_all_folders: false,
        enabled_folders: ['lib-movies', 'lib-series'],
        enable_downloading: true,
        max_active_sessions: 2,
        last_activity: new Date(Date.now() - 3 * 3600_000).toISOString(),
        in_jellyseerr: true,
        jellyseerr_id: 2,
        request_count: 6,
        auto_approve: true,
      },
      {
        jellyfin_id: 'demo-guest-03',
        name: 'Camille',
        is_admin: false,
        is_protected: false,
        is_disabled: false,
        enable_all_folders: true,
        enabled_folders: [],
        enable_downloading: false,
        max_active_sessions: 2,
        last_activity: new Date(Date.now() - 26 * 3600_000).toISOString(),
        in_jellyseerr: false,
        jellyseerr_id: null,
        request_count: 0,
        auto_approve: false,
      },
    ],
  };
}

let demoState: DemoState = createInitialDemoState();

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleDemoRequest(apiPath: string, init?: RequestInit): Promise<Response> {
  await new Promise((resolve) => setTimeout(resolve, 60));

  const url = new URL(apiPath, 'https://demo.local');
  const path = url.pathname;
  const method = (init?.method || 'GET').toUpperCase();
  let body: Record<string, unknown> = {};
  if (typeof init?.body === 'string' && init.body.trim()) {
    try {
      body = JSON.parse(init.body) as Record<string, unknown>;
    } catch {
      body = {};
    }
  }

  if (path === '/api/me' && method === 'GET') {
    const me: AuthUser = {
      login: 'demo@pve-center.app',
      name: 'Mode Démo App Store',
      profile_pic: '',
      auth_mode: 'demo',
    };
    return jsonResponse(me);
  }

  if (path === '/api/pve/overview' && method === 'GET') {
    const running = demoState.resources.filter((r) => r.status === 'running').length;
    const stopped = demoState.resources.length - running;
    const lxcCount = demoState.resources.filter((r) => r.type === 'lxc').length;
    const qemuCount = demoState.resources.filter((r) => r.type === 'qemu').length;

    const overview: PveOverview = {
      online: true,
      node: {
        name: 'pve-node-01',
        cpu_pct: 23.8,
        cpu_model: 'AMD EPYC / Ryzen Pro Virtualization Host',
        cpu_threads: 16,
        loadavg: ['1.18', '1.05', '0.94'],
        mem_used_bytes: Math.round(28.4 * GB),
        mem_total_bytes: 64 * GB,
        mem_pct: 44.4,
        swap_used_bytes: Math.round(0.4 * GB),
        swap_total_bytes: 8 * GB,
        rootfs_used_bytes: Math.round(42.6 * GB),
        rootfs_total_bytes: 120 * GB,
        uptime_seconds: 1842310,
        uptime_human: '21j 7h 45m',
        pve_version: '8.3.2',
        storages: [
          {
            name: 'local-lvm',
            type: 'lvmthin',
            active: true,
            used_bytes: 412 * GB,
            total_bytes: 1000 * GB,
            used_pct: 41.2,
          },
          {
            name: 'local',
            type: 'dir',
            active: true,
            used_bytes: 88 * GB,
            total_bytes: 240 * GB,
            used_pct: 36.7,
          },
        ],
      },
      counts: {
        total: demoState.resources.length,
        running,
        stopped,
        lxc: lxcCount,
        qemu: qemuCount,
      },
      resources: demoState.resources,
      external_storage: {
        pool: {
          name: 'Pool MergerFS (32 To)',
          mount: '/mnt/storage',
          fstype: 'fuse.mergerfs',
          policy: 'mfs (most free space)',
          drives_count: 3,
          available: true,
          total_bytes: 32 * TB,
          used_bytes: Math.round(19.6 * TB),
          avail_bytes: Math.round(12.4 * TB),
          used_pct: 61.3,
        },
        drives: [
          {
            mount: '/mnt/disk1',
            label: 'Disque 1 • 16 To',
            wwn: 'wwn-0x5000demo00000001',
            devpath: '/dev/sda',
            model: 'Seagate IronWolf Pro 16TB',
            vendor: 'ATA',
            serial: 'DEMO-16TB-01',
            type: 'HDD',
            rpm: '7200 rpm',
            health: 'PASSED',
            size_bytes: 16 * TB,
            total_bytes: 16 * TB,
            used_bytes: Math.round(10.1 * TB),
            avail_bytes: Math.round(5.9 * TB),
            used_pct: 63.1,
          },
          {
            mount: '/mnt/disk2',
            label: 'Disque 2 • 16 To',
            wwn: 'wwn-0x5000demo00000002',
            devpath: '/dev/sdb',
            model: 'Seagate IronWolf Pro 16TB',
            vendor: 'ATA',
            serial: 'DEMO-16TB-02',
            type: 'HDD',
            rpm: '7200 rpm',
            health: 'PASSED',
            size_bytes: 16 * TB,
            total_bytes: 16 * TB,
            used_bytes: Math.round(9.5 * TB),
            avail_bytes: Math.round(6.5 * TB),
            used_pct: 59.4,
          },
          {
            mount: '/mnt/disk3',
            label: 'Cache NVMe • 2 To',
            wwn: 'wwn-0x5000demo00000003',
            devpath: '/dev/nvme0n1',
            model: 'Samsung 990 PRO 2TB',
            vendor: 'NVMe',
            serial: 'DEMO-NVME-01',
            type: 'SSD',
            rpm: 'NVMe',
            health: 'PASSED',
            size_bytes: 2 * TB,
            total_bytes: 2 * TB,
            used_bytes: Math.round(0.84 * TB),
            avail_bytes: Math.round(1.16 * TB),
            used_pct: 42.0,
          },
        ],
        system_ssd: {
          devpath: '/dev/nvme1n1',
          model: 'Enterprise Boot NVMe 512GB',
          serial: 'DEMO-SYS-01',
          health: 'PASSED',
          size_bytes: 512 * GB,
        },
      },
    };
    return jsonResponse(overview);
  }

  const pveMatch = path.match(/^\/api\/pve\/(lxc|qemu)\/(\d+)\/(start|stop|shutdown|reboot)$/);
  if (pveMatch && method === 'POST') {
    const [, type, vmidStr, action] = pveMatch;
    const vmid = Number(vmidStr);
    const target = demoState.resources.find((r) => r.vmid === vmid && r.type === type);
    if (!target) {
      return jsonResponse({ detail: 'Ressource introuvable en mode démo' }, 404);
    }
    if (action === 'stop' || action === 'shutdown') {
      target.status = 'stopped';
      target.cpu_pct = 0;
      target.mem_used_bytes = 0;
      target.mem_pct = 0;
      target.uptime_seconds = 0;
      target.uptime_human = 'Arrêté';
    } else {
      target.status = 'running';
      target.cpu_pct = 8.4;
      target.mem_used_bytes = Math.round(target.mem_total_bytes * 0.35);
      target.mem_pct = 35.0;
      target.uptime_seconds = 60;
      target.uptime_human = '1m';
    }
    const nowSec = Math.floor(Date.now() / 1000);
    demoState.pveTasks.unshift({
      upid: `UPID:pve-node-01:demo-${action}-${vmid}-${Date.now()}`,
      type: `${type === 'lxc' ? 'vz' : 'qm'}${action}`,
      vmid: String(vmid),
      user: 'demo@pve',
      status: 'OK',
      starttime: nowSec,
      endtime: nowSec + 1,
      duration_sec: 1,
    });
    return jsonResponse({ ok: true, vmid, type, action, upid: 'demo-task-ok' });
  }

  if (path === '/api/services' && method === 'GET') {
    const categories: ServiceCategory[] = [
      {
        name: 'Médias & Streaming',
        services: [
          {
            id: 'jellyfin',
            name: 'Jellyfin',
            description: 'Serveur multimédia 4K HDR & transcodage matériel',
            url: 'https://panel.example.ts.net',
            icon: 'Tv',
            widget: 'jellyfin',
            online: true,
            latency_ms: 8,
            status_code: 200,
          },
          {
            id: 'jellyseerr',
            name: 'Jellyseerr',
            description: 'Portail de demandes de films et séries',
            url: 'https://panel.example.ts.net',
            icon: 'Sparkles',
            online: true,
            latency_ms: 11,
            status_code: 200,
          },
        ],
      },
      {
        name: 'Téléchargements & Automation',
        services: [
          {
            id: 'radarr',
            name: 'Radarr',
            description: 'Gestion automatisée de la vidéothèque Films',
            url: 'https://panel.example.ts.net',
            icon: 'Film',
            widget: 'radarr',
            online: true,
            latency_ms: 12,
            status_code: 200,
          },
          {
            id: 'sonarr',
            name: 'Sonarr',
            description: 'Suivi et téléchargement des séries TV',
            url: 'https://panel.example.ts.net',
            icon: 'Clapperboard',
            widget: 'sonarr',
            online: true,
            latency_ms: 13,
            status_code: 200,
          },
          {
            id: 'prowlarr',
            name: 'Prowlarr',
            description: 'Gestionnaire centralisé d’indexeurs',
            url: 'https://panel.example.ts.net',
            icon: 'Search',
            widget: 'prowlarr',
            online: true,
            latency_ms: 10,
            status_code: 200,
          },
          {
            id: 'qbittorrent',
            name: 'qBittorrent',
            description: 'Client BitTorrent haute vitesse',
            url: 'https://panel.example.ts.net',
            icon: 'Download',
            widget: 'qbittorrent',
            online: true,
            latency_ms: 7,
            status_code: 200,
          },
        ],
      },
      {
        name: 'Infrastructure & Sécurité',
        services: [
          {
            id: 'proxmox',
            name: 'Proxmox VE',
            description: 'Hyperviseur principal KVM / LXC',
            url: 'https://panel.example.ts.net',
            icon: 'Server',
            online: true,
            latency_ms: 3,
            status_code: 200,
          },
          {
            id: 'vaultwarden',
            name: 'Vaultwarden',
            description: 'Coffre-fort de mots de passe chiffré',
            url: 'https://panel.example.ts.net',
            icon: 'Shield',
            online: true,
            latency_ms: 9,
            status_code: 200,
          },
        ],
      },
    ];
    return jsonResponse({ categories });
  }

  if (path === '/api/widgets/all' && method === 'GET') {
    const dlTotal = demoState.qbitTorrents.reduce(
      (sum, t) => sum + (t.state.startsWith('paused') ? 0 : t.dlspeed),
      0
    );
    const upTotal = demoState.qbitTorrents.reduce(
      (sum, t) => sum + (t.state.startsWith('paused') ? 0 : t.upspeed),
      0
    );
    const widgets: WidgetsMap = {
      jellyfin: {
        status: 'ok',
        active_streams_count: 2,
        active_streams: [
          {
            user: 'Alex',
            title: 'Dune : Deuxième Partie',
            device: 'Apple TV 4K',
            play_method: 'DirectPlay',
            is_paused: false,
          },
          {
            user: 'Camille',
            title: 'Severance S02E03',
            device: 'iPhone 16 Pro',
            play_method: 'Transcode',
            is_paused: false,
          },
        ],
        movies_count: 418,
        series_count: 64,
        episodes_count: 1840,
      },
      radarr: {
        status: 'ok',
        movies_total: 418,
        movies_downloaded: 414,
        movies_missing: 4,
        queue_count: 1,
        upcoming: [{ title: 'Mickey 17', date: '2026-11-22' }],
      },
      sonarr: {
        status: 'ok',
        series_total: 64,
        episodes_downloaded: 1840,
        queue_count: 2,
        upcoming: [{ title: 'Severance S02E04', date: '2026-11-20' }],
      },
      prowlarr: {
        status: 'ok',
        indexers_enabled: 8,
        indexers_total: 8,
        queries: 1420,
        grabs: 86,
      },
      qbittorrent: {
        status: 'ok',
        dl_speed_bytes: demoState.qbitAltSpeed ? Math.round(dlTotal * 0.25) : dlTotal,
        up_speed_bytes: demoState.qbitAltSpeed ? Math.round(upTotal * 0.25) : upTotal,
        dl_total_bytes: Math.round(1.8 * TB),
        up_total_bytes: Math.round(6.4 * TB),
        downloading_count: demoState.qbitTorrents.filter((t) => t.state === 'downloading').length,
        seeding_count: demoState.qbitTorrents.filter((t) => t.state === 'uploading').length,
        torrents_total: demoState.qbitTorrents.length,
      },
    };
    return jsonResponse(widgets);
  }

  if (path === '/api/ops/overview' && method === 'GET') {
    const ops: OpsOverview = {
      pve_tasks: demoState.pveTasks.slice(0, 12),
      seerr_requests: demoState.seerrRequests,
      qbit_control: {
        available: true,
        alt_speed_enabled: demoState.qbitAltSpeed,
        torrents: demoState.qbitTorrents,
      },
    };
    return jsonResponse(ops);
  }

  const seerrMatch = path.match(/^\/api\/ops\/seerr\/(\d+)\/(approve|decline)$/);
  if (seerrMatch && method === 'POST') {
    const [, idStr, action] = seerrMatch;
    const reqItem = demoState.seerrRequests.find((r) => r.id === Number(idStr));
    if (!reqItem) return jsonResponse({ detail: 'Demande introuvable' }, 404);
    reqItem.status = action === 'approve' ? 2 : 3;
    return jsonResponse({ ok: true, id: reqItem.id, action });
  }

  if (path === '/api/ops/qbit/toggle-speed-mode' && method === 'POST') {
    demoState.qbitAltSpeed = !demoState.qbitAltSpeed;
    return jsonResponse({ ok: true, alt_speed_enabled: demoState.qbitAltSpeed });
  }

  const torrentMatch = path.match(/^\/api\/ops\/qbit\/torrent\/([^/]+)\/(pause|resume)$/);
  if (torrentMatch && method === 'POST') {
    const [, hash, action] = torrentMatch;
    const torrent = demoState.qbitTorrents.find((t) => t.hash === hash);
    if (!torrent) return jsonResponse({ detail: 'Torrent introuvable' }, 404);
    if (action === 'pause') {
      torrent.state = torrent.progress_pct >= 100 ? 'pausedUP' : 'pausedDL';
    } else {
      torrent.state = torrent.progress_pct >= 100 ? 'uploading' : 'downloading';
    }
    return jsonResponse({ ok: true, hash, action });
  }

  const scanMatch = path.match(/^\/api\/ops\/media\/scan\/(jellyfin|plex)$/);
  if (scanMatch && method === 'POST') {
    return jsonResponse({ ok: true, service: scanMatch[1], message: 'Scan démarré (Démo)' });
  }

  if (path === '/api/users' && method === 'GET') {
    const total = demoState.users.length;
    const synced = demoState.users.filter((u) => u.in_jellyseerr).length;
    const disabled = demoState.users.filter((u) => u.is_disabled).length;
    const overview: UsersOverview = {
      counts: {
        total_jellyfin: total,
        synced_jellyseerr: synced,
        unsynced_count: total - synced,
        disabled_count: disabled,
      },
      libraries: [
        { id: 'lib-movies', name: 'Films 4K & HD' },
        { id: 'lib-series', name: 'Séries TV' },
        { id: 'lib-anime', name: 'Animation' },
      ],
      users: demoState.users,
    };
    return jsonResponse(overview);
  }

  if (path === '/api/users' && method === 'POST') {
    const username = String(body.username || '').trim();
    if (!username) return jsonResponse({ detail: 'Nom d’utilisateur requis' }, 400);
    const created: UnifiedUser = {
      jellyfin_id: `demo-user-${Date.now()}`,
      name: username,
      is_admin: Boolean(body.is_admin),
      is_protected: false,
      is_disabled: false,
      enable_all_folders: Boolean(body.enable_all_folders ?? true),
      enabled_folders: Array.isArray(body.enabled_folders) ? (body.enabled_folders as string[]) : [],
      enable_downloading: Boolean(body.enable_downloading ?? true),
      max_active_sessions: typeof body.max_active_sessions === 'number' ? body.max_active_sessions : 2,
      last_activity: null,
      in_jellyseerr: Boolean(body.sync_jellyseerr ?? true),
      jellyseerr_id: body.sync_jellyseerr ? demoState.users.length + 10 : null,
      request_count: 0,
      auto_approve: Boolean(body.auto_approve ?? true),
    };
    demoState.users.push(created);
    return jsonResponse({
      ok: true,
      user: created,
      jellyfin: { ok: true },
      jellyseerr: { ok: true, status: created.in_jellyseerr ? 'created' : 'skipped' },
    });
  }

  if (path === '/api/users/sync' && method === 'POST') {
    demoState.users = demoState.users.map((u, idx) => ({
      ...u,
      in_jellyseerr: true,
      jellyseerr_id: u.jellyseerr_id ?? idx + 10,
      auto_approve: true,
    }));
    return jsonResponse({ ok: true, imported_count: demoState.users.length });
  }

  const userPatchMatch = path.match(/^\/api\/users\/([^/]+)$/);
  if (userPatchMatch && method === 'PATCH') {
    const user = demoState.users.find((u) => u.jellyfin_id === userPatchMatch[1]);
    if (!user) return jsonResponse({ detail: 'Utilisateur introuvable' }, 404);
    if (user.is_protected) return jsonResponse({ detail: 'Compte administrateur protégé' }, 403);
    if (typeof body.is_disabled === 'boolean') user.is_disabled = body.is_disabled;
    if (typeof body.is_admin === 'boolean') user.is_admin = body.is_admin;
    if (typeof body.enable_all_folders === 'boolean') user.enable_all_folders = body.enable_all_folders;
    if (Array.isArray(body.enabled_folders)) user.enabled_folders = body.enabled_folders as string[];
    if (typeof body.enable_downloading === 'boolean') user.enable_downloading = body.enable_downloading;
    if (typeof body.max_active_sessions === 'number') user.max_active_sessions = body.max_active_sessions;
    if (typeof body.auto_approve === 'boolean') user.auto_approve = body.auto_approve;
    return jsonResponse({ ok: true, user });
  }

  const userPassMatch = path.match(/^\/api\/users\/([^/]+)\/password$/);
  if (userPassMatch && method === 'POST') {
    return jsonResponse({ ok: true });
  }

  if (userPatchMatch && method === 'DELETE') {
    const user = demoState.users.find((u) => u.jellyfin_id === userPatchMatch[1]);
    if (!user) return jsonResponse({ detail: 'Utilisateur introuvable' }, 404);
    if (user.is_protected) return jsonResponse({ detail: 'Compte administrateur protégé' }, 403);
    demoState.users = demoState.users.filter((u) => u.jellyfin_id !== user.jellyfin_id);
    return jsonResponse({ ok: true });
  }

  return jsonResponse({ detail: `Endpoint démo non simulé: ${method} ${path}` }, 404);
}

function extractApiPath(input: RequestInfo | URL): string | null {
  const raw =
    typeof input === 'string'
      ? input
      : input instanceof URL
        ? input.toString()
        : input.url;

  if (raw.startsWith('/api/')) {
    return raw;
  }

  if (typeof window !== 'undefined' && raw.startsWith(window.location.origin + '/api/')) {
    return raw.slice(window.location.origin.length);
  }

  return null;
}

export function installApiInterceptor(): void {
  if (typeof window === 'undefined' || interceptorInstalled) return;
  interceptorInstalled = true;
  nativeFetchRef = window.fetch.bind(window);

  window.fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const apiPath = extractApiPath(input);
    const nativeFetch = nativeFetchRef!;

    if (!apiPath) {
      return nativeFetch(input, init);
    }

    if (isDemoMode()) {
      return handleDemoRequest(apiPath, init);
    }

    const remoteBase = getServerUrl();
    if (remoteBase) {
      const targetUrl = `${remoteBase}${apiPath}`;
      const nextInit: RequestInit = {
        ...init,
        credentials: init?.credentials ?? 'include',
      };
      return nativeFetch(targetUrl, nextInit);
    }

    return nativeFetch(input, init);
  };
}

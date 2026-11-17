import { useCallback, useEffect, useState } from 'react';
import {
  AlertCircle,
  ArrowLeft,
  ArrowRight,
  BellRing,
  Check,
  CheckCircle2,
  Copy,
  KeyRound,
  Loader2,
  Plus,
  Radar,
  Rocket,
  Server,
  ShieldCheck,
  Sparkles,
  Trash2,
  Wifi,
  X,
} from 'lucide-react';
import { setAuthToken } from '../lib/apiClient';
import { QrCodeView } from './NotificationsModal';
import type {
  CustomServicePayload,
  CustomServiceTestResponse,
  DiscoveryLanResponse,
  DiscoveryQrResponse,
  LanDiscoveredService,
  OnboardingInitResponse,
  ServiceProtocol,
  WebhookChannelType,
} from '../types';

interface OnboardingModalProps {
  open: boolean;
  onClose: () => void;
  onCompleted: (message: string) => void;
}

interface HomelabTemplate {
  id: string;
  name: string;
  description: string;
  category: string;
  icon: string;
  protocol: ServiceProtocol;
  url: string;
  health_url: string;
  host: string;
  port: number | null;
  json_metric_path?: string;
}

const HOMELAB_TEMPLATES: HomelabTemplate[] = [
  {
    id: 'jellyfin',
    name: 'Jellyfin',
    description: 'Serveur multimédia 4K & streaming',
    category: 'Médias & Streaming',
    icon: 'Tv',
    protocol: 'http_rest',
    url: 'http://192.168.1.26:8096',
    health_url: 'http://192.168.1.26:8096/health',
    host: '192.168.1.26',
    port: 8096,
  },
  {
    id: 'home-assistant',
    name: 'Home Assistant',
    description: 'Domotique & capteurs maison',
    category: 'Domotique',
    icon: 'Activity',
    protocol: 'http_rest',
    url: 'http://192.168.1.40:8123',
    health_url: 'http://192.168.1.40:8123',
    host: '192.168.1.40',
    port: 8123,
  },
  {
    id: 'adguard-home',
    name: 'AdGuard Home',
    description: 'Filtrage DNS & métriques réseau',
    category: 'Infrastructure & Sécurité',
    icon: 'Shield',
    protocol: 'json_metrics',
    url: 'http://192.168.1.5:3000',
    health_url: 'http://192.168.1.5:3000/control/stats',
    host: '192.168.1.5',
    port: 3000,
    json_metric_path: 'num_dns_queries, num_blocked_filtering',
  },
  {
    id: 'postgres-db',
    name: 'PostgreSQL',
    description: 'Sonde TCP port 5432',
    category: 'Infrastructure & Sécurité',
    icon: 'Database',
    protocol: 'tcp_port',
    url: '',
    health_url: '',
    host: '192.168.1.20',
    port: 5432,
  },
  {
    id: 'backup-heartbeat',
    name: 'Agent Backup Webhook',
    description: 'Heartbeat push nightly Restic / Borg',
    category: 'Services Personnalisés',
    icon: 'Activity',
    protocol: 'webhook_ingest',
    url: '',
    health_url: '',
    host: '',
    port: null,
  },
];

export function OnboardingModal({
  open,
  onClose,
  onCompleted,
}: OnboardingModalProps) {
  const [step, setStep] = useState<1 | 2 | 3 | 4>(1);

  // Step 1: Server Identity & Network
  const [serverName, setServerName] = useState('PVE Command Center');
  const [publicUrl, setPublicUrl] = useState('');
  const [listenHost, setListenHost] = useState('0.0.0.0');
  const [listenPort, setListenPort] = useState('8000');
  const [mdnsEnabled, setMdnsEnabled] = useState(true);
  const [qrPreview, setQrPreview] = useState<DiscoveryQrResponse | null>(null);

  // Step 2: Admin Security
  const [tailscaleSsoEnabled, setTailscaleSsoEnabled] = useState(true);
  const [allowedTailscaleUsers, setAllowedTailscaleUsers] = useState('');
  const [adminPin, setAdminPin] = useState('');
  const [tokenName, setTokenName] = useState('Initial Admin Token');
  const [devAuthBypass, setDevAuthBypass] = useState(false);

  // Step 3: Services & Alerts
  const [scanningLan, setScanningLan] = useState(false);
  const [discovered, setDiscovered] = useState<LanDiscoveredService[]>([]);
  const [selectedServices, setSelectedServices] = useState<CustomServicePayload[]>([]);
  const [testingIndex, setTestingIndex] = useState<number | null>(null);
  const [testResults, setTestResults] = useState<Record<number, CustomServiceTestResponse>>({});
  const [alertsEnabled, setAlertsEnabled] = useState(true);
  const [webhookEnabled, setWebhookEnabled] = useState(false);
  const [webhookType, setWebhookType] = useState<WebhookChannelType>('discord');
  const [webhookName, setWebhookName] = useState('Alertes Homelab');
  const [webhookUrl, setWebhookUrl] = useState('');
  const [webhookChatId, setWebhookChatId] = useState('');
  const [webhookBotToken, setWebhookBotToken] = useState('');

  // Step 4: Submit & Token Reveal
  const [submitting, setSubmitting] = useState(false);
  const [initResult, setInitResult] = useState<OnboardingInitResponse | null>(null);
  const [saveTokenLocally, setSaveTokenLocally] = useState(true);
  const [copiedToken, setCopiedToken] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const loadQrPreview = useCallback(async () => {
    try {
      const resp = await fetch('/api/discovery/qr');
      if (resp.ok) {
        const data = (await resp.json()) as DiscoveryQrResponse;
        setQrPreview(data);
        setPublicUrl((prev) => prev || data.public_url || '');
        setServerName((prev) => prev || data.server_name || 'PVE Command Center');
      }
    } catch {
      // Ignore preview fetch failure before server config
    }
  }, []);

  useEffect(() => {
    if (open) {
      setStep(1);
      setInitResult(null);
      setErrorMsg(null);
      setTestResults({});
      void loadQrPreview();
    }
  }, [open, loadQrPreview]);

  if (!open) return null;

  const effectivePublicUrl =
    publicUrl.trim() ||
    qrPreview?.public_url ||
    (typeof window !== 'undefined' ? window.location.origin : 'http://localhost:8000');

  const liveDeepLink = `pvecenter://connect?url=${encodeURIComponent(
    effectivePublicUrl
  )}&name=${encodeURIComponent(serverName.trim() || 'PVE Command Center')}${
    qrPreview?.server_id ? `&id=${encodeURIComponent(qrPreview.server_id)}` : ''
  }`;

  const handleScanLan = async () => {
    setScanningLan(true);
    setErrorMsg(null);
    try {
      const resp = await fetch('/api/discovery/lan?timeout=2.0');
      const data = (await resp.json().catch(() => ({}))) as DiscoveryLanResponse & {
        detail?: string;
      };
      if (!resp.ok) throw new Error(data.detail || `HTTP ${resp.status}`);
      setDiscovered(data.services || []);
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Échec du scan mDNS LAN.');
    } finally {
      setScanningLan(false);
    }
  };

  const addDiscoveredService = (item: LanDiscoveredService) => {
    const scheme = item.port === 443 || item.port === 8006 ? 'https' : 'http';
    const baseUrl = `${scheme}://${item.host}:${item.port}`;
    setSelectedServices((prev) => {
      if (prev.some((s) => s.name === item.name)) return prev;
      return [
        ...prev,
        {
          name: item.name,
          description: `Découvert via mDNS (${item.service_type})`,
          category: 'Services Découverts',
          icon: 'Globe',
          protocol: item.suggested_protocol || 'http_rest',
          host: item.host,
          port: item.port,
          url: baseUrl,
          health_url: baseUrl,
          enabled: true,
        },
      ];
    });
  };

  const addTemplateService = (tpl: HomelabTemplate) => {
    setSelectedServices((prev) => {
      if (prev.some((s) => s.id === tpl.id || s.name === tpl.name)) return prev;
      return [
        ...prev,
        {
          id: tpl.id,
          name: tpl.name,
          description: tpl.description,
          category: tpl.category,
          icon: tpl.icon,
          protocol: tpl.protocol,
          host: tpl.host,
          port: tpl.port,
          url: tpl.url,
          health_url: tpl.health_url,
          json_metric_path: tpl.json_metric_path || '',
          enabled: true,
        },
      ];
    });
  };

  const handleTestServiceAt = async (idx: number) => {
    const svc = selectedServices[idx];
    if (!svc) return;
    setTestingIndex(idx);
    try {
      const resp = await fetch(`/api/custom-services/${encodeURIComponent(svc.id || 'dry-run')}/test`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(svc),
      });
      const data = (await resp.json().catch(() => ({}))) as CustomServiceTestResponse;
      setTestResults((prev) => ({ ...prev, [idx]: data }));
    } catch {
      // Ignore inline test error
    } finally {
      setTestingIndex(null);
    }
  };

  const handleInitOnboarding = async () => {
    if (adminPin.trim() && adminPin.trim().length < 4) {
      setErrorMsg('Le code PIN administrateur doit contenir au moins 4 caractères.');
      return;
    }
    setSubmitting(true);
    setErrorMsg(null);
    try {
      const usersList = allowedTailscaleUsers
        .split(',')
        .map((u) => u.trim())
        .filter(Boolean);

      const notificationsPayload =
        webhookEnabled && (webhookUrl.trim() || (webhookType === 'telegram' && webhookBotToken.trim()))
          ? {
              webhooks: [
                {
                  id: `wh-${Date.now()}`,
                  name: webhookName.trim() || 'Alertes Homelab',
                  type: webhookType,
                  enabled: true,
                  url: webhookUrl.trim(),
                  bot_token: webhookBotToken.trim(),
                  chat_id: webhookChatId.trim(),
                  notify_on_down: true,
                  notify_on_recovery: true,
                  include_details: true,
                },
              ],
            }
          : undefined;

      const resp = await fetch('/api/onboarding/init', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          server_name: serverName.trim() || 'PVE Command Center',
          public_url: publicUrl.trim(),
          listen_host: listenHost.trim() || '0.0.0.0',
          listen_port: Number(listenPort) || 8000,
          mdns_enabled: mdnsEnabled,
          tailscale_sso_enabled: tailscaleSsoEnabled,
          allowed_tailscale_users: usersList,
          dev_auth_bypass: devAuthBypass,
          admin_pin: adminPin.trim(),
          token_name: tokenName.trim() || 'Initial Admin Token',
          alerts: { enabled: alertsEnabled },
          notifications: notificationsPayload,
          custom_services: selectedServices.length > 0 ? selectedServices : undefined,
        }),
      });

      const data = (await resp.json().catch(() => ({}))) as OnboardingInitResponse & {
        detail?: string;
      };
      if (!resp.ok || !data.ok) {
        throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      }

      if (saveTokenLocally && data.api_token) {
        setAuthToken(data.api_token);
      }
      setInitResult(data);
    } catch (err) {
      setErrorMsg(
        err instanceof Error ? err.message : 'Échec de l’initialisation de config.yaml.'
      );
    } finally {
      setSubmitting(false);
    }
  };

  const handleCopyToken = async () => {
    if (!initResult?.api_token) return;
    try {
      await navigator.clipboard.writeText(initResult.api_token);
      setCopiedToken(true);
      window.setTimeout(() => setCopiedToken(false), 2000);
    } catch {
      // Ignore clipboard failure
    }
  };

  const steps = [
    { id: 1, title: 'Serveur & Réseau' },
    { id: 2, title: 'Sécurité & Accès' },
    { id: 3, title: 'Services & Alertes' },
    { id: 4, title: 'Validation & Clé' },
  ] as const;

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/65 p-0 backdrop-blur-md sm:items-center sm:p-4"
      onClick={onClose}
    >
      <div
        className="ios-sheet safe-bottom-sheet flex max-h-[94dvh] w-full max-w-3xl flex-col overflow-hidden rounded-t-[32px] text-slate-900 dark:text-slate-100 sm:rounded-3xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="shrink-0 border-b border-slate-200/80 px-5 pb-4 pt-3 dark:border-white/10 sm:px-6 sm:pt-5">
          <div className="mb-3 flex justify-center sm:hidden">
            <div className="ios-grabber" />
          </div>

          <div className="flex items-start justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border border-cyan-500/35 bg-gradient-to-br from-cyan-500/20 to-indigo-500/20 text-cyan-600 dark:text-cyan-300">
                <Rocket className="h-5 w-5" />
              </div>
              <div>
                <h2 className="text-base font-semibold text-slate-900 dark:text-white">
                  Assistant de démarrage PVE Command Center
                </h2>
                <p className="text-xs text-slate-500 dark:text-slate-400">
                  Configuration initiale guidée en 4 étapes &amp; génération sécurisée de <code className="font-mono">config.yaml</code>
                </p>
              </div>
            </div>

            <button
              type="button"
              onClick={onClose}
              aria-label="Fermer"
              className="liquid-pill rounded-full p-2 text-slate-500 hover:text-slate-900 dark:text-slate-300 dark:hover:text-white"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          {/* Stepper */}
          <div className="mt-4 grid grid-cols-4 gap-2">
            {steps.map((s) => {
              const active = step === s.id;
              const done = step > s.id || Boolean(initResult);
              return (
                <button
                  key={s.id}
                  type="button"
                  disabled={Boolean(initResult)}
                  onClick={() => setStep(s.id)}
                  className={`flex items-center gap-2 rounded-2xl border px-2.5 py-2 text-left transition ${
                    active
                      ? 'border-cyan-500/50 bg-cyan-500/15 text-slate-900 dark:text-white'
                      : done
                        ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-800 dark:text-emerald-200'
                        : 'border-slate-200/80 bg-white/50 text-slate-500 dark:border-white/10 dark:bg-white/[0.03] dark:text-slate-400'
                  }`}
                >
                  <span
                    className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[10px] font-bold ${
                      done
                        ? 'bg-emerald-500 text-white'
                        : active
                          ? 'bg-cyan-500 text-white'
                          : 'bg-slate-200 text-slate-600 dark:bg-white/10 dark:text-slate-300'
                    }`}
                  >
                    {done && s.id < step ? <Check className="h-3 w-3" /> : s.id}
                  </span>
                  <span className="hidden truncate text-[11px] font-semibold sm:inline">
                    {s.title}
                  </span>
                </button>
              );
            })}
          </div>
        </div>

        {/* Body */}
        <div className="flex-1 space-y-5 overflow-y-auto p-5 sm:p-6">
          {errorMsg && (
            <div className="flex items-start gap-2 rounded-2xl border border-rose-500/35 bg-rose-500/10 p-3 text-xs text-rose-700 dark:text-rose-200">
              <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{errorMsg}</span>
            </div>
          )}

          {step === 1 && (
            <div className="grid grid-cols-1 gap-5 md:grid-cols-12">
              <div className="space-y-3.5 md:col-span-7">
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-600 dark:text-slate-300">
                    Nom du serveur
                  </label>
                  <input
                    type="text"
                    value={serverName}
                    onChange={(e) => setServerName(e.target.value)}
                    placeholder="PVE Command Center"
                    className="liquid-input"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-600 dark:text-slate-300">
                    URL publique (Tailscale Serve ou LAN)
                  </label>
                  <input
                    type="url"
                    value={publicUrl}
                    onChange={(e) => setPublicUrl(e.target.value)}
                    placeholder="https://pve-panel.example.ts.net"
                    className="liquid-input font-mono text-xs"
                  />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="mb-1 block text-xs font-medium text-slate-600 dark:text-slate-300">
                      Adresse d’écoute
                    </label>
                    <input
                      type="text"
                      value={listenHost}
                      onChange={(e) => setListenHost(e.target.value)}
                      className="liquid-input font-mono text-xs"
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-xs font-medium text-slate-600 dark:text-slate-300">
                      Port HTTP
                    </label>
                    <input
                      type="number"
                      min={1}
                      max={65535}
                      value={listenPort}
                      onChange={(e) => setListenPort(e.target.value)}
                      className="liquid-input font-mono text-xs"
                    />
                  </div>
                </div>

                <label className="liquid-subcard flex cursor-pointer items-center justify-between gap-3 p-3.5">
                  <div className="flex items-center gap-2.5">
                    <Wifi className="h-4 w-4 text-cyan-500" />
                    <div>
                      <div className="text-xs font-semibold text-slate-900 dark:text-white">
                        Découverte Bonjour / mDNS
                      </div>
                      <div className="text-[11px] text-slate-500 dark:text-slate-400">
                        Annonce automatiquement <code className="font-mono">_pvecenter._tcp.local.</code> sur le LAN
                      </div>
                    </div>
                  </div>
                  <input
                    type="checkbox"
                    checked={mdnsEnabled}
                    onChange={(e) => setMdnsEnabled(e.target.checked)}
                    className="h-4 w-4 rounded accent-cyan-500"
                  />
                </label>
              </div>

              <div className="liquid-subcard flex flex-col items-center justify-center p-4 text-center md:col-span-5">
                <QrCodeView value={liveDeepLink} size={156} />
                <div className="mt-2.5 text-xs font-semibold text-slate-900 dark:text-white">
                  Aperçu QR App Apple
                </div>
                <p className="mt-1 text-[11px] text-slate-500 dark:text-slate-400">
                  Scannable depuis l’app iOS / iPadOS pour pré-remplir ce serveur.
                </p>
              </div>
            </div>
          )}

          {step === 2 && (
            <div className="space-y-4">
              <label className="liquid-subcard flex cursor-pointer items-center justify-between gap-3 p-4">
                <div className="flex items-center gap-3">
                  <ShieldCheck className="h-5 w-5 text-emerald-500" />
                  <div>
                    <div className="text-xs font-semibold text-slate-900 dark:text-white">
                      Tailscale Serve SSO (Zéro friction)
                    </div>
                    <div className="text-[11px] text-slate-500 dark:text-slate-400">
                      Fait confiance à l’en-tête <code className="font-mono">Tailscale-User-Login</code> injecté sur loopback
                    </div>
                  </div>
                </div>
                <input
                  type="checkbox"
                  checked={tailscaleSsoEnabled}
                  onChange={(e) => setTailscaleSsoEnabled(e.target.checked)}
                  className="h-4 w-4 rounded accent-cyan-500"
                />
              </label>

              <div>
                <label className="mb-1 block text-xs font-medium text-slate-600 dark:text-slate-300">
                  Utilisateurs Tailscale autorisés (séparés par virgule — vide = tout le tailnet)
                </label>
                <input
                  type="text"
                  value={allowedTailscaleUsers}
                  onChange={(e) => setAllowedTailscaleUsers(e.target.value)}
                  placeholder="admin@example.com, ops@example.com"
                  className="liquid-input"
                />
              </div>

              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-600 dark:text-slate-300">
                    Code PIN Administrateur LAN (optionnel, min 4 car.)
                  </label>
                  <input
                    type="password"
                    value={adminPin}
                    onChange={(e) => setAdminPin(e.target.value)}
                    placeholder="Ex: 4829"
                    className="liquid-input font-mono"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-600 dark:text-slate-300">
                    Nom du 1er jeton API Bearer généré
                  </label>
                  <input
                    type="text"
                    value={tokenName}
                    onChange={(e) => setTokenName(e.target.value)}
                    placeholder="Initial Admin Token"
                    className="liquid-input"
                  />
                </div>
              </div>

              <label className="flex items-center gap-2 text-xs text-slate-500 dark:text-slate-400">
                <input
                  type="checkbox"
                  checked={devAuthBypass}
                  onChange={(e) => setDevAuthBypass(e.target.checked)}
                  className="rounded accent-amber-500"
                />
                Activer <code className="font-mono">dev_auth_bypass</code> (développement local uniquement)
              </label>
            </div>
          )}

          {step === 3 && (
            <div className="space-y-4">
              {/* Scan mDNS + Templates */}
              <div className="liquid-subcard space-y-3 p-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div>
                    <h3 className="flex items-center gap-1.5 text-xs font-semibold text-slate-900 dark:text-white">
                      <Radar className="h-4 w-4 text-cyan-500" />
                      Découverte réseau LAN (mDNS) &amp; Modèles rapides
                    </h3>
                    <p className="text-[11px] text-slate-500 dark:text-slate-400">
                      Ajoutez vos services Homelab en 1 clic et testez-les avant écriture.
                    </p>
                  </div>
                  <button
                    type="button"
                    disabled={scanningLan}
                    onClick={() => void handleScanLan()}
                    className="inline-flex items-center gap-1.5 rounded-full border border-cyan-500/35 bg-cyan-500/15 px-3 py-1.5 text-xs font-semibold text-cyan-800 hover:bg-cyan-500/25 disabled:opacity-50 dark:text-cyan-200"
                  >
                    {scanningLan ? (
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <Radar className="h-3.5 w-3.5" />
                    )}
                    Scanner le LAN
                  </button>
                </div>

                {discovered.length > 0 && (
                  <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                    {discovered.map((d) => (
                      <div
                        key={d.id}
                        className="flex items-center justify-between gap-2 rounded-xl border border-slate-200/80 bg-white/75 px-3 py-2 text-xs dark:border-white/10 dark:bg-white/[0.04]"
                      >
                        <div className="min-w-0">
                          <div className="truncate font-semibold text-slate-900 dark:text-white">
                            {d.name}
                          </div>
                          <div className="truncate font-mono text-[10px] text-slate-500 dark:text-slate-400">
                            {d.host}:{d.port} • {d.suggested_protocol}
                          </div>
                        </div>
                        <button
                          type="button"
                          onClick={() => addDiscoveredService(d)}
                          className="shrink-0 rounded-lg bg-cyan-500/15 px-2 py-1 text-[11px] font-semibold text-cyan-700 hover:bg-cyan-500/25 dark:text-cyan-200"
                        >
                          + Ajouter
                        </button>
                      </div>
                    ))}
                  </div>
                )}

                <div className="flex flex-wrap gap-1.5 pt-1">
                  {HOMELAB_TEMPLATES.map((tpl) => (
                    <button
                      key={tpl.id}
                      type="button"
                      onClick={() => addTemplateService(tpl)}
                      className="liquid-pill inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-medium text-slate-700 hover:text-cyan-700 dark:text-slate-200 dark:hover:text-cyan-200"
                    >
                      <Plus className="h-3 w-3 text-cyan-500" />
                      {tpl.name}
                    </button>
                  ))}
                </div>
              </div>

              {selectedServices.length > 0 && (
                <div className="space-y-2">
                  <div className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                    Services sélectionnés ({selectedServices.length})
                  </div>
                  {selectedServices.map((svc, idx) => {
                    const testRes = testResults[idx];
                    return (
                      <div key={idx} className="liquid-subcard space-y-2 p-3">
                        <div className="flex flex-wrap items-center justify-between gap-2">
                          <div className="flex items-center gap-2">
                            <Server className="h-3.5 w-3.5 text-cyan-500" />
                            <span className="text-xs font-semibold text-slate-900 dark:text-white">
                              {svc.name}
                            </span>
                            <span className="rounded bg-cyan-500/15 px-1.5 py-0.5 font-mono text-[10px] text-cyan-700 dark:text-cyan-300">
                              {svc.protocol}
                            </span>
                          </div>
                          <div className="flex items-center gap-1.5">
                            <button
                              type="button"
                              disabled={testingIndex === idx}
                              onClick={() => void handleTestServiceAt(idx)}
                              className="rounded-lg border border-cyan-500/30 bg-cyan-500/10 px-2 py-1 text-[11px] font-semibold text-cyan-700 dark:text-cyan-200"
                            >
                              {testingIndex === idx ? 'Test…' : 'Tester'}
                            </button>
                            <button
                              type="button"
                              onClick={() =>
                                setSelectedServices((prev) => prev.filter((_, i) => i !== idx))
                              }
                              className="rounded-lg bg-rose-500/10 p-1 text-rose-500"
                            >
                              <Trash2 className="h-3.5 w-3.5" />
                            </button>
                          </div>
                        </div>

                        <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                          <input
                            type="text"
                            value={svc.health_url || svc.url || ''}
                            onChange={(e) =>
                              setSelectedServices((prev) =>
                                prev.map((item, i) =>
                                  i === idx
                                    ? { ...item, url: e.target.value, health_url: e.target.value }
                                    : item
                                )
                              )
                            }
                            placeholder="URL (ex: http://192.168.1.26:8096)"
                            className="liquid-input py-1.5 font-mono text-xs"
                          />
                          <input
                            type="text"
                            value={svc.host || ''}
                            onChange={(e) =>
                              setSelectedServices((prev) =>
                                prev.map((item, i) =>
                                  i === idx ? { ...item, host: e.target.value } : item
                                )
                              )
                            }
                            placeholder="Hôte / IP"
                            className="liquid-input py-1.5 font-mono text-xs"
                          />
                        </div>

                        {testRes && (
                          <div
                            className={`text-[11px] ${
                              testRes.ok
                                ? 'text-emerald-700 dark:text-emerald-300'
                                : 'text-rose-600 dark:text-rose-300'
                            }`}
                          >
                            {testRes.ok ? '✓' : '✕'} {testRes.message}
                            {testRes.latency_ms !== null ? ` (${testRes.latency_ms} ms)` : ''}
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              )}

              {/* Alertes & Webhook rapide */}
              <div className="liquid-subcard space-y-3 p-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <BellRing className="h-4 w-4 text-amber-500" />
                    <span className="text-xs font-semibold text-slate-900 dark:text-white">
                      Moteur d’alertes &amp; Webhook rapide
                    </span>
                  </div>
                  <div className="flex items-center gap-4 text-xs">
                    <label className="inline-flex items-center gap-1.5">
                      <input
                        type="checkbox"
                        checked={alertsEnabled}
                        onChange={(e) => setAlertsEnabled(e.target.checked)}
                        className="rounded accent-cyan-500"
                      />
                      Alertes actives
                    </label>
                    <label className="inline-flex items-center gap-1.5">
                      <input
                        type="checkbox"
                        checked={webhookEnabled}
                        onChange={(e) => setWebhookEnabled(e.target.checked)}
                        className="rounded accent-cyan-500"
                      />
                      Ajouter un webhook
                    </label>
                  </div>
                </div>

                {webhookEnabled && (
                  <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
                    <select
                      value={webhookType}
                      onChange={(e) => setWebhookType(e.target.value as WebhookChannelType)}
                      className="liquid-input text-xs"
                    >
                      <option value="discord">Discord</option>
                      <option value="telegram">Telegram</option>
                      <option value="generic">ntfy / Gotify / Générique</option>
                    </select>
                    <input
                      type="text"
                      value={webhookName}
                      onChange={(e) => setWebhookName(e.target.value)}
                      placeholder="Nom du canal"
                      className="liquid-input text-xs"
                    />
                    {webhookType === 'telegram' ? (
                      <>
                        <input
                          type="password"
                          value={webhookBotToken}
                          onChange={(e) => setWebhookBotToken(e.target.value)}
                          placeholder="Telegram Bot Token"
                          className="liquid-input font-mono text-xs"
                        />
                        <input
                          type="text"
                          value={webhookChatId}
                          onChange={(e) => setWebhookChatId(e.target.value)}
                          placeholder="Telegram Chat ID"
                          className="liquid-input font-mono text-xs"
                        />
                      </>
                    ) : (
                      <input
                        type="url"
                        value={webhookUrl}
                        onChange={(e) => setWebhookUrl(e.target.value)}
                        placeholder="https://discord.com/api/webhooks/..."
                        className="liquid-input font-mono text-xs sm:col-span-2"
                      />
                    )}
                  </div>
                )}
              </div>
            </div>
          )}

          {step === 4 && (
            <div className="space-y-4">
              {!initResult ? (
                <>
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
                    <div className="liquid-subcard p-3.5">
                      <div className="text-[10px] font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                        Serveur
                      </div>
                      <div className="mt-1 text-sm font-semibold text-slate-900 dark:text-white">
                        {serverName || 'PVE Command Center'}
                      </div>
                      <div className="mt-0.5 truncate font-mono text-[11px] text-cyan-700 dark:text-cyan-300">
                        {effectivePublicUrl}
                      </div>
                      <div className="mt-1 text-[11px] text-slate-500 dark:text-slate-400">
                        mDNS : {mdnsEnabled ? 'Activé' : 'Désactivé'} • Port {listenPort}
                      </div>
                    </div>

                    <div className="liquid-subcard p-3.5">
                      <div className="text-[10px] font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                        Sécurité
                      </div>
                      <div className="mt-1 text-sm font-semibold text-slate-900 dark:text-white">
                        {tailscaleSsoEnabled ? 'Tailscale SSO + API' : 'Bearer Token / PIN'}
                      </div>
                      <div className="mt-1 text-[11px] text-slate-500 dark:text-slate-400">
                        Code PIN : {adminPin.trim().length >= 4 ? 'Configuré' : 'Non défini'}
                      </div>
                      <div className="text-[11px] text-slate-500 dark:text-slate-400">
                        Jeton : {tokenName || 'Initial Admin Token'}
                      </div>
                    </div>

                    <div className="liquid-subcard p-3.5">
                      <div className="text-[10px] font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                        Supervision
                      </div>
                      <div className="mt-1 text-sm font-semibold text-slate-900 dark:text-white">
                        {selectedServices.length} service(s) ajouté(s)
                      </div>
                      <div className="mt-1 text-[11px] text-slate-500 dark:text-slate-400">
                        Alertes : {alertsEnabled ? 'Activées' : 'En pause'}
                      </div>
                      <div className="text-[11px] text-slate-500 dark:text-slate-400">
                        Webhook : {webhookEnabled ? webhookType : 'Aucun'}
                      </div>
                    </div>
                  </div>

                  <label className="liquid-subcard flex cursor-pointer items-center gap-2.5 p-3.5 text-xs text-slate-700 dark:text-slate-200">
                    <input
                      type="checkbox"
                      checked={saveTokenLocally}
                      onChange={(e) => setSaveTokenLocally(e.target.checked)}
                      className="rounded accent-cyan-500"
                    />
                    Enregistrer automatiquement le jeton Bearer généré dans ce navigateur (recommandé sur LAN)
                  </label>

                  <div className="rounded-2xl border border-cyan-500/25 bg-cyan-500/10 p-4 text-xs text-slate-700 dark:text-slate-200">
                    <p>
                      Cliquez sur <strong>« Écrire config.yaml &amp; Générer le jeton »</strong> pour initialiser votre serveur et obtenir votre clé API administrateur (affichée une seule fois).
                    </p>
                  </div>
                </>
              ) : (
                <div className="space-y-4">
                  <div className="rounded-3xl border border-emerald-500/35 bg-emerald-500/10 p-5">
                    <div className="flex items-start gap-3">
                      <CheckCircle2 className="mt-0.5 h-6 w-6 shrink-0 text-emerald-500" />
                      <div className="min-w-0 flex-1">
                        <h3 className="text-sm font-semibold text-slate-900 dark:text-white">
                          Configuration initialisée avec succès !
                        </h3>
                        <p className="mt-1 text-xs text-slate-600 dark:text-slate-300">
                          Fichier écrit : <code className="font-mono">{initResult.config_path}</code> (hash <code className="font-mono">{initResult.config_hash.slice(0, 10)}</code>)
                        </p>
                      </div>
                    </div>

                    <div className="mt-4 rounded-2xl border border-amber-500/35 bg-amber-500/10 p-4">
                      <div className="flex items-center justify-between gap-2">
                        <span className="flex items-center gap-1.5 text-xs font-semibold text-amber-800 dark:text-amber-200">
                          <KeyRound className="h-4 w-4" />
                          Votre jeton API Administrateur (copiez-le maintenant, il ne sera plus affiché)
                        </span>
                        <button
                          type="button"
                          onClick={() => void handleCopyToken()}
                          className="inline-flex items-center gap-1 rounded-xl bg-amber-500/20 px-2.5 py-1 text-xs font-semibold text-amber-900 dark:text-amber-100"
                        >
                          {copiedToken ? (
                            <>
                              <Check className="h-3.5 w-3.5" /> Copié !
                            </>
                          ) : (
                            <>
                              <Copy className="h-3.5 w-3.5" /> Copier
                            </>
                          )}
                        </button>
                      </div>
                      <div className="mt-2 break-all rounded-xl bg-white/80 px-3 py-2 font-mono text-xs font-semibold text-slate-900 dark:bg-slate-950/80 dark:text-cyan-200">
                        {initResult.api_token}
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex shrink-0 items-center justify-between gap-2 border-t border-slate-200/80 px-5 py-3.5 dark:border-white/10 sm:px-6">
          {!initResult ? (
            <>
              <button
                type="button"
                onClick={step === 1 ? onClose : () => setStep((s) => (s - 1) as 1 | 2 | 3 | 4)}
                className="liquid-pill inline-flex items-center gap-1.5 rounded-2xl px-4 py-2 text-xs font-medium text-slate-700 dark:text-slate-200"
              >
                {step > 1 && <ArrowLeft className="h-3.5 w-3.5" />}
                {step === 1 ? 'Plus tard' : 'Précédent'}
              </button>

              {step < 4 ? (
                <button
                  type="button"
                  onClick={() => setStep((s) => (s + 1) as 1 | 2 | 3 | 4)}
                  className="cider-accent-btn inline-flex items-center gap-1.5 rounded-2xl px-5 py-2 text-xs font-semibold text-white"
                >
                  Suivant
                  <ArrowRight className="h-3.5 w-3.5" />
                </button>
              ) : (
                <button
                  type="button"
                  disabled={submitting}
                  onClick={() => void handleInitOnboarding()}
                  className="cider-accent-btn inline-flex items-center gap-2 rounded-2xl px-5 py-2 text-xs font-semibold text-white disabled:opacity-50"
                >
                  {submitting ? (
                    <>
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      Initialisation…
                    </>
                  ) : (
                    <>
                      <Sparkles className="h-3.5 w-3.5" />
                      Écrire config.yaml &amp; Générer le jeton
                    </>
                  )}
                </button>
              )}
            </>
          ) : (
            <div className="flex w-full justify-end">
              <button
                type="button"
                onClick={() =>
                  onCompleted(
                    `Serveur « ${initResult.server_name} » initialisé et prêt.`
                  )
                }
                className="inline-flex items-center gap-2 rounded-2xl bg-gradient-to-r from-emerald-500 to-cyan-500 px-5 py-2.5 text-xs font-semibold text-white shadow-lg"
              >
                <CheckCircle2 className="h-4 w-4" />
                Entrer dans le Dashboard
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

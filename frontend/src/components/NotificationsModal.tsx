import { useCallback, useEffect, useMemo, useState } from 'react';
import QRCode from 'qrcode';
import {
  AlertCircle,
  Bell,
  BellRing,
  Check,
  CheckCircle2,
  Copy,
  ExternalLink,
  Loader2,
  Plus,
  QrCode,
  RefreshCw,
  Send,
  Smartphone,
  Trash2,
  Webhook,
  X,
} from 'lucide-react';
import type {
  APNsConfigSummary,
  DiscoveryQrResponse,
  NotificationChannelsResponse,
  NotificationTestResponse,
  NotificationTestResultItem,
  WebhookChannelItem,
  WebhookChannelType,
} from '../types';

export function QrCodeView({
  value,
  size = 176,
  className = '',
}: {
  value: string;
  size?: number;
  className?: string;
}) {
  const svgData = useMemo(() => {
    if (!value.trim()) return null;
    try {
      const qr = QRCode.create(value, { errorCorrectionLevel: 'M' });
      const count = qr.modules.size;
      const parts: string[] = [];
      for (let r = 0; r < count; r++) {
        for (let c = 0; c < count; c++) {
          if (qr.modules.get(r, c)) {
            parts.push(`M${c},${r}h1v1h-1z`);
          }
        }
      }
      return { count, path: parts.join('') };
    } catch {
      return null;
    }
  }, [value]);

  if (!svgData) {
    return (
      <div
        style={{ width: size, height: size }}
        className={`flex items-center justify-center rounded-2xl border border-slate-200 bg-white/80 text-xs text-slate-400 dark:border-white/10 dark:bg-slate-900/60 ${className}`}
      >
        QR indisponible
      </div>
    );
  }

  const quiet = 2;
  const viewSize = svgData.count + quiet * 2;

  return (
    <div
      className={`inline-flex items-center justify-center rounded-2xl border border-slate-200/90 bg-white p-2.5 shadow-sm dark:border-white/15 ${className}`}
    >
      <svg
        width={size}
        height={size}
        viewBox={`-${quiet} -${quiet} ${viewSize} ${viewSize}`}
        role="img"
        aria-label="QR Code de connexion Apple"
        shapeRendering="crispEdges"
      >
        <rect
          x={-quiet}
          y={-quiet}
          width={viewSize}
          height={viewSize}
          fill="#ffffff"
        />
        <path d={svgData.path} fill="#0f172a" />
      </svg>
    </div>
  );
}

interface NotificationsModalProps {
  open: boolean;
  onClose: () => void;
  onToast: (toast: { type: 'success' | 'error'; message: string }) => void;
  onUpdated?: () => void;
}

type ModalTab = 'webhooks' | 'apns' | 'pairing';

interface EditableWebhook extends WebhookChannelItem {
  headerEntries: Array<{ key: string; value: string }>;
}

function toEditableWebhook(item: WebhookChannelItem): EditableWebhook {
  return {
    ...item,
    headerEntries: Object.entries(item.headers || {}).map(([key, value]) => ({
      key,
      value,
    })),
  };
}

function createBlankWebhook(type: WebhookChannelType = 'discord'): EditableWebhook {
  const defaults: Record<WebhookChannelType, { name: string; url: string }> = {
    discord: { name: 'Discord Homelab', url: 'https://discord.com/api/webhooks/...' },
    telegram: { name: 'Telegram Bot', url: '' },
    generic: { name: 'ntfy / Gotify / Webhook', url: 'https://ntfy.sh/mon-topic' },
  };
  return {
    id: `wh-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
    name: defaults[type].name,
    type,
    enabled: true,
    url: defaults[type].url,
    bot_token: '',
    bot_token_set: false,
    chat_id: '',
    headers: {},
    has_secret_headers: false,
    notify_on_down: true,
    notify_on_recovery: true,
    include_details: true,
    headerEntries: [],
  };
}

async function copyText(text: string): Promise<boolean> {
  if (!text) return false;
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

export function NotificationsModal({
  open,
  onClose,
  onToast,
  onUpdated,
}: NotificationsModalProps) {
  const [tab, setTab] = useState<ModalTab>('webhooks');
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [testingKey, setTestingKey] = useState<string | null>(null);
  const [testResults, setTestResults] = useState<NotificationTestResultItem[]>([]);
  const [apns, setApns] = useState<APNsConfigSummary | null>(null);
  const [webhooks, setWebhooks] = useState<EditableWebhook[]>([]);
  const [qrData, setQrData] = useState<DiscoveryQrResponse | null>(null);
  const [copiedField, setCopiedField] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    setLoading(true);
    setErrorMsg(null);
    try {
      const [chanResp, qrResp] = await Promise.all([
        fetch('/api/notifications/channels'),
        fetch('/api/discovery/qr'),
      ]);
      if (!chanResp.ok) {
        const err = await chanResp.json().catch(() => ({}));
        throw new Error(err.detail || `Erreur HTTP ${chanResp.status}`);
      }
      const chanData = (await chanResp.json()) as NotificationChannelsResponse;
      setApns(chanData.apns);
      setWebhooks((chanData.webhooks || []).map(toEditableWebhook));
      if (qrResp.ok) {
        setQrData((await qrResp.json()) as DiscoveryQrResponse);
      }
    } catch (err) {
      setErrorMsg(
        err instanceof Error ? err.message : 'Impossible de charger les canaux de notification.'
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (open) {
      setTestResults([]);
      void loadData();
    }
  }, [open, loadData]);

  if (!open) return null;

  const handleCopy = async (key: string, val: string) => {
    const ok = await copyText(val);
    if (ok) {
      setCopiedField(key);
      window.setTimeout(() => setCopiedField(null), 2000);
    }
  };

  const updateWebhook = (idx: number, patch: Partial<EditableWebhook>) => {
    setWebhooks((prev) => prev.map((item, i) => (i === idx ? { ...item, ...patch } : item)));
  };

  const removeWebhook = (idx: number) => {
    setWebhooks((prev) => prev.filter((_, i) => i !== idx));
  };

  const addWebhook = (type: WebhookChannelType) => {
    setWebhooks((prev) => [...prev, createBlankWebhook(type)]);
  };

  const handleSaveChannels = async () => {
    setSaving(true);
    setErrorMsg(null);
    try {
      const payload = {
        apns: apns
          ? {
              enabled: apns.enabled,
              team_id: apns.team_id,
              key_id: apns.key_id,
              bundle_id: apns.bundle_id,
              private_key_path: apns.private_key_path,
              use_sandbox: apns.use_sandbox,
            }
          : undefined,
        webhooks: webhooks.map((wh) => {
          const headers: Record<string, string> = {};
          for (const entry of wh.headerEntries) {
            const k = entry.key.trim();
            if (k) headers[k] = entry.value;
          }
          return {
            id: wh.id,
            name: wh.name.trim() || 'Webhook',
            type: wh.type,
            enabled: wh.enabled,
            url: wh.url.trim(),
            bot_token: wh.bot_token,
            chat_id: wh.chat_id.trim(),
            headers,
            notify_on_down: wh.notify_on_down,
            notify_on_recovery: wh.notify_on_recovery,
            include_details: wh.include_details,
          };
        }),
      };

      const resp = await fetch('/api/notifications/channels', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      }
      if (data.apns) setApns(data.apns as APNsConfigSummary);
      if (Array.isArray(data.webhooks)) {
        setWebhooks((data.webhooks as WebhookChannelItem[]).map(toEditableWebhook));
      }
      onToast({ type: 'success', message: 'Canaux de notification enregistrés.' });
      onUpdated?.();
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Échec de sauvegarde des notifications.');
    } finally {
      setSaving(false);
    }
  };

  const handleTest = async (options: {
    key: string;
    channel_id?: string;
    channel_type?: 'apns' | 'discord' | 'telegram' | 'generic' | 'all';
  }) => {
    setTestingKey(options.key);
    setErrorMsg(null);
    try {
      const resp = await fetch('/api/notifications/test', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          channel_id: options.channel_id,
          channel_type: options.channel_type || 'all',
        }),
      });
      const data = (await resp.json().catch(() => ({}))) as NotificationTestResponse & {
        detail?: string;
      };
      if (!resp.ok) {
        throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      }
      setTestResults(data.results || []);
      onToast({
        type: data.ok ? 'success' : 'error',
        message: data.ok
          ? 'Test de notification envoyé avec succès.'
          : 'Aucun canal actif n’a confirmé la réception du test.',
      });
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Échec du test de notification.');
    } finally {
      setTestingKey(null);
    }
  };

  const handleRemoveDevice = async (token: string) => {
    try {
      const resp = await fetch(`/api/notifications/devices/${encodeURIComponent(token)}`, {
        method: 'DELETE',
      });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      setApns((prev) =>
        prev
          ? {
              ...prev,
              devices: prev.devices.filter((d) => d.device_token !== token),
              registered_devices_count: Math.max(0, prev.registered_devices_count - 1),
            }
          : prev
      );
      onToast({ type: 'success', message: 'Appareil APNs supprimé.' });
    } catch {
      onToast({ type: 'error', message: 'Impossible de supprimer cet appareil.' });
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/60 p-0 backdrop-blur-md sm:items-center sm:p-4"
      onClick={onClose}
    >
      <div
        className="ios-sheet safe-bottom-sheet flex max-h-[92dvh] w-full max-w-3xl flex-col overflow-hidden rounded-t-[32px] text-slate-900 dark:text-slate-100 sm:rounded-3xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="shrink-0 border-b border-slate-200/80 px-5 pb-4 pt-3 dark:border-white/10 sm:px-6 sm:pt-5">
          <div className="mb-3 flex justify-center sm:hidden">
            <div className="ios-grabber" />
          </div>

          <div className="flex items-start justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border border-cyan-500/30 bg-cyan-500/15 text-cyan-600 dark:border-cyan-400/35 dark:text-cyan-300">
                <BellRing className="h-5 w-5" />
              </div>
              <div>
                <h2 className="text-base font-semibold text-slate-900 dark:text-white">
                  Notifications, Webhooks &amp; Appairage Apple
                </h2>
                <p className="text-xs text-slate-500 dark:text-slate-400">
                  Alertes Push APNs, Discord, Telegram, ntfy / Gotify et QR Code iOS / macOS
                </p>
              </div>
            </div>

            <button
              type="button"
              onClick={onClose}
              aria-label="Fermer"
              className="liquid-pill rounded-full p-2 text-slate-500 transition hover:text-slate-900 dark:text-slate-300 dark:hover:text-white"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          <div className="mt-4 flex flex-wrap items-center gap-1.5">
            {(
              [
                { id: 'webhooks', label: `Webhooks (${webhooks.length})`, icon: Webhook },
                {
                  id: 'apns',
                  label: `Push Apple APNs (${apns?.registered_devices_count ?? 0})`,
                  icon: Bell,
                },
                { id: 'pairing', label: 'Connexion App Apple & QR', icon: QrCode },
              ] as const
            ).map((item) => {
              const Icon = item.icon;
              const active = tab === item.id;
              return (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => setTab(item.id)}
                  className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition ${
                    active
                      ? 'border-cyan-500/40 bg-cyan-500/15 text-cyan-700 dark:border-cyan-400/40 dark:text-cyan-200'
                      : 'border-slate-200/80 bg-white/50 text-slate-600 hover:text-slate-900 dark:border-white/10 dark:bg-white/[0.04] dark:text-slate-300 dark:hover:text-white'
                  }`}
                >
                  <Icon className="h-3.5 w-3.5" />
                  <span>{item.label}</span>
                </button>
              );
            })}
          </div>
        </div>

        <div className="flex-1 space-y-5 overflow-y-auto p-5 sm:p-6">
          {errorMsg && (
            <div className="flex items-start gap-2 rounded-2xl border border-rose-500/35 bg-rose-500/10 p-3 text-xs text-rose-700 dark:text-rose-200">
              <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{errorMsg}</span>
            </div>
          )}

          {loading ? (
            <div className="flex items-center justify-center gap-2 py-12 text-sm text-slate-500 dark:text-slate-400">
              <Loader2 className="h-4 w-4 animate-spin text-cyan-500" />
              <span>Chargement des canaux et du QR Code…</span>
            </div>
          ) : (
            <>
              {testResults.length > 0 && (
                <div className="liquid-subcard space-y-2 p-3.5">
                  <div className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                    Résultats du dernier test en direct
                  </div>
                  <div className="space-y-1.5">
                    {testResults.map((res, i) => (
                      <div
                        key={`${res.channel_id}-${i}`}
                        className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-slate-200/80 bg-white/75 px-3 py-2 text-xs dark:border-white/10 dark:bg-slate-900/60"
                      >
                        <div className="flex items-center gap-2">
                          {res.ok ? (
                            <CheckCircle2 className="h-3.5 w-3.5 text-emerald-500" />
                          ) : (
                            <AlertCircle className="h-3.5 w-3.5 text-amber-500" />
                          )}
                          <span className="font-semibold text-slate-900 dark:text-white">
                            {res.channel_name}
                          </span>
                          <span className="rounded bg-slate-200/80 px-1.5 py-0.5 font-mono text-[10px] uppercase text-slate-600 dark:bg-white/10 dark:text-slate-300">
                            {res.channel_type}
                          </span>
                          {res.http_status !== null && (
                            <span className="font-mono text-[11px] text-slate-500 dark:text-slate-400">
                              HTTP {res.http_status}
                            </span>
                          )}
                        </div>
                        <span className="text-slate-600 dark:text-slate-300">{res.message}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {tab === 'webhooks' && (
                <div className="space-y-4">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <button
                        type="button"
                        onClick={() => addWebhook('discord')}
                        className="liquid-pill inline-flex items-center gap-1 rounded-full px-3 py-1.5 text-xs font-medium text-slate-700 hover:text-slate-900 dark:text-slate-200 dark:hover:text-white"
                      >
                        <Plus className="h-3.5 w-3.5 text-indigo-500 dark:text-indigo-300" />
                        Discord
                      </button>
                      <button
                        type="button"
                        onClick={() => addWebhook('telegram')}
                        className="liquid-pill inline-flex items-center gap-1 rounded-full px-3 py-1.5 text-xs font-medium text-slate-700 hover:text-slate-900 dark:text-slate-200 dark:hover:text-white"
                      >
                        <Plus className="h-3.5 w-3.5 text-sky-500 dark:text-sky-300" />
                        Telegram
                      </button>
                      <button
                        type="button"
                        onClick={() => addWebhook('generic')}
                        className="liquid-pill inline-flex items-center gap-1 rounded-full px-3 py-1.5 text-xs font-medium text-slate-700 hover:text-slate-900 dark:text-slate-200 dark:hover:text-white"
                      >
                        <Plus className="h-3.5 w-3.5 text-cyan-500 dark:text-cyan-300" />
                        ntfy / Gotify / HA
                      </button>
                    </div>

                    <button
                      type="button"
                      disabled={testingKey !== null}
                      onClick={() => void handleTest({ key: 'all', channel_type: 'all' })}
                      className="inline-flex items-center gap-1.5 rounded-full border border-cyan-500/35 bg-cyan-500/15 px-3.5 py-1.5 text-xs font-semibold text-cyan-700 transition hover:bg-cyan-500/25 disabled:opacity-50 dark:text-cyan-200"
                    >
                      {testingKey === 'all' ? (
                        <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      ) : (
                        <Send className="h-3.5 w-3.5" />
                      )}
                      Tester tous les canaux
                    </button>
                  </div>

                  {webhooks.length === 0 ? (
                    <div className="rounded-2xl border border-dashed border-slate-300 p-6 text-center text-xs text-slate-500 dark:border-white/15 dark:text-slate-400">
                      Aucun webhook configuré. Ajoutez Discord, Telegram ou un webhook générique ci-dessus.
                    </div>
                  ) : (
                    <div className="space-y-3">
                      {webhooks.map((wh, idx) => (
                        <div key={wh.id} className="liquid-subcard space-y-3 p-4">
                          <div className="flex flex-wrap items-center justify-between gap-2">
                            <div className="flex flex-wrap items-center gap-2">
                              <span className="rounded-lg bg-cyan-500/15 px-2 py-0.5 font-mono text-[10px] font-semibold uppercase text-cyan-700 dark:text-cyan-300">
                                {wh.type}
                              </span>
                              <label className="inline-flex cursor-pointer items-center gap-1.5 text-xs font-medium text-slate-700 dark:text-slate-200">
                                <input
                                  type="checkbox"
                                  checked={wh.enabled}
                                  onChange={(e) =>
                                    updateWebhook(idx, { enabled: e.target.checked })
                                  }
                                  className="h-3.5 w-3.5 rounded accent-cyan-500"
                                />
                                Actif
                              </label>
                            </div>

                            <div className="flex items-center gap-1.5">
                              <button
                                type="button"
                                disabled={testingKey !== null}
                                onClick={() =>
                                  void handleTest({ key: wh.id, channel_id: wh.id })
                                }
                                className="inline-flex items-center gap-1 rounded-xl border border-cyan-500/35 bg-cyan-500/10 px-2.5 py-1 text-[11px] font-semibold text-cyan-700 hover:bg-cyan-500/20 disabled:opacity-50 dark:text-cyan-200"
                              >
                                {testingKey === wh.id ? (
                                  <Loader2 className="h-3 w-3 animate-spin" />
                                ) : (
                                  <Send className="h-3 w-3" />
                                )}
                                Tester
                              </button>
                              <button
                                type="button"
                                onClick={() => removeWebhook(idx)}
                                className="rounded-xl border border-rose-500/25 bg-rose-500/10 p-1.5 text-rose-600 hover:bg-rose-500/20 dark:text-rose-300"
                                title="Supprimer ce canal"
                              >
                                <Trash2 className="h-3.5 w-3.5" />
                              </button>
                            </div>
                          </div>

                          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                            <div>
                              <label className="mb-1 block text-[11px] font-medium text-slate-500 dark:text-slate-400">
                                Nom du canal
                              </label>
                              <input
                                type="text"
                                value={wh.name}
                                onChange={(e) => updateWebhook(idx, { name: e.target.value })}
                                className="liquid-input"
                              />
                            </div>
                            <div>
                              <label className="mb-1 block text-[11px] font-medium text-slate-500 dark:text-slate-400">
                                Type
                              </label>
                              <select
                                value={wh.type}
                                onChange={(e) =>
                                  updateWebhook(idx, {
                                    type: e.target.value as WebhookChannelType,
                                  })
                                }
                                className="liquid-input"
                              >
                                <option value="discord">Discord Webhook</option>
                                <option value="telegram">Telegram Bot API</option>
                                <option value="generic">Générique (ntfy, Gotify, HA)</option>
                              </select>
                            </div>
                          </div>

                          {wh.type !== 'telegram' && (
                            <div>
                              <label className="mb-1 block text-[11px] font-medium text-slate-500 dark:text-slate-400">
                                URL du Webhook
                              </label>
                              <input
                                type="url"
                                value={wh.url}
                                onChange={(e) => updateWebhook(idx, { url: e.target.value })}
                                placeholder={
                                  wh.type === 'discord'
                                    ? 'https://discord.com/api/webhooks/...'
                                    : 'https://ntfy.sh/mon-topic'
                                }
                                className="liquid-input font-mono text-xs"
                              />
                            </div>
                          )}

                          {wh.type === 'telegram' && (
                            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                              <div>
                                <label className="mb-1 block text-[11px] font-medium text-slate-500 dark:text-slate-400">
                                  Bot Token {wh.bot_token_set ? '(configuré — laisser ********)' : ''}
                                </label>
                                <input
                                  type="password"
                                  value={wh.bot_token}
                                  onChange={(e) =>
                                    updateWebhook(idx, { bot_token: e.target.value })
                                  }
                                  placeholder={wh.bot_token_set ? '********' : '123456:ABC-DEF...'}
                                  className="liquid-input font-mono text-xs"
                                />
                              </div>
                              <div>
                                <label className="mb-1 block text-[11px] font-medium text-slate-500 dark:text-slate-400">
                                  Chat ID
                                </label>
                                <input
                                  type="text"
                                  value={wh.chat_id}
                                  onChange={(e) => updateWebhook(idx, { chat_id: e.target.value })}
                                  placeholder="-1001234567890"
                                  className="liquid-input font-mono text-xs"
                                />
                              </div>
                            </div>
                          )}

                          {wh.type === 'generic' && (
                            <div className="space-y-2">
                              <div className="flex items-center justify-between">
                                <span className="text-[11px] font-medium text-slate-500 dark:text-slate-400">
                                  En-têtes HTTP personnalisés
                                </span>
                                <button
                                  type="button"
                                  onClick={() =>
                                    updateWebhook(idx, {
                                      headerEntries: [
                                        ...wh.headerEntries,
                                        { key: '', value: '' },
                                      ],
                                    })
                                  }
                                  className="text-[11px] font-semibold text-cyan-600 hover:underline dark:text-cyan-300"
                                >
                                  + Ajouter un header
                                </button>
                              </div>
                              {wh.headerEntries.map((entry, hIdx) => (
                                <div key={hIdx} className="grid grid-cols-12 gap-2">
                                  <input
                                    type="text"
                                    value={entry.key}
                                    onChange={(e) => {
                                      const next = [...wh.headerEntries];
                                      next[hIdx] = { ...entry, key: e.target.value };
                                      updateWebhook(idx, { headerEntries: next });
                                    }}
                                    placeholder="Authorization"
                                    className="liquid-input col-span-5 font-mono text-xs"
                                  />
                                  <input
                                    type="text"
                                    value={entry.value}
                                    onChange={(e) => {
                                      const next = [...wh.headerEntries];
                                      next[hIdx] = { ...entry, value: e.target.value };
                                      updateWebhook(idx, { headerEntries: next });
                                    }}
                                    placeholder="Bearer ..."
                                    className="liquid-input col-span-6 font-mono text-xs"
                                  />
                                  <button
                                    type="button"
                                    onClick={() =>
                                      updateWebhook(idx, {
                                        headerEntries: wh.headerEntries.filter(
                                          (_, i) => i !== hIdx
                                        ),
                                      })
                                    }
                                    className="col-span-1 flex items-center justify-center rounded-xl border border-rose-500/25 bg-rose-500/10 text-rose-500"
                                  >
                                    <X className="h-3.5 w-3.5" />
                                  </button>
                                </div>
                              ))}
                            </div>
                          )}

                          <div className="flex flex-wrap gap-4 border-t border-slate-200/70 pt-2.5 text-xs text-slate-600 dark:border-white/10 dark:text-slate-300">
                            <label className="inline-flex items-center gap-1.5">
                              <input
                                type="checkbox"
                                checked={wh.notify_on_down}
                                onChange={(e) =>
                                  updateWebhook(idx, { notify_on_down: e.target.checked })
                                }
                                className="rounded accent-cyan-500"
                              />
                              Alerte panne
                            </label>
                            <label className="inline-flex items-center gap-1.5">
                              <input
                                type="checkbox"
                                checked={wh.notify_on_recovery}
                                onChange={(e) =>
                                  updateWebhook(idx, { notify_on_recovery: e.target.checked })
                                }
                                className="rounded accent-cyan-500"
                              />
                              Alerte rétablissement
                            </label>
                            <label className="inline-flex items-center gap-1.5">
                              <input
                                type="checkbox"
                                checked={wh.include_details}
                                onChange={(e) =>
                                  updateWebhook(idx, { include_details: e.target.checked })
                                }
                                className="rounded accent-cyan-500"
                              />
                              Inclure détails &amp; latence
                            </label>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {tab === 'apns' && apns && (
                <div className="space-y-4">
                  <div className="liquid-subcard space-y-3 p-4">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        <span
                          className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11px] font-semibold ${
                            apns.configured
                              ? 'border border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300'
                              : 'border border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-300'
                          }`}
                        >
                          {apns.configured ? 'Clé .p8 prête' : 'Configuration APNs incomplète'}
                        </span>
                        <label className="inline-flex cursor-pointer items-center gap-1.5 text-xs font-medium">
                          <input
                            type="checkbox"
                            checked={apns.enabled}
                            onChange={(e) =>
                              setApns((p) => (p ? { ...p, enabled: e.target.checked } : p))
                            }
                            className="rounded accent-cyan-500"
                          />
                          APNs activé
                        </label>
                      </div>

                      <button
                        type="button"
                        disabled={testingKey !== null}
                        onClick={() => void handleTest({ key: 'apns', channel_type: 'apns' })}
                        className="inline-flex items-center gap-1.5 rounded-full border border-cyan-500/35 bg-cyan-500/15 px-3 py-1 text-xs font-semibold text-cyan-700 hover:bg-cyan-500/25 disabled:opacity-50 dark:text-cyan-200"
                      >
                        {testingKey === 'apns' ? (
                          <Loader2 className="h-3.5 w-3.5 animate-spin" />
                        ) : (
                          <Send className="h-3.5 w-3.5" />
                        )}
                        Tester Push Apple
                      </button>
                    </div>

                    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                      <div>
                        <label className="mb-1 block text-[11px] font-medium text-slate-500 dark:text-slate-400">
                          Team ID Apple
                        </label>
                        <input
                          type="text"
                          value={apns.team_id}
                          onChange={(e) =>
                            setApns((p) => (p ? { ...p, team_id: e.target.value } : p))
                          }
                          placeholder="ABCDE12345"
                          className="liquid-input font-mono text-xs"
                        />
                      </div>
                      <div>
                        <label className="mb-1 block text-[11px] font-medium text-slate-500 dark:text-slate-400">
                          Key ID (.p8)
                        </label>
                        <input
                          type="text"
                          value={apns.key_id}
                          onChange={(e) =>
                            setApns((p) => (p ? { ...p, key_id: e.target.value } : p))
                          }
                          placeholder="KEY1234567"
                          className="liquid-input font-mono text-xs"
                        />
                      </div>
                      <div>
                        <label className="mb-1 block text-[11px] font-medium text-slate-500 dark:text-slate-400">
                          Bundle ID App
                        </label>
                        <input
                          type="text"
                          value={apns.bundle_id}
                          onChange={(e) =>
                            setApns((p) => (p ? { ...p, bundle_id: e.target.value } : p))
                          }
                          placeholder="com.example.pvecenter"
                          className="liquid-input font-mono text-xs"
                        />
                      </div>
                      <div>
                        <label className="mb-1 block text-[11px] font-medium text-slate-500 dark:text-slate-400">
                          Chemin clé .p8 ({apns.private_key_exists ? 'trouvée' : 'absente'})
                        </label>
                        <input
                          type="text"
                          value={apns.private_key_path}
                          onChange={(e) =>
                            setApns((p) => (p ? { ...p, private_key_path: e.target.value } : p))
                          }
                          placeholder="/app/config/apns_key.p8"
                          className="liquid-input font-mono text-xs"
                        />
                      </div>
                    </div>

                    <label className="inline-flex items-center gap-2 text-xs text-slate-600 dark:text-slate-300">
                      <input
                        type="checkbox"
                        checked={apns.use_sandbox}
                        onChange={(e) =>
                          setApns((p) => (p ? { ...p, use_sandbox: e.target.checked } : p))
                        }
                        className="rounded accent-cyan-500"
                      />
                      Environnement Sandbox (Xcode Debug)
                    </label>
                  </div>

                  <div className="space-y-2.5">
                    <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                      Appareils Apple enregistrés ({apns.devices.length})
                    </h3>
                    {apns.devices.length === 0 ? (
                      <div className="rounded-2xl border border-dashed border-slate-300 p-5 text-center text-xs text-slate-500 dark:border-white/15 dark:text-slate-400">
                        Aucun appareil enregistré pour le moment. Connectez l’application iOS / macOS via le QR Code pour activer les notifications Push.
                      </div>
                    ) : (
                      <div className="space-y-2">
                        {apns.devices.map((dev) => (
                          <div
                            key={dev.device_token}
                            className="liquid-subcard flex items-center justify-between gap-3 px-3.5 py-2.5"
                          >
                            <div className="flex min-w-0 items-center gap-2.5">
                              <Smartphone className="h-4 w-4 shrink-0 text-cyan-500 dark:text-cyan-300" />
                              <div className="min-w-0">
                                <div className="flex items-center gap-2 text-xs font-semibold text-slate-900 dark:text-white">
                                  <span className="truncate">
                                    {dev.device_name || `Appareil ${dev.platform}`}
                                  </span>
                                  <span className="rounded bg-slate-200/80 px-1.5 py-0.5 text-[10px] uppercase text-slate-600 dark:bg-white/10 dark:text-slate-300">
                                    {dev.platform}
                                  </span>
                                  <span className="rounded bg-indigo-500/10 px-1.5 py-0.5 text-[10px] text-indigo-600 dark:text-indigo-300">
                                    {dev.environment}
                                  </span>
                                </div>
                                <div className="truncate font-mono text-[11px] text-slate-500 dark:text-slate-400">
                                  {dev.device_token.slice(0, 18)}…{dev.device_token.slice(-8)}
                                </div>
                              </div>
                            </div>
                            <button
                              type="button"
                              onClick={() => void handleRemoveDevice(dev.device_token)}
                              className="rounded-xl border border-rose-500/25 bg-rose-500/10 p-1.5 text-rose-600 hover:bg-rose-500/20 dark:text-rose-300"
                              title="Révoquer cet appareil"
                            >
                              <Trash2 className="h-3.5 w-3.5" />
                            </button>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
              )}

              {tab === 'pairing' && (
                <div className="space-y-4">
                  <div className="cider-accent-ring rounded-3xl border p-5">
                    <div className="flex flex-col items-center gap-5 sm:flex-row sm:items-start">
                      <div className="shrink-0 text-center">
                        <QrCodeView value={qrData?.deep_link || ''} size={172} />
                        <p className="mt-2 text-[11px] font-medium text-slate-500 dark:text-slate-400">
                          Scanner avec iPhone / iPad
                        </p>
                      </div>

                      <div className="min-w-0 flex-1 space-y-3">
                        <div>
                          <div className="flex items-center justify-between gap-2">
                            <h3 className="text-sm font-semibold text-slate-900 dark:text-white">
                              Connexion App Apple — {qrData?.server_name || 'PVE Center'}
                            </h3>
                            <button
                              type="button"
                              onClick={() => void loadData()}
                              className="liquid-pill rounded-full p-1.5 text-slate-500 hover:text-slate-900 dark:text-slate-300 dark:hover:text-white"
                              title="Actualiser les métadonnées QR"
                            >
                              <RefreshCw className="h-3.5 w-3.5" />
                            </button>
                          </div>
                          <p className="mt-1 text-xs text-slate-600 dark:text-slate-300">
                            Scannez ce QR Code depuis l’app iOS/iPadOS/macOS ou ouvrez le lien profond pour associer ce serveur automatiquement.
                          </p>
                        </div>

                        {qrData && (
                          <>
                            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                              <div className="liquid-subcard px-3 py-2">
                                <div className="text-[10px] uppercase tracking-wider text-slate-500 dark:text-slate-400">
                                  URL Publique
                                </div>
                                <div className="mt-0.5 truncate font-mono text-xs font-medium text-cyan-700 dark:text-cyan-200">
                                  {qrData.public_url}
                                </div>
                              </div>
                              <div className="liquid-subcard px-3 py-2">
                                <div className="text-[10px] uppercase tracking-wider text-slate-500 dark:text-slate-400">
                                  LAN &amp; Bonjour mDNS
                                </div>
                                <div className="mt-0.5 truncate font-mono text-xs font-medium text-slate-700 dark:text-slate-200">
                                  {qrData.lan_ip}:{qrData.port} • {qrData.mdns_service_type}
                                </div>
                              </div>
                            </div>

                            <div className="liquid-subcard flex items-center justify-between gap-2 px-3 py-2">
                              <span className="truncate font-mono text-[11px] text-slate-600 dark:text-slate-300">
                                {qrData.deep_link}
                              </span>
                              <button
                                type="button"
                                onClick={() => void handleCopy('deeplink', qrData.deep_link)}
                                className="inline-flex shrink-0 items-center gap-1 rounded-lg bg-cyan-500/15 px-2.5 py-1 text-[11px] font-semibold text-cyan-700 dark:text-cyan-200"
                              >
                                {copiedField === 'deeplink' ? (
                                  <>
                                    <Check className="h-3 w-3" /> Copié
                                  </>
                                ) : (
                                  <>
                                    <Copy className="h-3 w-3" /> Copier
                                  </>
                                )}
                              </button>
                            </div>

                            <div className="flex flex-wrap gap-2">
                              <button
                                type="button"
                                onClick={() => void handleCopy('public_url', qrData.public_url)}
                                className="liquid-pill inline-flex items-center gap-1.5 rounded-2xl px-3.5 py-2 text-xs font-semibold text-slate-700 dark:text-slate-200"
                              >
                                <Copy className="h-3.5 w-3.5 text-cyan-500" />
                                {copiedField === 'public_url' ? 'URL copiée !' : 'Copier URL'}
                              </button>
                              <a
                                href={qrData.deep_link}
                                className="cider-accent-btn inline-flex items-center gap-1.5 rounded-2xl px-4 py-2 text-xs font-semibold text-white"
                              >
                                <ExternalLink className="h-3.5 w-3.5" />
                                Ouvrir dans PVE Center
                              </a>
                            </div>
                          </>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </>
          )}
        </div>

        <div className="flex shrink-0 items-center justify-between gap-3 border-t border-slate-200/80 px-5 py-3.5 dark:border-white/10 sm:px-6">
          <button
            type="button"
            onClick={onClose}
            className="liquid-pill rounded-2xl px-4 py-2 text-xs font-medium text-slate-700 dark:text-slate-200"
          >
            Fermer
          </button>
          {tab !== 'pairing' && (
            <button
              type="button"
              disabled={saving || loading}
              onClick={() => void handleSaveChannels()}
              className="cider-accent-btn inline-flex items-center gap-2 rounded-2xl px-5 py-2 text-xs font-semibold text-white transition hover:brightness-110 disabled:opacity-50"
            >
              {saving ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Enregistrement…
                </>
              ) : (
                <>
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  Enregistrer les canaux
                </>
              )}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

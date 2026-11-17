import { useEffect, useState, type FormEvent } from 'react';
import {
  Activity,
  AlertCircle,
  Check,
  CheckCircle2,
  Copy,
  Loader2,
  Play,
  Shield,
  Webhook,
  X,
} from 'lucide-react';
import { getServerUrl } from '../lib/apiClient';
import { ServiceIconBadge, ServiceIconPicker } from './ServiceIcon';
import type {
  CustomServiceItem,
  CustomServicePayload,
  CustomServiceTestResponse,
  ServiceAuthType,
  ServiceProtocol,
} from '../types';

interface CustomServiceModalProps {
  open: boolean;
  service: CustomServiceItem | null;
  existingCategories: string[];
  onClose: () => void;
  onSaved: (message: string) => void;
}

const PROTOCOL_OPTIONS: Array<{
  value: ServiceProtocol;
  label: string;
  hint: string;
}> = [
  {
    value: 'http_rest',
    label: 'HTTP / REST Healthcheck',
    hint: 'Vérifie un endpoint HTTP/HTTPS et le code retour attendu.',
  },
  {
    value: 'json_metrics',
    label: 'API JSON & Métriques',
    hint: 'Interroge une API JSON et extrait des métriques via dot-path.',
  },
  {
    value: 'tcp_port',
    label: 'Port TCP (Socket)',
    hint: 'Teste la disponibilité d’un port TCP (PostgreSQL, Redis, SSH, MQTT…).',
  },
  {
    value: 'icmp_ping',
    label: 'ICMP Ping',
    hint: 'Mesure le RTT réseau et la perte de paquets vers un hôte.',
  },
  {
    value: 'webhook_ingest',
    label: 'Webhook Ingest (Push)',
    hint: 'Reçoit les heartbeats entrants de vos scripts, cron ou agents.',
  },
];

function slugifyId(raw: string): string {
  return raw
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

export function CustomServiceModal({
  open,
  service,
  existingCategories,
  onClose,
  onSaved,
}: CustomServiceModalProps) {
  const isEditing = Boolean(service);

  const [id, setId] = useState('');
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [category, setCategory] = useState('Services Personnalisés');
  const [icon, setIcon] = useState('Globe');
  const [protocol, setProtocol] = useState<ServiceProtocol>('http_rest');
  const [host, setHost] = useState('');
  const [port, setPort] = useState('');
  const [url, setUrl] = useState('');
  const [healthUrl, setHealthUrl] = useState('');
  const [internalUrl, setInternalUrl] = useState('');
  const [authType, setAuthType] = useState<ServiceAuthType>('none');
  const [authToken, setAuthToken] = useState('');
  const [authTokenSet, setAuthTokenSet] = useState(false);
  const [authHeaderName, setAuthHeaderName] = useState('');
  const [jsonMetricPath, setJsonMetricPath] = useState('');
  const [expectedStatus, setExpectedStatus] = useState('200');
  const [refreshInterval, setRefreshInterval] = useState('30');
  const [webhookTtl, setWebhookTtl] = useState('300');
  const [enabled, setEnabled] = useState(true);
  const [verifySsl, setVerifySsl] = useState(false);
  const [alertEnabled, setAlertEnabled] = useState(true);
  const [consecutiveFailures, setConsecutiveFailures] = useState('2');
  const [cooldownSeconds, setCooldownSeconds] = useState('300');

  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<CustomServiceTestResponse | null>(null);
  const [saving, setSaving] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [copiedWebhook, setCopiedWebhook] = useState(false);

  useEffect(() => {
    if (!open) return;
    setTestResult(null);
    setErrorMsg(null);

    if (service) {
      setId(service.id);
      setName(service.name);
      setDescription(service.description || '');
      setCategory(service.category || 'Services Personnalisés');
      setIcon(service.icon || 'Globe');
      setProtocol(service.protocol || 'http_rest');
      setHost(service.host || '');
      setPort(service.port ? String(service.port) : '');
      setUrl(service.url || '');
      setHealthUrl(service.health_url || '');
      setInternalUrl(service.internal_url || '');
      setAuthType(service.auth_type || 'none');
      setAuthToken(service.auth_token_set ? '********' : '');
      setAuthTokenSet(Boolean(service.auth_token_set));
      setAuthHeaderName(service.auth_header_name || '');
      setJsonMetricPath(service.json_metric_path || '');
      setExpectedStatus(String(service.expected_status ?? 200));
      setRefreshInterval(String(service.refresh_interval_seconds ?? 30));
      setWebhookTtl(String(service.webhook_ttl_seconds ?? 300));
      setEnabled(service.enabled !== false);
      setVerifySsl(Boolean(service.verify_ssl));
      setAlertEnabled(service.alert_policy?.enabled !== false);
      setConsecutiveFailures(String(service.alert_policy?.consecutive_failures ?? 2));
      setCooldownSeconds(String(service.alert_policy?.cooldown_seconds ?? 300));
    } else {
      setId('');
      setName('');
      setDescription('');
      setCategory(existingCategories[0] || 'Services Personnalisés');
      setIcon('Globe');
      setProtocol('http_rest');
      setHost('');
      setPort('');
      setUrl('');
      setHealthUrl('');
      setInternalUrl('');
      setAuthType('none');
      setAuthToken('');
      setAuthTokenSet(false);
      setAuthHeaderName('');
      setJsonMetricPath('');
      setExpectedStatus('200');
      setRefreshInterval('30');
      setWebhookTtl('300');
      setEnabled(true);
      setVerifySsl(false);
      setAlertEnabled(true);
      setConsecutiveFailures('2');
      setCooldownSeconds('300');
    }
  }, [open, service, existingCategories]);

  if (!open) return null;

  const effectiveId = isEditing ? id : id.trim() || slugifyId(name) || 'nouveau-service';
  const baseOrigin =
    getServerUrl() || (typeof window !== 'undefined' ? window.location.origin : 'http://localhost:8000');
  const webhookEndpoint = `${baseOrigin}/api/custom-services/${effectiveId}/webhook`;

  const buildPayload = (): CustomServicePayload => {
    const parsedPort = Number(port);
    return {
      ...(isEditing ? {} : { id: id.trim() || undefined }),
      name: name.trim(),
      description: description.trim(),
      category: category.trim() || 'Services Personnalisés',
      icon,
      protocol,
      host: host.trim(),
      port: port.trim() && Number.isFinite(parsedPort) && parsedPort > 0 ? parsedPort : null,
      url: url.trim(),
      health_url: healthUrl.trim(),
      internal_url: internalUrl.trim(),
      auth_type: authType,
      auth_token: authToken,
      auth_header_name: authHeaderName.trim(),
      json_metric_path: jsonMetricPath.trim(),
      expected_status: Math.min(599, Math.max(100, Number(expectedStatus) || 200)),
      refresh_interval_seconds: Math.min(3600, Math.max(5, Number(refreshInterval) || 30)),
      webhook_ttl_seconds: Math.min(86400, Math.max(10, Number(webhookTtl) || 300)),
      enabled,
      verify_ssl: verifySsl,
      alert_policy: {
        enabled: alertEnabled,
        consecutive_failures: Math.min(20, Math.max(1, Number(consecutiveFailures) || 2)),
        cooldown_seconds: Math.min(86400, Math.max(0, Number(cooldownSeconds) || 300)),
      },
    };
  };

  const handleDryRunTest = async () => {
    setTesting(true);
    setTestResult(null);
    setErrorMsg(null);
    try {
      const targetId = isEditing ? service!.id : effectiveId;
      const payload = buildPayload();
      const resp = await fetch(`/api/custom-services/${encodeURIComponent(targetId)}/test`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      }
      setTestResult(data as CustomServiceTestResponse);
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Échec du test de connectivité.');
    } finally {
      setTesting(false);
    }
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!name.trim()) {
      setErrorMsg('Le nom du service est obligatoire.');
      return;
    }
    setSaving(true);
    setErrorMsg(null);
    try {
      const payload = buildPayload();
      const endpoint = isEditing
        ? `/api/custom-services/${encodeURIComponent(service!.id)}`
        : '/api/custom-services';
      const resp = await fetch(endpoint, {
        method: isEditing ? 'PUT' : 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      }
      onSaved(
        isEditing
          ? `Service « ${name.trim()} » mis à jour.`
          : `Service « ${name.trim()} » créé.`
      );
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Impossible d’enregistrer le service.');
    } finally {
      setSaving(false);
    }
  };

  const handleCopyWebhook = async () => {
    const tokenSnippet =
      authType !== 'none' ? ` \\\n  -H "Authorization: Bearer VOTRE_TOKEN"` : '';
    const curlSnippet = `curl -X POST "${webhookEndpoint}" \\\n  -H "Content-Type: application/json"${tokenSnippet} \\\n  -d '{"status":"up","message":"Heartbeat OK","metrics":{"jobs_ok":1}}'`;
    try {
      await navigator.clipboard.writeText(curlSnippet);
      setCopiedWebhook(true);
      window.setTimeout(() => setCopiedWebhook(false), 2000);
    } catch {
      // Ignore clipboard failures
    }
  };

  const categorySuggestions = Array.from(
    new Set([
      ...existingCategories,
      'Services Personnalisés',
      'Médias & Streaming',
      'Infrastructure & Sécurité',
      'Réseau & DNS',
      'Domotique',
    ])
  );

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/60 p-0 backdrop-blur-md sm:items-center sm:p-4"
      onClick={onClose}
    >
      <div
        className="ios-sheet safe-bottom-sheet flex max-h-[92dvh] w-full max-w-2xl flex-col overflow-hidden rounded-t-[32px] text-slate-900 dark:text-slate-100 sm:rounded-3xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="shrink-0 border-b border-slate-200/80 px-5 pb-4 pt-3 dark:border-white/10 sm:px-6 sm:pt-5">
          <div className="mb-3 flex justify-center sm:hidden">
            <div className="ios-grabber" />
          </div>
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-center gap-3">
              <ServiceIconBadge
                icon={icon}
                hint={{ id: isEditing ? id : effectiveId, name }}
                size="md"
              />
              <div>
                <h2 className="text-base font-semibold text-slate-900 dark:text-white">
                  {isEditing ? `Modifier « ${service?.name} »` : 'Nouveau service personnalisé'}
                </h2>
                <p className="text-xs text-slate-500 dark:text-slate-400">
                  Connecteur supervisé avec alertes, métriques temps réel et test à chaud
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
        </div>

        <form onSubmit={handleSubmit} className="flex flex-1 flex-col overflow-hidden">
          <div className="flex-1 space-y-5 overflow-y-auto p-5 sm:p-6">
            {errorMsg && (
              <div className="flex items-start gap-2 rounded-2xl border border-rose-500/35 bg-rose-500/10 p-3 text-xs text-rose-700 dark:text-rose-200">
                <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                <span>{errorMsg}</span>
              </div>
            )}

            {/* Identité */}
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div>
                <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                  Nom du service *
                </label>
                <input
                  type="text"
                  required
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Home Assistant / AdGuard / PostgreSQL"
                  className="liquid-input"
                />
              </div>

              <div>
                <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                  Identifiant (slug)
                </label>
                <input
                  type="text"
                  value={isEditing ? id : id}
                  disabled={isEditing}
                  onChange={(e) => setId(e.target.value)}
                  placeholder={effectiveId}
                  className="liquid-input font-mono text-xs disabled:opacity-60"
                />
              </div>

              <div>
                <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                  Catégorie
                </label>
                <input
                  type="text"
                  list="custom-service-categories"
                  value={category}
                  onChange={(e) => setCategory(e.target.value)}
                  className="liquid-input"
                />
                <datalist id="custom-service-categories">
                  {categorySuggestions.map((cat) => (
                    <option key={cat} value={cat} />
                  ))}
                </datalist>
              </div>
            </div>

            <div className="liquid-subcard p-4">
              <ServiceIconPicker
                value={icon}
                hint={{ id: isEditing ? id : effectiveId, name }}
                onChange={setIcon}
              />
            </div>

            <div>
              <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                Description
              </label>
              <input
                type="text"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Courte description affichée sur la carte du service"
                className="liquid-input"
              />
            </div>

            {/* Protocole */}
            <div className="liquid-subcard space-y-3 p-4">
              <div className="flex items-center justify-between gap-2">
                <span className="flex items-center gap-1.5 text-xs font-semibold text-slate-900 dark:text-white">
                  <Activity className="h-4 w-4 text-cyan-500 dark:text-cyan-300" />
                  Protocole de supervision
                </span>
                <label className="inline-flex cursor-pointer items-center gap-1.5 text-xs font-medium text-slate-700 dark:text-slate-200">
                  <input
                    type="checkbox"
                    checked={enabled}
                    onChange={(e) => setEnabled(e.target.checked)}
                    className="rounded accent-cyan-500"
                  />
                  Service activé
                </label>
              </div>

              <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                {PROTOCOL_OPTIONS.map((opt) => {
                  const selected = protocol === opt.value;
                  return (
                    <button
                      key={opt.value}
                      type="button"
                      onClick={() => setProtocol(opt.value)}
                      className={`rounded-2xl border p-3 text-left transition ${
                        selected
                          ? 'border-cyan-500/50 bg-cyan-500/10 text-slate-900 dark:border-cyan-400/50 dark:text-white'
                          : 'border-slate-200/80 bg-white/50 text-slate-600 hover:border-slate-300 dark:border-white/10 dark:bg-white/[0.03] dark:text-slate-300'
                      }`}
                    >
                      <div className="text-xs font-semibold">{opt.label}</div>
                      <div className="mt-0.5 text-[11px] opacity-80">{opt.hint}</div>
                    </button>
                  );
                })}
              </div>

              {(protocol === 'http_rest' || protocol === 'json_metrics') && (
                <div className="grid grid-cols-1 gap-3 pt-1 sm:grid-cols-2">
                  <div className="sm:col-span-2">
                    <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                      URL d’ouverture (carte Dashboard)
                    </label>
                    <input
                      type="url"
                      value={url}
                      onChange={(e) => setUrl(e.target.value)}
                      placeholder="https://service.example.ts.net"
                      className="liquid-input font-mono text-xs"
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                      URL Healthcheck / Endpoint API
                    </label>
                    <input
                      type="url"
                      value={healthUrl}
                      onChange={(e) => setHealthUrl(e.target.value)}
                      placeholder="http://192.168.1.40:8123/api/"
                      className="liquid-input font-mono text-xs"
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                      Code HTTP attendu
                    </label>
                    <input
                      type="number"
                      min={100}
                      max={599}
                      value={expectedStatus}
                      onChange={(e) => setExpectedStatus(e.target.value)}
                      className="liquid-input font-mono text-xs"
                    />
                  </div>
                  {protocol === 'json_metrics' && (
                    <div className="sm:col-span-2">
                      <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                        Chemins de métriques JSON (séparés par virgule)
                      </label>
                      <input
                        type="text"
                        value={jsonMetricPath}
                        onChange={(e) => setJsonMetricPath(e.target.value)}
                        placeholder="stats.active_users, version, num_dns_queries"
                        className="liquid-input font-mono text-xs"
                      />
                    </div>
                  )}
                  <label className="inline-flex items-center gap-2 text-xs text-slate-600 dark:text-slate-300 sm:col-span-2">
                    <input
                      type="checkbox"
                      checked={verifySsl}
                      onChange={(e) => setVerifySsl(e.target.checked)}
                      className="rounded accent-cyan-500"
                    />
                    Vérifier strictement les certificats TLS/SSL
                  </label>
                </div>
              )}

              {(protocol === 'tcp_port' || protocol === 'icmp_ping') && (
                <div className="grid grid-cols-1 gap-3 pt-1 sm:grid-cols-3">
                  <div className={protocol === 'tcp_port' ? 'sm:col-span-2' : 'sm:col-span-3'}>
                    <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                      Hôte ou IP *
                    </label>
                    <input
                      type="text"
                      value={host}
                      onChange={(e) => setHost(e.target.value)}
                      placeholder="192.168.1.20"
                      className="liquid-input font-mono text-xs"
                    />
                  </div>
                  {protocol === 'tcp_port' && (
                    <div>
                      <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                        Port TCP *
                      </label>
                      <input
                        type="number"
                        min={1}
                        max={65535}
                        value={port}
                        onChange={(e) => setPort(e.target.value)}
                        placeholder="5432"
                        className="liquid-input font-mono text-xs"
                      />
                    </div>
                  )}
                  <div className="sm:col-span-3">
                    <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                      URL d’ouverture (optionnel)
                    </label>
                    <input
                      type="url"
                      value={url}
                      onChange={(e) => setUrl(e.target.value)}
                      placeholder="https://admin.example.ts.net"
                      className="liquid-input font-mono text-xs"
                    />
                  </div>
                </div>
              )}

              {protocol === 'webhook_ingest' && (
                <div className="space-y-3 pt-1">
                  <div>
                    <label className="mb-1 block text-[11px] font-medium text-slate-600 dark:text-slate-300">
                      Expiration heartbeat TTL (secondes)
                    </label>
                    <input
                      type="number"
                      min={10}
                      max={86400}
                      value={webhookTtl}
                      onChange={(e) => setWebhookTtl(e.target.value)}
                      className="liquid-input font-mono text-xs"
                    />
                  </div>

                  <div className="rounded-2xl border border-indigo-500/25 bg-indigo-500/10 p-3 text-xs">
                    <div className="flex items-center justify-between gap-2">
                      <span className="flex items-center gap-1.5 font-semibold text-indigo-700 dark:text-indigo-200">
                        <Webhook className="h-3.5 w-3.5" />
                        URL d’ingestion Webhook
                      </span>
                      <button
                        type="button"
                        onClick={() => void handleCopyWebhook()}
                        className="inline-flex items-center gap-1 rounded-lg bg-indigo-500/20 px-2 py-1 text-[11px] font-semibold text-indigo-700 dark:text-indigo-200"
                      >
                        {copiedWebhook ? (
                          <>
                            <Check className="h-3 w-3" /> Commande curl copiée
                          </>
                        ) : (
                          <>
                            <Copy className="h-3 w-3" /> Copier curl
                          </>
                        )}
                      </button>
                    </div>
                    <div className="mt-1.5 break-all font-mono text-[11px] text-slate-700 dark:text-slate-200">
                      POST {webhookEndpoint}
                    </div>
                  </div>
                </div>
              )}
            </div>

            {/* Authentification & Politique d'alerte */}
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div className="liquid-subcard space-y-2.5 p-3.5">
                <div className="flex items-center gap-1.5 text-xs font-semibold text-slate-900 dark:text-white">
                  <Shield className="h-3.5 w-3.5 text-cyan-500 dark:text-cyan-300" />
                  Authentification
                </div>
                <select
                  value={authType}
                  onChange={(e) => setAuthType(e.target.value as ServiceAuthType)}
                  className="liquid-input text-xs"
                >
                  <option value="none">Aucune authentification</option>
                  <option value="bearer">Bearer Token</option>
                  <option value="header">Header personnalisé (X-Api-Key…)</option>
                  <option value="basic">HTTP Basic (user:pass)</option>
                </select>
                {authType === 'header' && (
                  <input
                    type="text"
                    value={authHeaderName}
                    onChange={(e) => setAuthHeaderName(e.target.value)}
                    placeholder="Nom du header (ex: X-API-Key)"
                    className="liquid-input font-mono text-xs"
                  />
                )}
                {authType !== 'none' && (
                  <input
                    type="password"
                    value={authToken}
                    onChange={(e) => setAuthToken(e.target.value)}
                    placeholder={authTokenSet ? '******** (inchangé)' : 'Jeton ou user:pass'}
                    className="liquid-input font-mono text-xs"
                  />
                )}
              </div>

              <div className="liquid-subcard space-y-2.5 p-3.5">
                <div className="flex items-center justify-between text-xs font-semibold text-slate-900 dark:text-white">
                  <span>Politique d’alerte</span>
                  <label className="inline-flex cursor-pointer items-center gap-1.5 font-medium">
                    <input
                      type="checkbox"
                      checked={alertEnabled}
                      onChange={(e) => setAlertEnabled(e.target.checked)}
                      className="rounded accent-cyan-500"
                    />
                    Activer
                  </label>
                </div>
                <div className="grid grid-cols-3 gap-2">
                  <div>
                    <label className="mb-1 block text-[10px] text-slate-500 dark:text-slate-400">
                      Poll (s)
                    </label>
                    <input
                      type="number"
                      min={5}
                      max={3600}
                      value={refreshInterval}
                      onChange={(e) => setRefreshInterval(e.target.value)}
                      className="liquid-input px-2 py-1.5 font-mono text-xs"
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-[10px] text-slate-500 dark:text-slate-400">
                      Échecs
                    </label>
                    <input
                      type="number"
                      min={1}
                      max={20}
                      value={consecutiveFailures}
                      onChange={(e) => setConsecutiveFailures(e.target.value)}
                      className="liquid-input px-2 py-1.5 font-mono text-xs"
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-[10px] text-slate-500 dark:text-slate-400">
                      Cooldown
                    </label>
                    <input
                      type="number"
                      min={0}
                      max={86400}
                      value={cooldownSeconds}
                      onChange={(e) => setCooldownSeconds(e.target.value)}
                      className="liquid-input px-2 py-1.5 font-mono text-xs"
                    />
                  </div>
                </div>
              </div>
            </div>

            {testResult && (
              <div
                className={`rounded-2xl border p-3.5 text-xs ${
                  testResult.ok
                    ? 'border-emerald-500/35 bg-emerald-500/10 text-emerald-800 dark:text-emerald-200'
                    : 'border-rose-500/35 bg-rose-500/10 text-rose-800 dark:text-rose-200'
                }`}
              >
                <div className="flex flex-wrap items-center justify-between gap-2 font-semibold">
                  <span className="flex items-center gap-1.5">
                    {testResult.ok ? (
                      <CheckCircle2 className="h-4 w-4 text-emerald-500" />
                    ) : (
                      <AlertCircle className="h-4 w-4 text-rose-500" />
                    )}
                    Statut : {testResult.status.toUpperCase()}
                  </span>
                  <div className="flex items-center gap-2 font-mono text-[11px]">
                    {testResult.http_status !== null && <span>HTTP {testResult.http_status}</span>}
                    {testResult.latency_ms !== null && <span>{testResult.latency_ms} ms</span>}
                  </div>
                </div>
                <p className="mt-1 opacity-90">{testResult.message}</p>
                {Object.keys(testResult.metrics || {}).length > 0 && (
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {Object.entries(testResult.metrics).map(([k, v]) => (
                      <span
                        key={k}
                        className="rounded-lg border border-black/10 bg-white/60 px-2 py-0.5 font-mono text-[11px] dark:border-white/15 dark:bg-black/30"
                      >
                        {k}: {String(v)}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>

          <div className="flex shrink-0 flex-wrap items-center justify-between gap-2 border-t border-slate-200/80 px-5 py-3.5 dark:border-white/10 sm:px-6">
            <button
              type="button"
              disabled={testing || saving}
              onClick={() => void handleDryRunTest()}
              className="liquid-pill inline-flex items-center gap-1.5 rounded-2xl px-4 py-2 text-xs font-semibold text-cyan-700 transition hover:bg-cyan-500/10 disabled:opacity-50 dark:text-cyan-200"
            >
              {testing ? (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              ) : (
                <Play className="h-3.5 w-3.5" />
              )}
              Tester la connexion
            </button>

            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={onClose}
                disabled={saving}
                className="liquid-pill rounded-2xl px-4 py-2 text-xs font-medium text-slate-700 dark:text-slate-200"
              >
                Annuler
              </button>
              <button
                type="submit"
                disabled={saving}
                className="cider-accent-btn inline-flex items-center gap-1.5 rounded-2xl px-5 py-2 text-xs font-semibold text-white transition hover:brightness-110 disabled:opacity-50"
              >
                {saving ? (
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <CheckCircle2 className="h-3.5 w-3.5" />
                )}
                {isEditing ? 'Enregistrer' : 'Créer le service'}
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}

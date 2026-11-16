import { useState, type FormEvent } from 'react';
import {
  CheckCircle2,
  Globe,
  Loader2,
  Play,
  Server,
  ShieldCheck,
  Sparkles,
  WifiOff,
  X,
} from 'lucide-react';
import {
  getServerUrl,
  isDemoMode,
  isNativePlatform,
  normalizeServerUrl,
  setDemoMode,
  setServerUrl,
} from '../lib/apiClient';

interface ServerConfigModalProps {
  open: boolean;
  initialMessage?: string | null;
  onClose: () => void;
  onApplied: () => void;
}

export function ServerConfigModal({
  open,
  initialMessage,
  onClose,
  onApplied,
}: ServerConfigModalProps) {
  const [urlInput, setUrlInput] = useState<string>(() => getServerUrl());
  const [testing, setTesting] = useState(false);
  const [feedback, setFeedback] = useState<{
    type: 'error' | 'success';
    text: string;
  } | null>(null);

  if (!open) return null;

  const demoActive = isDemoMode();
  const nativeApp = isNativePlatform();
  const currentServer = getServerUrl();

  const handleConnectServer = async (e: FormEvent) => {
    e.preventDefault();
    const normalized = normalizeServerUrl(urlInput);
    if (!normalized) {
      setFeedback({
        type: 'error',
        text: 'Saisissez une URL valide (ex: https://pve-panel.votre-tailnet.ts.net).',
      });
      return;
    }

    setTesting(true);
    setFeedback(null);
    try {
      const resp = await fetch(`${normalized}/api/me`, {
        method: 'GET',
        credentials: 'include',
      });
      if (!resp.ok) {
        throw new Error(`Le serveur a répondu HTTP ${resp.status}.`);
      }
      const data = (await resp.json()) as { login?: string };
      if (!data?.login) {
        throw new Error('Réponse inattendue : vérifiez que Tailscale Serve pointe vers pve-panel.');
      }
      setDemoMode(false);
      setServerUrl(normalized);
      setFeedback({
        type: 'success',
        text: `Connecté en tant que ${data.login}.`,
      });
      onApplied();
    } catch (err) {
      setFeedback({
        type: 'error',
        text:
          err instanceof Error
            ? `${err.message} Vérifiez que Tailscale est actif sur cet iPhone ou essayez le Mode Démo.`
            : 'Connexion impossible. Vérifiez Tailscale ou activez le Mode Démo.',
      });
    } finally {
      setTesting(false);
    }
  };

  const handleEnableDemo = () => {
    setDemoMode(true);
    setFeedback(null);
    onApplied();
  };

  const handleUseLocalOrigin = () => {
    setDemoMode(false);
    setServerUrl('');
    setUrlInput('');
    setFeedback(null);
    onApplied();
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/70 p-0 backdrop-blur-md sm:items-center sm:p-4"
      onClick={onClose}
    >
      <div
        className="ios-sheet safe-bottom-sheet max-h-[92dvh] w-full max-w-lg overflow-y-auto rounded-t-[32px] p-5 text-slate-100 sm:rounded-3xl sm:p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex justify-center sm:hidden">
          <div className="ios-grabber" />
        </div>

        <div className="flex items-start justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl border border-cyan-400/35 bg-cyan-500/15 text-cyan-300 shadow-inner">
              <Server className="h-5 w-5" />
            </div>
            <div>
              <h2 className="text-base font-semibold text-white">
                Connexion Serveur & Mode Démo
              </h2>
              <p className="text-xs text-slate-400">
                {demoActive
                  ? 'Actuellement en Mode Démo interactif'
                  : currentServer
                    ? `Connecté à ${currentServer}`
                    : nativeApp
                      ? 'Aucun serveur configuré sur cet iPhone'
                      : 'Connecté à l’hôte local (Tailscale Serve)'}
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={onClose}
            aria-label="Fermer"
            className="liquid-pill rounded-full p-2 text-slate-300 transition hover:text-white active:scale-95"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {initialMessage && (
          <div className="mt-4 flex items-start gap-2.5 rounded-2xl border border-amber-400/30 bg-amber-500/10 p-3 text-xs text-amber-200">
            <WifiOff className="mt-0.5 h-4 w-4 shrink-0 text-amber-300" />
            <span>{initialMessage}</span>
          </div>
        )}

        {feedback && (
          <div
            className={`mt-4 flex items-start gap-2.5 rounded-2xl border p-3 text-xs ${
              feedback.type === 'success'
                ? 'border-emerald-400/30 bg-emerald-500/10 text-emerald-200'
                : 'border-rose-400/30 bg-rose-500/10 text-rose-200'
            }`}
          >
            <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
            <span>{feedback.text}</span>
          </div>
        )}

        {/* Mode Démo App Store / Aperçu */}
        <div className="mt-4 rounded-2xl border border-indigo-400/25 bg-gradient-to-br from-indigo-500/15 via-cyan-500/10 to-transparent p-4">
          <div className="flex items-start gap-3">
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-indigo-400/30 bg-indigo-500/20 text-indigo-200">
              <Sparkles className="h-4 w-4" />
            </div>
            <div className="min-w-0 flex-1">
              <h3 className="text-sm font-semibold text-white">
                Mode Démo interactif (App Review / Test)
              </h3>
              <p className="mt-1 text-xs leading-relaxed text-slate-300">
                Explorez l’ensemble de l’interface Liquid Glass (Proxmox VE, stockage 32 To, widgets Jellyfin/Radarr/Sonarr/qBittorrent et utilisateurs) avec des données simulées complètes, sans VPN.
              </p>
              <button
                type="button"
                onClick={handleEnableDemo}
                className="mt-3 inline-flex w-full items-center justify-center gap-2 rounded-2xl bg-gradient-to-r from-cyan-500 to-indigo-500 px-4 py-2.5 text-xs font-semibold text-white shadow-lg shadow-cyan-500/20 transition hover:brightness-110 active:scale-[0.98]"
              >
                <Play className="h-3.5 w-3.5 fill-current" />
                {demoActive ? 'Relancer le Mode Démo' : 'Activer le Mode Démo'}
              </button>
            </div>
          </div>
        </div>

        {/* Connexion serveur Tailscale Serve */}
        <form onSubmit={handleConnectServer} className="mt-5 space-y-3">
          <div>
            <label
              htmlFor="pve-server-url"
              className="mb-1.5 flex items-center gap-1.5 text-xs font-medium text-slate-300"
            >
              <Globe className="h-3.5 w-3.5 text-cyan-400" />
              URL Tailscale Serve de votre panel
            </label>
            <input
              id="pve-server-url"
              type="url"
              inputMode="url"
              autoCapitalize="none"
              autoCorrect="off"
              value={urlInput}
              onChange={(e) => setUrlInput(e.target.value)}
              placeholder="https://pve-panel.votre-tailnet.ts.net"
              className="w-full rounded-2xl border border-white/15 bg-slate-950/70 px-3.5 py-2.5 text-sm text-white placeholder-slate-500 focus:border-cyan-400/60 focus:outline-none focus:ring-2 focus:ring-cyan-400/20"
            />
          </div>

          <div className="flex flex-col gap-2 sm:flex-row">
            <button
              type="submit"
              disabled={testing}
              className="inline-flex flex-1 items-center justify-center gap-2 rounded-2xl border border-cyan-400/40 bg-cyan-500/20 px-4 py-2.5 text-xs font-semibold text-cyan-100 transition hover:bg-cyan-500/30 active:scale-[0.98] disabled:opacity-50"
            >
              {testing ? (
                <>
                  <Loader2 className="h-3.5 w-3.5 animate-spin" />
                  Vérification...
                </>
              ) : (
                <>
                  <ShieldCheck className="h-3.5 w-3.5" />
                  Tester & Connecter
                </>
              )}
            </button>

            {!nativeApp && (currentServer || demoActive) && (
              <button
                type="button"
                onClick={handleUseLocalOrigin}
                className="liquid-pill inline-flex items-center justify-center rounded-2xl px-4 py-2.5 text-xs font-medium text-slate-200 transition hover:text-white active:scale-[0.98]"
              >
                Hôte local
              </button>
            )}
          </div>
        </form>
      </div>
    </div>
  );
}

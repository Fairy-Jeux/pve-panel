import { useCallback, useEffect, useRef, useState, type KeyboardEvent } from 'react';
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle2,
  Download,
  FileCode2,
  Loader2,
  RefreshCw,
  ShieldCheck,
  Upload,
  X,
} from 'lucide-react';
import type {
  ConfigParsedSummary,
  ConfigSaveResponse,
  ConfigValidateResponse,
  ConfigYamlResponse,
} from '../types';

interface YamlConfigEditorModalProps {
  open: boolean;
  onClose: () => void;
  onSaved: (message: string) => void;
}

export function YamlConfigEditorModal({
  open,
  onClose,
  onSaved,
}: YamlConfigEditorModalProps) {
  const [yamlText, setYamlText] = useState('');
  const [hash, setHash] = useState('');
  const [isSynthesized, setIsSynthesized] = useState(false);
  const [summary, setSummary] = useState<ConfigParsedSummary | null>(null);
  const [loading, setLoading] = useState(false);
  const [validating, setValidating] = useState(false);
  const [saving, setSaving] = useState(false);
  const [validation, setValidation] = useState<ConfigValidateResponse | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const loadYaml = useCallback(async () => {
    setLoading(true);
    setErrorMsg(null);
    setValidation(null);
    try {
      const resp = await fetch('/api/config/yaml');
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      }
      const typed = data as ConfigYamlResponse;
      setYamlText(typed.yaml);
      setHash(typed.hash);
      setIsSynthesized(Boolean(typed.is_synthesized));
      setSummary(typed.parsed_summary);
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Impossible de charger config.yaml.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (open) {
      void loadYaml();
    }
  }, [open, loadYaml]);

  if (!open) return null;

  const runValidate = async (candidate: string) => {
    setValidating(true);
    setErrorMsg(null);
    try {
      const resp = await fetch('/api/config/validate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ yaml: candidate }),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      }
      const res = data as ConfigValidateResponse;
      setValidation(res);
      if (res.parsed_summary) {
        setSummary(res.parsed_summary);
      }
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Erreur lors de la validation YAML.');
    } finally {
      setValidating(false);
    }
  };

  const handleSave = async () => {
    setSaving(true);
    setErrorMsg(null);
    try {
      const resp = await fetch('/api/config/yaml', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ yaml: yamlText }),
      });
      const data = (await resp.json().catch(() => ({}))) as ConfigSaveResponse;
      if (!resp.ok || !data.ok) {
        setValidation({
          valid: false,
          errors: data.errors || [data.detail || `Erreur HTTP ${resp.status}`],
          warnings: data.warnings || [],
          parsed_summary: null,
        });
        throw new Error(data.detail || 'Validation YAML refusée.');
      }
      if (data.hash) setHash(data.hash);
      if (data.parsed_summary) setSummary(data.parsed_summary);
      setIsSynthesized(false);
      setValidation({
        valid: true,
        errors: [],
        warnings: data.warnings || [],
        parsed_summary: data.parsed_summary || null,
      });
      onSaved(data.message || 'config.yaml enregistré et rechargé à chaud.');
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Échec de sauvegarde YAML.');
    } finally {
      setSaving(false);
    }
  };

  const handleDownload = async () => {
    try {
      const resp = await fetch('/api/config/export');
      const content = resp.ok ? await resp.text() : yamlText;
      const blob = new Blob([content], { type: 'application/x-yaml;charset=utf-8' });
      const blobUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = 'config.yaml';
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(blobUrl);
    } catch {
      setErrorMsg('Impossible de télécharger config.yaml.');
    }
  };

  const handleImportFile = async (file: File | null) => {
    if (!file) return;
    try {
      const text = await file.text();
      setYamlText(text);
      await runValidate(text);
    } catch {
      setErrorMsg('Impossible de lire le fichier YAML importé.');
    }
  };

  const handleEditorKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Tab') {
      e.preventDefault();
      const target = e.currentTarget;
      const start = target.selectionStart;
      const end = target.selectionEnd;
      const next = yamlText.slice(0, start) + '  ' + yamlText.slice(end);
      setYamlText(next);
      window.requestAnimationFrame(() => {
        target.selectionStart = start + 2;
        target.selectionEnd = start + 2;
      });
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/60 p-0 backdrop-blur-md sm:items-center sm:p-4"
      onClick={onClose}
    >
      <div
        className="ios-sheet safe-bottom-sheet flex max-h-[94dvh] w-full max-w-4xl flex-col overflow-hidden rounded-t-[32px] text-slate-900 dark:text-slate-100 sm:rounded-3xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="shrink-0 border-b border-slate-200/80 px-5 pb-4 pt-3 dark:border-white/10 sm:px-6 sm:pt-5">
          <div className="mb-3 flex justify-center sm:hidden">
            <div className="ios-grabber" />
          </div>

          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border border-indigo-500/30 bg-indigo-500/15 text-indigo-600 dark:text-indigo-300">
                <FileCode2 className="h-5 w-5" />
              </div>
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <h2 className="text-base font-semibold text-slate-900 dark:text-white">
                    Éditeur déclaratif config.yaml
                  </h2>
                  {hash && (
                    <span className="rounded-full border border-slate-300/80 bg-white/70 px-2 py-0.5 font-mono text-[10px] text-slate-600 dark:border-white/15 dark:bg-white/[0.06] dark:text-slate-300">
                      sha256:{hash.slice(0, 10)}
                    </span>
                  )}
                  {isSynthesized && (
                    <span className="rounded-full border border-amber-500/35 bg-amber-500/15 px-2 py-0.5 text-[10px] font-medium text-amber-700 dark:text-amber-200">
                      Synthétisé (.env/services)
                    </span>
                  )}
                </div>
                <p className="text-xs text-slate-500 dark:text-slate-400">
                  Les secrets littéraux sont masqués (<code className="font-mono">********</code>) et préservés automatiquement lors de la sauvegarde.
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

          {summary && (
            <div className="mt-3 flex flex-wrap gap-1.5 text-[11px]">
              <span className="liquid-pill rounded-full px-2.5 py-0.5 text-slate-700 dark:text-slate-200">
                Serveur : <strong>{summary.server_name}</strong>
              </span>
              <span className="liquid-pill rounded-full px-2.5 py-0.5 text-slate-700 dark:text-slate-200">
                Nœud PVE : <strong>{summary.proxmox_node || '—'}</strong>
              </span>
              <span className="liquid-pill rounded-full px-2.5 py-0.5 text-slate-700 dark:text-slate-200">
                Catégories : <strong>{summary.categories_count}</strong>
              </span>
              <span className="liquid-pill rounded-full px-2.5 py-0.5 text-slate-700 dark:text-slate-200">
                Services perso : <strong>{summary.custom_services_count}</strong>
              </span>
              <span className="liquid-pill rounded-full px-2.5 py-0.5 text-slate-700 dark:text-slate-200">
                Webhooks : <strong>{summary.webhooks_count}</strong>
              </span>
              <span className="liquid-pill rounded-full px-2.5 py-0.5 text-slate-700 dark:text-slate-200">
                Jetons API : <strong>{summary.api_tokens_count}</strong>
              </span>
            </div>
          )}
        </div>

        <div className="flex flex-1 flex-col gap-3 overflow-y-auto p-5 sm:p-6">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex flex-wrap items-center gap-2">
              <input
                ref={fileInputRef}
                type="file"
                accept=".yaml,.yml,text/yaml"
                className="hidden"
                onChange={(e) => {
                  const f = e.target.files?.[0] || null;
                  void handleImportFile(f);
                  e.target.value = '';
                }}
              />
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                className="liquid-pill inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium text-slate-700 hover:text-slate-900 dark:text-slate-200 dark:hover:text-white"
              >
                <Upload className="h-3.5 w-3.5 text-cyan-500" />
                Importer .yaml
              </button>
              <button
                type="button"
                onClick={() => void handleDownload()}
                className="liquid-pill inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium text-slate-700 hover:text-slate-900 dark:text-slate-200 dark:hover:text-white"
              >
                <Download className="h-3.5 w-3.5 text-indigo-500" />
                Télécharger .yaml
              </button>
              <button
                type="button"
                onClick={() => void loadYaml()}
                className="liquid-pill inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium text-slate-700 hover:text-slate-900 dark:text-slate-200 dark:hover:text-white"
              >
                <RefreshCw className="h-3.5 w-3.5" />
                Recharger
              </button>
            </div>

            <button
              type="button"
              disabled={validating || loading}
              onClick={() => void runValidate(yamlText)}
              className="inline-flex items-center gap-1.5 rounded-full border border-cyan-500/35 bg-cyan-500/15 px-3.5 py-1.5 text-xs font-semibold text-cyan-800 hover:bg-cyan-500/25 disabled:opacity-50 dark:text-cyan-200"
            >
              {validating ? (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              ) : (
                <ShieldCheck className="h-3.5 w-3.5" />
              )}
              Valider le schéma
            </button>
          </div>

          {errorMsg && (
            <div className="flex items-start gap-2 rounded-2xl border border-rose-500/35 bg-rose-500/10 p-3 text-xs text-rose-700 dark:text-rose-200">
              <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>{errorMsg}</span>
            </div>
          )}

          {validation && (
            <div
              className={`space-y-1.5 rounded-2xl border p-3 text-xs ${
                validation.valid
                  ? 'border-emerald-500/35 bg-emerald-500/10 text-emerald-800 dark:text-emerald-200'
                  : 'border-rose-500/35 bg-rose-500/10 text-rose-800 dark:text-rose-200'
              }`}
            >
              <div className="flex items-center gap-2 font-semibold">
                {validation.valid ? (
                  <>
                    <CheckCircle2 className="h-4 w-4 text-emerald-500" />
                    Schéma YAML valide — prêt pour le rechargement à chaud.
                  </>
                ) : (
                  <>
                    <AlertCircle className="h-4 w-4 text-rose-500" />
                    {validation.errors.length} erreur(s) détectée(s) :
                  </>
                )}
              </div>
              {validation.errors.length > 0 && (
                <ul className="list-inside list-disc space-y-0.5 font-mono text-[11px]">
                  {validation.errors.map((err, idx) => (
                    <li key={idx}>{err}</li>
                  ))}
                </ul>
              )}
              {validation.warnings.length > 0 && (
                <div className="mt-1 flex items-start gap-1.5 text-amber-700 dark:text-amber-300">
                  <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                  <ul className="list-inside list-disc space-y-0.5 text-[11px]">
                    {validation.warnings.map((w, idx) => (
                      <li key={idx}>{w}</li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          )}

          {loading ? (
            <div className="flex h-80 items-center justify-center gap-2 text-sm text-slate-500 dark:text-slate-400">
              <Loader2 className="h-4 w-4 animate-spin text-cyan-500" />
              Chargement de config.yaml…
            </div>
          ) : (
            <textarea
              spellCheck={false}
              value={yamlText}
              onChange={(e) => setYamlText(e.target.value)}
              onKeyDown={handleEditorKeyDown}
              aria-label="Contenu config.yaml"
              className="min-h-[340px] w-full flex-1 resize-y rounded-2xl border border-slate-300/80 bg-slate-900 p-4 font-mono text-xs leading-relaxed text-slate-100 shadow-inner focus:border-cyan-400/60 focus:outline-none focus:ring-2 focus:ring-cyan-400/20 dark:border-white/15 dark:bg-slate-950/90"
            />
          )}
        </div>

        <div className="flex shrink-0 items-center justify-between gap-2 border-t border-slate-200/80 px-5 py-3.5 dark:border-white/10 sm:px-6">
          <button
            type="button"
            onClick={onClose}
            disabled={saving}
            className="liquid-pill rounded-2xl px-4 py-2 text-xs font-medium text-slate-700 dark:text-slate-200"
          >
            Fermer
          </button>
          <button
            type="button"
            disabled={saving || loading || !yamlText.trim()}
            onClick={() => void handleSave()}
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
                Enregistrer &amp; Recharger à chaud
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
}

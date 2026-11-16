import { useEffect, useRef, useState, type FormEvent } from 'react';
import {
  AlertTriangle,
  Ban,
  Check,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  Copy,
  Eye,
  EyeOff,
  FolderOpen,
  KeyRound,
  Monitor,
  RefreshCw,
  Settings2,
  Shield,
  ShieldAlert,
  Sparkles,
  Trash2,
  UserCheck,
  UserPlus,
  Users,
  X,
} from 'lucide-react';
import type { JellyfinLibrary, UnifiedUser, UsersOverview } from '../types';

interface ToastPayload {
  type: 'success' | 'error';
  message: string;
}

interface UsersSectionProps {
  overview: UsersOverview | null;
  search: string;
  onRefreshUsers: () => Promise<void>;
  onToast: (toast: ToastPayload) => void;
}

type UserFilter = 'all' | 'active' | 'disabled' | 'unsynced' | 'manual';

const SESSION_LIMIT_OPTIONS = [0, 1, 2, 3, 4] as const;

const FILTER_TABS: ReadonlyArray<{
  id: UserFilter;
  label: string;
  matches: (u: UnifiedUser) => boolean;
}> = [
  { id: 'all', label: 'Tous', matches: () => true },
  { id: 'active', label: 'Actifs', matches: (u) => !u.is_disabled },
  { id: 'disabled', label: 'Suspendus', matches: (u) => u.is_disabled },
  { id: 'unsynced', label: 'À synchroniser', matches: (u) => !u.in_jellyseerr },
  {
    id: 'manual',
    label: 'Validation manuelle',
    matches: (u) => u.in_jellyseerr && !u.auto_approve,
  },
];

function formatRelativeDate(iso: string | null): string {
  if (!iso) return 'Jamais';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '—';
  const diffHours = Math.floor((Date.now() - date.getTime()) / 3_600_000);
  if (diffHours < 1) return "À l'instant";
  if (diffHours < 24) return `Il y a ${diffHours}h`;
  const diffDays = Math.floor(diffHours / 24);
  if (diffDays < 30) return `Il y a ${diffDays}j`;
  return date.toLocaleDateString('fr-FR');
}

function generatePassword(length = 12): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$';
  const bytes = new Uint32Array(length);
  window.crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => chars[b % chars.length]).join('');
}

function isOwnerUser(user: UnifiedUser): boolean {
  return Boolean(user.is_protected) || user.jellyseerr_id === 1;
}

function formatLibrarySummary(user: UnifiedUser, totalLibraries: number): string {
  if (user.enable_all_folders) return 'Toutes biblio.';
  return totalLibraries > 0
    ? `${user.enabled_folders.length}/${totalLibraries} biblio.`
    : `${user.enabled_folders.length} biblio.`;
}

function formatScreenLimit(maxActiveSessions: number): string {
  return `max ${maxActiveSessions} écran${maxActiveSessions > 1 ? 's' : ''}`;
}

function toggleIdInList(list: string[], id: string): string[] {
  return list.includes(id) ? list.filter((item) => item !== id) : [...list, id];
}

async function apiJson<T = Record<string, unknown>>(
  url: string,
  init?: RequestInit
): Promise<T> {
  const resp = await fetch(url, init);
  const data = (await resp.json().catch(() => ({}))) as T & { detail?: string };
  if (!resp.ok) {
    throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
  }
  return data;
}

interface ToggleRowProps {
  label: string;
  description?: string;
  checked: boolean;
  disabled?: boolean;
  tone?: 'cyan' | 'rose';
  badge?: string;
  onChange: (checked: boolean) => void;
}

function ToggleRow({
  label,
  description,
  checked,
  disabled = false,
  tone = 'cyan',
  badge,
  onChange,
}: ToggleRowProps) {
  const trackActiveClass =
    tone === 'rose'
      ? 'border-rose-500/60 bg-rose-500/80'
      : 'border-cyan-400/60 bg-cyan-500';

  return (
    <div
      className={`flex items-center justify-between gap-3 rounded-xl border border-slate-800/80 bg-slate-950/60 px-3 py-2.5 ${
        disabled ? 'opacity-65' : ''
      }`}
    >
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="text-xs font-medium text-slate-200">{label}</span>
          {badge && (
            <span className="rounded border border-slate-700 bg-slate-800/90 px-1.5 py-0.5 text-[10px] font-medium text-slate-400">
              {badge}
            </span>
          )}
        </div>
        {description && (
          <p className="mt-0.5 text-[11px] text-slate-500">{description}</p>
        )}
      </div>

      <button
        type="button"
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={`relative inline-flex h-5 w-9 shrink-0 items-center rounded-full border transition focus:outline-none focus:ring-2 focus:ring-cyan-500/30 disabled:cursor-not-allowed ${
          checked
            ? trackActiveClass
            : 'border-slate-700 bg-slate-800'
        }`}
      >
        <span
          className={`inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow transition ${
            checked ? 'translate-x-4' : 'translate-x-0.5'
          }`}
        />
      </button>
    </div>
  );
}

interface SessionLimitSelectProps {
  value: number;
  onChange: (value: number) => void;
}

function SessionLimitSelect({ value, onChange }: SessionLimitSelectProps) {
  const hasCustomValue =
    value > 0 && !SESSION_LIMIT_OPTIONS.includes(value as 0 | 1 | 2 | 3 | 4);

  return (
    <div className="flex items-center justify-between gap-3 rounded-xl border border-slate-800/80 bg-slate-950/60 px-3 py-2.5">
      <label className="flex items-center gap-2 text-xs font-medium text-slate-200">
        <Monitor className="h-3.5 w-3.5 text-cyan-400" />
        Limite d&apos;écrans simultanés
      </label>
      <select
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="rounded-lg border border-slate-700 bg-slate-900 px-2.5 py-1 text-xs font-medium text-slate-100 focus:border-cyan-500/50 focus:outline-none focus:ring-2 focus:ring-cyan-500/20"
      >
        <option value={0}>Illimité (0)</option>
        <option value={1}>1 écran</option>
        <option value={2}>2 écrans</option>
        <option value={3}>3 écrans</option>
        <option value={4}>4 écrans</option>
        {hasCustomValue && <option value={value}>{value} écrans</option>}
      </select>
    </div>
  );
}

interface LibraryAccessPickerProps {
  libraries: JellyfinLibrary[];
  enableAll: boolean;
  selectedIds: string[];
  onToggleAll: (enableAll: boolean) => void;
  onToggleLibrary: (id: string) => void;
}

function LibraryAccessPicker({
  libraries,
  enableAll,
  selectedIds,
  onToggleAll,
  onToggleLibrary,
}: LibraryAccessPickerProps) {
  return (
    <div className="space-y-2.5">
      <ToggleRow
        label="Accès à toutes les médiathèques"
        description={
          enableAll
            ? 'Accès complet à toutes les bibliothèques actuelles et futures'
            : `${selectedIds.length} médiathèque(s) sélectionnée(s)`
        }
        checked={enableAll}
        onChange={onToggleAll}
      />

      {!enableAll && (
        <div className="rounded-xl border border-slate-800/80 bg-slate-950/50 p-3">
          {libraries.length === 0 ? (
            <p className="text-xs text-slate-500">
              Aucune médiathèque détectée sur Jellyfin.
            </p>
          ) : (
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              {libraries.map((lib) => {
                const checked = selectedIds.includes(lib.id);
                return (
                  <label
                    key={lib.id}
                    className={`flex cursor-pointer items-center gap-2 rounded-lg border px-2.5 py-1.5 text-xs transition ${
                      checked
                        ? 'border-cyan-500/40 bg-cyan-500/10 text-cyan-100'
                        : 'border-slate-800 bg-slate-900/70 text-slate-300 hover:border-slate-700'
                    }`}
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      onChange={() => onToggleLibrary(lib.id)}
                      className="h-3.5 w-3.5 rounded border-slate-700 bg-slate-900 text-cyan-500 focus:ring-cyan-500/30"
                    />
                    <span className="truncate">{lib.name}</span>
                  </label>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

interface ManageUserModalProps {
  user: UnifiedUser;
  libraries: JellyfinLibrary[];
  syncing: boolean;
  onSyncUser: (jellyfinId: string) => Promise<void>;
  onClose: () => void;
  onRefreshUsers: () => Promise<void>;
  onToast: (toast: ToastPayload) => void;
}

function ManageUserModal({
  user,
  libraries,
  syncing,
  onSyncUser,
  onClose,
  onRefreshUsers,
  onToast,
}: ManageUserModalProps) {
  const isOwner = isOwnerUser(user);

  const [isDisabled, setIsDisabled] = useState(user.is_disabled);
  const [enableDownloading, setEnableDownloading] = useState(
    user.enable_downloading
  );
  const [isAdmin, setIsAdmin] = useState(user.is_admin);
  const [maxActiveSessions, setMaxActiveSessions] = useState(
    user.max_active_sessions
  );
  const [enableAllFolders, setEnableAllFolders] = useState(
    user.enable_all_folders
  );
  const [enabledFolders, setEnabledFolders] = useState<string[]>(
    user.enabled_folders
  );
  const [autoApprove, setAutoApprove] = useState(user.auto_approve);

  const [saving, setSaving] = useState(false);
  const [newPassword, setNewPassword] = useState('');
  const [showNewPassword, setShowNewPassword] = useState(false);
  const [passwordBusy, setPasswordBusy] = useState(false);
  const [copiedPassword, setCopiedPassword] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);

  const prevUserIdRef = useRef(user.jellyfin_id);
  const prevInJellyseerrRef = useRef(user.in_jellyseerr);

  useEffect(() => {
    if (prevUserIdRef.current !== user.jellyfin_id) {
      prevUserIdRef.current = user.jellyfin_id;
      prevInJellyseerrRef.current = user.in_jellyseerr;
      setIsDisabled(user.is_disabled);
      setEnableDownloading(user.enable_downloading);
      setIsAdmin(user.is_admin);
      setMaxActiveSessions(user.max_active_sessions);
      setEnableAllFolders(user.enable_all_folders);
      setEnabledFolders(user.enabled_folders);
      setAutoApprove(user.auto_approve);
      setNewPassword('');
      setShowNewPassword(false);
      setConfirmDelete(false);
      return;
    }

    if (!prevInJellyseerrRef.current && user.in_jellyseerr) {
      prevInJellyseerrRef.current = true;
      setAutoApprove(user.auto_approve);
    }
  }, [user]);

  const busy = saving || passwordBusy || deleting || syncing;

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !busy) {
        onClose();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [busy, onClose]);

  const handleSaveSettings = async (e: FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      const payload: Record<string, unknown> = {
        enable_all_folders: enableAllFolders,
        enable_downloading: enableDownloading,
        max_active_sessions: maxActiveSessions,
      };
      if (!enableAllFolders) {
        payload.enabled_folders = enabledFolders;
      }
      if (!isOwner) {
        payload.is_disabled = isDisabled;
        payload.is_admin = isAdmin;
        if (user.in_jellyseerr) {
          payload.auto_approve = autoApprove;
        }
      }

      await apiJson(`/api/users/${encodeURIComponent(user.jellyfin_id)}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      onToast({
        type: 'success',
        message: `Paramètres de "${user.name}" enregistrés.`,
      });
      await onRefreshUsers();
      onClose();
    } catch (err) {
      onToast({
        type: 'error',
        message:
          err instanceof Error
            ? err.message
            : 'Échec de la mise à jour du compte.',
      });
    } finally {
      setSaving(false);
    }
  };

  const handleResetPassword = async () => {
    if (newPassword.length < 4) return;
    setPasswordBusy(true);
    try {
      await apiJson(
        `/api/users/${encodeURIComponent(user.jellyfin_id)}/password`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ new_password: newPassword }),
        }
      );
      onToast({
        type: 'success',
        message: `Mot de passe Jellyfin de "${user.name}" modifié.`,
      });
      setNewPassword('');
      setShowNewPassword(false);
    } catch (err) {
      onToast({
        type: 'error',
        message:
          err instanceof Error
            ? err.message
            : 'Échec de la modification du mot de passe.',
      });
    } finally {
      setPasswordBusy(false);
    }
  };

  const handleDeleteUser = async () => {
    if (isOwner) return;
    setDeleting(true);
    try {
      await apiJson(`/api/users/${encodeURIComponent(user.jellyfin_id)}`, {
        method: 'DELETE',
      });
      onToast({
        type: 'success',
        message: `Compte "${user.name}" supprimé de Jellyfin et Jellyseerr.`,
      });
      await onRefreshUsers();
      onClose();
    } catch (err) {
      onToast({
        type: 'error',
        message:
          err instanceof Error
            ? err.message
            : 'Échec de la suppression du compte.',
      });
    } finally {
      setDeleting(false);
    }
  };

  const handleCopyPassword = async () => {
    if (!newPassword) return;
    try {
      await navigator.clipboard.writeText(newPassword);
      setCopiedPassword(true);
      window.setTimeout(() => setCopiedPassword(false), 1800);
    } catch {
      // Clipboard API may be unavailable in insecure contexts.
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/70 p-0 backdrop-blur-md sm:items-center sm:p-4">
      <div className="ios-sheet safe-bottom-sheet max-h-[92dvh] w-full max-w-lg overflow-y-auto rounded-t-[32px] p-5 sm:rounded-3xl sm:p-6">
        <div className="mb-4 flex justify-center sm:hidden">
          <div className="ios-grabber" />
        </div>
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <div
              className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl border text-sm font-semibold ${
                isDisabled
                  ? 'border-rose-500/30 bg-rose-500/10 text-rose-300'
                  : isAdmin
                    ? 'border-cyan-500/30 bg-cyan-500/15 text-cyan-300'
                    : 'border-white/15 bg-white/10 text-slate-200'
              }`}
            >
              {user.name.slice(0, 2).toUpperCase()}
            </div>
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <h3 className="text-base font-semibold text-slate-100">
                  {user.name}
                </h3>
                {isAdmin && (
                  <span className="rounded bg-cyan-500/15 px-1.5 py-0.5 text-[10px] font-medium text-cyan-300">
                    Admin
                  </span>
                )}
                {isDisabled && (
                  <span className="rounded bg-rose-500/15 px-1.5 py-0.5 text-[10px] font-medium text-rose-300">
                    Suspendu
                  </span>
                )}
                {isOwner && (
                  <span className="rounded border border-amber-500/30 bg-amber-500/10 px-1.5 py-0.5 text-[10px] font-medium text-amber-300">
                    Propriétaire
                  </span>
                )}
              </div>
              <p className="text-xs text-slate-400">
                Dernière activité : {formatRelativeDate(user.last_activity)}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={busy}
            className="rounded-lg p-1 text-slate-400 hover:bg-slate-800 hover:text-slate-200 disabled:opacity-50"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <form onSubmit={handleSaveSettings} className="mt-5 space-y-5">
          <div className="space-y-2">
            <h4 className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-slate-400">
              <Shield className="h-3.5 w-3.5 text-cyan-400" />
              Accès &amp; Sécurité Jellyfin
            </h4>
            <div className="space-y-2">
              <ToggleRow
                label="Suspendre ce compte"
                description="Bloque la connexion et la lecture sur Jellyfin"
                checked={isDisabled}
                disabled={isOwner}
                tone="rose"
                badge={isOwner ? 'Protégé' : undefined}
                onChange={setIsDisabled}
              />
              <ToggleRow
                label="Autoriser le téléchargement hors-ligne"
                checked={enableDownloading}
                onChange={setEnableDownloading}
              />
              <ToggleRow
                label="Administrateur Jellyfin"
                checked={isAdmin}
                disabled={isOwner}
                badge={isOwner ? 'Protégé' : undefined}
                onChange={setIsAdmin}
              />
              <SessionLimitSelect
                value={maxActiveSessions}
                onChange={setMaxActiveSessions}
              />
            </div>
          </div>

          <div className="space-y-2">
            <h4 className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-slate-400">
              <FolderOpen className="h-3.5 w-3.5 text-cyan-400" />
              Accès aux Médiathèques
            </h4>
            <LibraryAccessPicker
              libraries={libraries}
              enableAll={enableAllFolders}
              selectedIds={enabledFolders}
              onToggleAll={setEnableAllFolders}
              onToggleLibrary={(id) =>
                setEnabledFolders((prev) => toggleIdInList(prev, id))
              }
            />
          </div>

          <div className="space-y-2">
            <h4 className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-slate-400">
              <UserCheck className="h-3.5 w-3.5 text-cyan-400" />
              Permissions Jellyseerr
            </h4>
            {user.in_jellyseerr ? (
              <ToggleRow
                label="Auto-approuver ses demandes de films/séries"
                description={
                  isOwner
                    ? 'Le compte propriétaire dispose toujours de l’auto-approbation'
                    : undefined
                }
                checked={isOwner ? true : autoApprove}
                disabled={isOwner}
                badge={isOwner ? 'Protégé' : undefined}
                onChange={setAutoApprove}
              />
            ) : (
              <div className="flex flex-col gap-2.5 rounded-xl border border-amber-500/30 bg-amber-500/10 p-3 sm:flex-row sm:items-center sm:justify-between">
                <span className="text-xs text-amber-200">
                  Cet utilisateur n&apos;est pas encore importé dans Jellyseerr.
                </span>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => onSyncUser(user.jellyfin_id)}
                  className="inline-flex shrink-0 items-center justify-center gap-1.5 rounded-lg border border-amber-400/40 bg-amber-500/20 px-3 py-1.5 text-xs font-medium text-amber-200 transition hover:bg-amber-500/30 disabled:opacity-50"
                >
                  <RefreshCw
                    className={`h-3.5 w-3.5 ${syncing ? 'animate-spin' : ''}`}
                  />
                  Importer dans Jellyseerr maintenant
                </button>
              </div>
            )}
          </div>

          <div className="flex items-center justify-end gap-2.5 border-t border-slate-800/80 pt-3">
            <button
              type="button"
              onClick={onClose}
              disabled={busy}
              className="rounded-xl border border-slate-700 bg-slate-800 px-4 py-2 text-xs font-medium text-slate-200 hover:bg-slate-700 disabled:opacity-50"
            >
              Fermer
            </button>
            <button
              type="submit"
              disabled={busy}
              className="rounded-xl bg-cyan-600 px-4 py-2 text-xs font-semibold text-white transition hover:bg-cyan-500 disabled:opacity-50"
            >
              {saving ? 'Enregistrement…' : 'Enregistrer les modifications'}
            </button>
          </div>
        </form>

        <div className="mt-5 space-y-2.5 border-t border-slate-800 pt-5">
          <div className="flex items-center justify-between">
            <h4 className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-slate-400">
              <KeyRound className="h-3.5 w-3.5 text-cyan-400" />
              Mot de passe Jellyfin
            </h4>
            <div className="flex items-center gap-3">
              {newPassword && (
                <button
                  type="button"
                  onClick={handleCopyPassword}
                  className="inline-flex items-center gap-1 text-[11px] font-medium text-slate-300 hover:text-white"
                >
                  {copiedPassword ? (
                    <>
                      <Check className="h-3 w-3 text-emerald-400" />
                      Copié
                    </>
                  ) : (
                    <>
                      <Copy className="h-3 w-3" />
                      Copier
                    </>
                  )}
                </button>
              )}
              <button
                type="button"
                onClick={() => {
                  setNewPassword(generatePassword());
                  setShowNewPassword(true);
                }}
                className="inline-flex items-center gap-1 text-[11px] font-medium text-cyan-400 hover:text-cyan-300"
              >
                <Sparkles className="h-3 w-3" />
                Générer
              </button>
            </div>
          </div>

          <div className="flex flex-col gap-2 sm:flex-row">
            <div className="relative flex-1">
              <input
                type={showNewPassword ? 'text' : 'password'}
                minLength={4}
                maxLength={128}
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                placeholder="Nouveau mot de passe (min. 4 car.)"
                className="w-full rounded-xl border border-slate-800 bg-slate-950 py-2 pl-3 pr-9 text-xs text-slate-100 placeholder-slate-500 focus:border-cyan-500/50 focus:outline-none focus:ring-2 focus:ring-cyan-500/20"
              />
              <button
                type="button"
                onClick={() => setShowNewPassword((v) => !v)}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-300"
              >
                {showNewPassword ? (
                  <EyeOff className="h-3.5 w-3.5" />
                ) : (
                  <Eye className="h-3.5 w-3.5" />
                )}
              </button>
            </div>
            <button
              type="button"
              disabled={busy || newPassword.length < 4}
              onClick={handleResetPassword}
              className="shrink-0 rounded-xl border border-cyan-500/40 bg-cyan-500/15 px-3.5 py-2 text-xs font-medium text-cyan-200 transition hover:bg-cyan-500/25 disabled:opacity-40"
            >
              {passwordBusy ? 'Modification…' : 'Modifier le mot de passe'}
            </button>
          </div>
        </div>

        {!isOwner && (
          <div className="mt-5 space-y-2.5 border-t border-slate-800 pt-5">
            <h4 className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-rose-400">
              <AlertTriangle className="h-3.5 w-3.5" />
              Zone de danger
            </h4>

            {!confirmDelete ? (
              <button
                type="button"
                disabled={busy}
                onClick={() => setConfirmDelete(true)}
                className="inline-flex w-full items-center justify-center gap-2 rounded-xl border border-rose-500/35 bg-rose-500/10 px-4 py-2 text-xs font-medium text-rose-300 transition hover:bg-rose-500/20 disabled:opacity-50"
              >
                <Trash2 className="h-3.5 w-3.5" />
                Supprimer le compte (Jellyfin + Jellyseerr)
              </button>
            ) : (
              <div className="space-y-3 rounded-xl border border-rose-500/40 bg-rose-950/30 p-3">
                <p className="text-xs text-rose-200">
                  Confirmer la suppression définitive du compte{' '}
                  <span className="font-semibold">{user.name}</span> sur Jellyfin
                  et Jellyseerr ? Cette action est irréversible.
                </p>
                <div className="flex items-center justify-end gap-2">
                  <button
                    type="button"
                    disabled={deleting}
                    onClick={() => setConfirmDelete(false)}
                    className="rounded-lg border border-slate-700 bg-slate-800 px-3 py-1.5 text-xs font-medium text-slate-200 hover:bg-slate-700 disabled:opacity-50"
                  >
                    Annuler
                  </button>
                  <button
                    type="button"
                    disabled={deleting}
                    onClick={handleDeleteUser}
                    className="inline-flex items-center gap-1.5 rounded-lg bg-rose-600 px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-rose-500 disabled:opacity-50"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                    {deleting ? 'Suppression…' : 'Confirmer la suppression'}
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

interface CreateUserModalProps {
  libraries: JellyfinLibrary[];
  onClose: () => void;
  onRefreshUsers: () => Promise<void>;
  onToast: (toast: ToastPayload) => void;
}

function CreateUserModal({
  libraries,
  onClose,
  onRefreshUsers,
  onToast,
}: CreateUserModalProps) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [syncJellyseerr, setSyncJellyseerr] = useState(true);
  const [autoApprove, setAutoApprove] = useState(true);
  const [enableDownloading, setEnableDownloading] = useState(true);
  const [maxActiveSessions, setMaxActiveSessions] = useState(0);
  const [enableAllFolders, setEnableAllFolders] = useState(true);
  const [enabledFolders, setEnabledFolders] = useState<string[]>([]);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !submitting) {
        onClose();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [submitting, onClose]);

  const handleCreateUser = async (e: FormEvent) => {
    e.preventDefault();
    if (!username.trim() || password.length < 4) return;
    setSubmitting(true);
    try {
      const data = await apiJson<{
        username: string;
        synced_jellyseerr: boolean;
      }>('/api/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username: username.trim(),
          password,
          sync_jellyseerr: syncJellyseerr,
          auto_approve: autoApprove,
          enable_all_folders: enableAllFolders,
          enabled_folders: enableAllFolders ? [] : enabledFolders,
          enable_downloading: enableDownloading,
          max_active_sessions: maxActiveSessions,
        }),
      });
      onToast({
        type: 'success',
        message: data.synced_jellyseerr
          ? `Utilisateur "${data.username}" créé sur Jellyfin et synchronisé sur Jellyseerr !`
          : `Utilisateur "${data.username}" créé sur Jellyfin.`,
      });
      await onRefreshUsers();
      onClose();
    } catch (err) {
      onToast({
        type: 'error',
        message: err instanceof Error ? err.message : 'Échec de la création.',
      });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/70 p-0 backdrop-blur-md sm:items-center sm:p-4">
      <div className="ios-sheet safe-bottom-sheet max-h-[92dvh] w-full max-w-lg overflow-y-auto rounded-t-[32px] p-5 sm:rounded-3xl sm:p-6">
        <div className="mb-4 flex justify-center sm:hidden">
          <div className="ios-grabber" />
        </div>
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-2xl border border-cyan-500/30 bg-cyan-500/10 text-cyan-400">
              <UserPlus className="h-5 w-5" />
            </div>
            <div>
              <h3 className="text-base font-semibold text-white">
                Nouvel utilisateur média
              </h3>
              <p className="text-xs text-slate-400">
                Création Jellyfin + synchronisation Jellyseerr
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            disabled={submitting}
            className="rounded-lg p-1 text-slate-400 hover:bg-slate-800 hover:text-slate-200 disabled:opacity-50"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <form onSubmit={handleCreateUser} className="mt-5 space-y-4">
          <div>
            <label className="mb-1.5 block text-xs font-medium text-slate-300">
              Nom d’utilisateur
            </label>
            <input
              type="text"
              required
              minLength={2}
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="ex: lucas"
              className="w-full rounded-xl border border-slate-800 bg-slate-950 px-3.5 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-cyan-500/50 focus:outline-none focus:ring-2 focus:ring-cyan-500/20"
            />
          </div>

          <div>
            <div className="mb-1.5 flex items-center justify-between">
              <label className="text-xs font-medium text-slate-300">
                Mot de passe (min. 4 caractères)
              </label>
              <button
                type="button"
                onClick={() => {
                  setPassword(generatePassword());
                  setShowPassword(true);
                }}
                className="inline-flex items-center gap-1 text-[11px] font-medium text-cyan-400 hover:text-cyan-300"
              >
                <Sparkles className="h-3 w-3" />
                Générer
              </button>
            </div>
            <div className="relative">
              <input
                type={showPassword ? 'text' : 'password'}
                required
                minLength={4}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Mot de passe Jellyfin & Jellyseerr"
                className="w-full rounded-xl border border-slate-800 bg-slate-950 py-2 pl-3.5 pr-10 text-sm text-slate-100 placeholder-slate-500 focus:border-cyan-500/50 focus:outline-none focus:ring-2 focus:ring-cyan-500/20"
              />
              <button
                type="button"
                onClick={() => setShowPassword((v) => !v)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-300"
              >
                {showPassword ? (
                  <EyeOff className="h-4 w-4" />
                ) : (
                  <Eye className="h-4 w-4" />
                )}
              </button>
            </div>
          </div>

          <div className="space-y-2">
            <h4 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              Options Jellyfin
            </h4>
            <ToggleRow
              label="Autoriser le téléchargement hors-ligne"
              checked={enableDownloading}
              onChange={setEnableDownloading}
            />
            <SessionLimitSelect
              value={maxActiveSessions}
              onChange={setMaxActiveSessions}
            />
            <LibraryAccessPicker
              libraries={libraries}
              enableAll={enableAllFolders}
              selectedIds={enabledFolders}
              onToggleAll={setEnableAllFolders}
              onToggleLibrary={(id) =>
                setEnabledFolders((prev) => toggleIdInList(prev, id))
              }
            />
          </div>

          <div className="space-y-2">
            <h4 className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              Options Jellyseerr
            </h4>
            <ToggleRow
              label="Importer automatiquement dans Jellyseerr"
              checked={syncJellyseerr}
              onChange={setSyncJellyseerr}
            />
            {syncJellyseerr && (
              <ToggleRow
                label="Auto-approuver ses demandes films/séries"
                checked={autoApprove}
                onChange={setAutoApprove}
              />
            )}
          </div>

          <div className="flex items-center justify-end gap-2.5 pt-1">
            <button
              type="button"
              onClick={onClose}
              disabled={submitting}
              className="rounded-xl border border-slate-700 bg-slate-800 px-4 py-2 text-sm font-medium text-slate-200 hover:bg-slate-700 disabled:opacity-50"
            >
              Annuler
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="rounded-xl bg-cyan-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-cyan-500 disabled:opacity-50"
            >
              {submitting ? 'Création…' : 'Créer et synchroniser'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export function UsersSection({
  overview,
  search,
  onRefreshUsers,
  onToast,
}: UsersSectionProps) {
  const [expanded, setExpanded] = useState(true);
  const [activeFilter, setActiveFilter] = useState<UserFilter>('all');
  const [createModalOpen, setCreateModalOpen] = useState(false);
  const [managedUserId, setManagedUserId] = useState<string | null>(null);
  const [syncingId, setSyncingId] = useState<string | null>(null);

  if (!overview) {
    return (
      <section className="liquid-glass rounded-3xl p-6">
        <div className="animate-pulse text-sm text-slate-400">
          Chargement des comptes Jellyfin &amp; Jellyseerr…
        </div>
      </section>
    );
  }

  const query = search.trim().toLowerCase();
  const activeTabMeta =
    FILTER_TABS.find((t) => t.id === activeFilter) ?? FILTER_TABS[0];

  const filteredUsers = overview.users.filter(
    (u) =>
      (!query || u.name.toLowerCase().includes(query)) &&
      activeTabMeta.matches(u)
  );

  const managedUser =
    managedUserId !== null
      ? (overview.users.find((u) => u.jellyfin_id === managedUserId) ?? null)
      : null;

  const handleSyncUsers = async (jellyfinUserIds?: string[]) => {
    const key = jellyfinUserIds ? jellyfinUserIds.join(',') : 'all';
    setSyncingId(key);
    try {
      const data = await apiJson<{ imported_count: number }>(
        '/api/users/sync',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            jellyfin_user_ids: jellyfinUserIds || null,
            auto_approve: true,
          }),
        }
      );
      onToast({
        type: 'success',
        message: `${data.imported_count} compte(s) importé(s) dans Jellyseerr avec auto-approbation.`,
      });
      await onRefreshUsers();
    } catch (err) {
      onToast({
        type: 'error',
        message: err instanceof Error ? err.message : 'Échec synchronisation.',
      });
    } finally {
      setSyncingId(null);
    }
  };

  const totalLibraries = overview.libraries.length;

  return (
    <section className="legacy-dark-surface space-y-4">
      <div className="space-y-2.5">
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-wrap items-center gap-2.5">
            <Users className="h-4 w-4 text-cyan-400" />
            <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
              Utilisateurs Jellyfin &amp; Jellyseerr
            </h2>
            <span className="rounded-full border border-slate-800 bg-slate-900 px-2.5 py-0.5 text-xs text-slate-300">
              {overview.counts.total_jellyfin} Jellyfin
            </span>
            <span className="rounded-full border border-emerald-500/25 bg-emerald-500/10 px-2.5 py-0.5 text-xs text-emerald-300">
              {overview.counts.synced_jellyseerr} sur Jellyseerr
            </span>
            {overview.counts.unsynced_count > 0 && (
              <span className="rounded-full border border-amber-500/30 bg-amber-500/10 px-2.5 py-0.5 text-xs text-amber-300">
                {overview.counts.unsynced_count} à synchroniser
              </span>
            )}
            {overview.counts.disabled_count > 0 && (
              <span className="rounded-full border border-rose-500/30 bg-rose-500/10 px-2.5 py-0.5 text-xs text-rose-300">
                {overview.counts.disabled_count} suspendu
                {overview.counts.disabled_count > 1 ? 's' : ''}
              </span>
            )}
          </div>

          <div className="flex flex-wrap items-center gap-2">
            {overview.counts.unsynced_count > 0 && (
              <button
                type="button"
                disabled={syncingId !== null}
                onClick={() => handleSyncUsers()}
                className="inline-flex items-center gap-1.5 rounded-xl border border-amber-500/30 bg-amber-500/10 px-3 py-1.5 text-xs font-medium text-amber-300 transition hover:bg-amber-500/20 disabled:opacity-50"
              >
                <RefreshCw
                  className={`h-3.5 w-3.5 ${syncingId === 'all' ? 'animate-spin' : ''}`}
                />
                Synchroniser les manquants ({overview.counts.unsynced_count})
              </button>
            )}

            <button
              type="button"
              onClick={() => setCreateModalOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-xl border border-cyan-500/40 bg-cyan-500/15 px-3.5 py-1.5 text-xs font-semibold text-cyan-200 transition hover:bg-cyan-500/25"
            >
              <UserPlus className="h-3.5 w-3.5" />
              Créer un utilisateur
            </button>

            <button
              type="button"
              onClick={() => setExpanded((v) => !v)}
              className="inline-flex items-center gap-1 rounded-xl border border-slate-800 bg-slate-900 px-2.5 py-1.5 text-xs text-slate-400 hover:bg-slate-800 hover:text-slate-200"
              title={expanded ? 'Réduire la liste' : 'Afficher la liste'}
            >
              {expanded ? (
                <ChevronUp className="h-4 w-4" />
              ) : (
                <ChevronDown className="h-4 w-4" />
              )}
            </button>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          {FILTER_TABS.map((tab) => {
            const count = overview.users.filter(tab.matches).length;
            const active = activeFilter === tab.id;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveFilter(tab.id)}
                className={`inline-flex items-center gap-1.5 rounded-xl border px-2.5 py-1 text-xs font-medium transition ${
                  active
                    ? 'border-cyan-500/40 bg-cyan-500/15 text-cyan-200'
                    : 'border-slate-800/80 bg-slate-900/60 text-slate-400 hover:border-slate-700 hover:text-slate-200'
                }`}
              >
                <span>{tab.label}</span>
                <span
                  className={`rounded-full px-1.5 py-0.5 text-[10px] ${
                    active
                      ? 'bg-cyan-500/20 text-cyan-200'
                      : 'bg-slate-800 text-slate-400'
                  }`}
                >
                  {count}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {expanded && (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {filteredUsers.map((u) => (
            <div
              key={u.jellyfin_id}
              onClick={() => setManagedUserId(u.jellyfin_id)}
              className={`liquid-glass flex cursor-pointer flex-col justify-between rounded-3xl p-3.5 transition active:scale-[0.98] ${
                u.is_disabled
                  ? '!border-rose-500/30 hover:!border-rose-400/50'
                  : 'hover:!border-cyan-400/40'
              }`}
            >
              <div>
                <div className="flex items-start justify-between gap-2">
                  <div className="flex min-w-0 items-center gap-2.5">
                    <div
                      className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-xs font-semibold ${
                        u.is_disabled
                          ? 'border border-rose-500/30 bg-rose-500/10 text-rose-300'
                          : u.is_admin
                            ? 'border border-cyan-500/30 bg-cyan-500/15 text-cyan-300'
                            : 'border border-slate-700 bg-slate-800 text-slate-200'
                      }`}
                    >
                      {u.name.slice(0, 2).toUpperCase()}
                    </div>
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <span className="truncate text-sm font-medium text-slate-100">
                          {u.name}
                        </span>
                        {u.is_admin && (
                          <span className="rounded bg-cyan-500/15 px-1.5 py-0.5 text-[10px] font-medium text-cyan-300">
                            Admin
                          </span>
                        )}
                        {u.is_disabled && (
                          <span className="inline-flex items-center gap-0.5 rounded bg-rose-500/15 px-1.5 py-0.5 text-[10px] font-medium text-rose-300">
                            <Ban className="h-2.5 w-2.5" />
                            Suspendu
                          </span>
                        )}
                      </div>
                      <div className="text-[11px] text-slate-500">
                        Vu : {formatRelativeDate(u.last_activity)}
                      </div>
                    </div>
                  </div>

                  {u.in_jellyseerr ? (
                    <span
                      className="inline-flex shrink-0 items-center gap-1 rounded-full border border-emerald-500/25 bg-emerald-500/10 px-2 py-0.5 text-[10px] font-medium text-emerald-300"
                      title="Synchronisé sur Jellyseerr"
                    >
                      <CheckCircle2 className="h-3 w-3" />
                      Seerr OK
                    </span>
                  ) : (
                    <button
                      type="button"
                      disabled={syncingId !== null}
                      onClick={(e) => {
                        e.stopPropagation();
                        handleSyncUsers([u.jellyfin_id]);
                      }}
                      className="inline-flex shrink-0 items-center gap-1 rounded-full border border-amber-500/30 bg-amber-500/10 px-2 py-0.5 text-[10px] font-medium text-amber-300 transition hover:bg-amber-500/20 disabled:opacity-50"
                      title="Importer cet utilisateur sur Jellyseerr"
                    >
                      <ShieldAlert className="h-3 w-3" />
                      Importer
                    </button>
                  )}
                </div>

                <div className="mt-2.5 flex flex-wrap items-center gap-1.5 text-[11px]">
                  <span className="inline-flex items-center gap-1 rounded-md border border-slate-800 bg-slate-950/70 px-1.5 py-0.5 text-slate-300">
                    <FolderOpen className="h-3 w-3 text-slate-400" />
                    {formatLibrarySummary(u, totalLibraries)}
                  </span>
                  {u.max_active_sessions > 0 && (
                    <span className="inline-flex items-center gap-1 rounded-md border border-cyan-500/25 bg-cyan-500/10 px-1.5 py-0.5 text-cyan-300">
                      <Monitor className="h-3 w-3" />
                      {formatScreenLimit(u.max_active_sessions)}
                    </span>
                  )}
                </div>
              </div>

              <div className="mt-2.5 flex items-center justify-between gap-2 border-t border-slate-800/70 pt-2 text-[11px] text-slate-400">
                <div className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-0.5">
                  <span>
                    {u.in_jellyseerr
                      ? `${u.request_count} demande${u.request_count > 1 ? 's' : ''}`
                      : 'Absent de Jellyseerr'}
                  </span>
                  {u.in_jellyseerr && (
                    <span
                      className={`inline-flex items-center gap-1 ${
                        u.auto_approve ? 'text-cyan-300' : 'text-amber-300/90'
                      }`}
                    >
                      <UserCheck className="h-3 w-3" />
                      {u.auto_approve ? 'Auto-approuvé' : 'Validation manuelle'}
                    </span>
                  )}
                </div>

                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation();
                    setManagedUserId(u.jellyfin_id);
                  }}
                  className="inline-flex shrink-0 items-center gap-1 rounded-lg border border-slate-700/80 bg-slate-800/80 px-2 py-1 text-[11px] font-medium text-slate-200 transition hover:border-cyan-500/40 hover:bg-slate-800 hover:text-cyan-200"
                >
                  <Settings2 className="h-3 w-3" />
                  Gérer
                </button>
              </div>
            </div>
          ))}

          {filteredUsers.length === 0 && (
            <div className="col-span-full rounded-xl border border-slate-800 bg-slate-900/50 p-6 text-center text-sm text-slate-500">
              {query
                ? 'Aucun utilisateur ne correspond à la recherche et aux filtres.'
                : 'Aucun utilisateur dans cette catégorie.'}
            </div>
          )}
        </div>
      )}

      {createModalOpen && (
        <CreateUserModal
          libraries={overview.libraries}
          onClose={() => setCreateModalOpen(false)}
          onRefreshUsers={onRefreshUsers}
          onToast={onToast}
        />
      )}

      {managedUser && (
        <ManageUserModal
          user={managedUser}
          libraries={overview.libraries}
          syncing={syncingId === managedUser.jellyfin_id}
          onSyncUser={async (jellyfinId) => {
            await handleSyncUsers([jellyfinId]);
          }}
          onClose={() => setManagedUserId(null)}
          onRefreshUsers={onRefreshUsers}
          onToast={onToast}
        />
      )}
    </section>
  );
}

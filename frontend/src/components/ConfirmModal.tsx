import { AlertTriangle, X } from 'lucide-react';
import type { PveAction, PveResource } from '../types';

interface ConfirmModalProps {
  resource: PveResource;
  action: PveAction;
  busy: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}

const ACTION_META: Record<
  PveAction,
  { label: string; tone: string; buttonClass: string; warning: string }
> = {
  start: {
    label: 'Démarrer',
    tone: 'text-emerald-400',
    buttonClass: 'bg-emerald-600 hover:bg-emerald-500 text-white',
    warning: 'Cette ressource va être démarrée sur le nœud Proxmox.',
  },
  reboot: {
    label: 'Redémarrer',
    tone: 'text-amber-400',
    buttonClass: 'bg-amber-600 hover:bg-amber-500 text-white',
    warning: 'Les connexions et services en cours sur cette ressource seront temporairement coupés.',
  },
  shutdown: {
    label: 'Arrêter proprement',
    tone: 'text-rose-400',
    buttonClass: 'bg-rose-600 hover:bg-rose-500 text-white',
    warning: 'Un signal ACPI / d’extinction propre va être envoyé à cette ressource.',
  },
  stop: {
    label: 'Forcer l’arrêt',
    tone: 'text-rose-400',
    buttonClass: 'bg-rose-700 hover:bg-rose-600 text-white',
    warning: 'Attention : arrêt immédiat sans extinction propre du système.',
  },
};

export function ConfirmModal({
  resource,
  action,
  busy,
  onCancel,
  onConfirm,
}: ConfirmModalProps) {
  const meta = ACTION_META[action];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/75 p-4 backdrop-blur-sm">
      <div className="w-full max-w-md rounded-2xl border border-slate-800 bg-slate-900 p-6 shadow-2xl">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-slate-700 bg-slate-800">
              <AlertTriangle className={`h-5 w-5 ${meta.tone}`} />
            </div>
            <div>
              <h3 className="text-base font-semibold text-slate-100">
                {meta.label} {resource.type.toUpperCase()} {resource.vmid}
              </h3>
              <p className="text-sm text-slate-400">{resource.name}</p>
            </div>
          </div>
          <button
            type="button"
            onClick={onCancel}
            disabled={busy}
            className="rounded-lg p-1 text-slate-400 hover:bg-slate-800 hover:text-slate-200"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <p className="mt-4 rounded-xl border border-slate-800 bg-slate-950/70 p-3 text-sm text-slate-300">
          {meta.warning}
        </p>

        <div className="mt-5 flex items-center justify-end gap-2.5">
          <button
            type="button"
            onClick={onCancel}
            disabled={busy}
            className="rounded-xl border border-slate-700 bg-slate-800 px-4 py-2 text-sm font-medium text-slate-200 transition hover:bg-slate-700 disabled:opacity-50"
          >
            Annuler
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={busy}
            className={`rounded-xl px-4 py-2 text-sm font-medium transition disabled:opacity-50 ${meta.buttonClass}`}
          >
            {busy ? 'Exécution…' : `Confirmer (${meta.label})`}
          </button>
        </div>
      </div>
    </div>
  );
}

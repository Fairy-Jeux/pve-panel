import { useCallback, useEffect, useRef, useState } from 'react';
import {
  Activity,
  AlertCircle,
  CheckCircle2,
  HardDrive,
  LayoutGrid,
  Server,
  SlidersHorizontal,
  Sparkles,
  Users,
} from 'lucide-react';
import { AlertsBanner } from './components/AlertsBanner';
import { ConfirmModal } from './components/ConfirmModal';
import { Header } from './components/Header';
import { OperationsSection } from './components/OperationsSection';
import { ProxmoxSection } from './components/ProxmoxSection';
import { ServerConfigModal } from './components/ServerConfigModal';
import { ServiceCard } from './components/ServiceCard';
import { SetupWizardModal } from './components/SetupWizardModal';
import { StorageSection } from './components/StorageSection';
import { UsersSection } from './components/UsersSection';
import { getServerUrl, isDemoMode, isNativePlatform } from './lib/apiClient';
import type {
  AuthUser,
  OpsOverview,
  PveAction,
  PveOverview,
  PveResource,
  ServiceCategory,
  SetupStatusResponse,
  UsersOverview,
  WidgetsMap,
} from './types';

type ActiveTab = 'all' | 'storage' | 'services' | 'proxmox' | 'ops' | 'users';

export function App() {
  const [user, setUser] = useState<AuthUser | null>(null);
  const [pveOverview, setPveOverview] = useState<PveOverview | null>(null);
  const [categories, setCategories] = useState<ServiceCategory[]>([]);
  const [widgets, setWidgets] = useState<WidgetsMap>({});
  const [usersOverview, setUsersOverview] = useState<UsersOverview | null>(null);
  const [opsOverview, setOpsOverview] = useState<OpsOverview | null>(null);
  const [activeTab, setActiveTab] = useState<ActiveTab>('all');
  const [search, setSearch] = useState('');
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [authError, setAuthError] = useState<string | null>(null);
  const [serverModalOpen, setServerModalOpen] = useState<boolean>(
    () => isNativePlatform() && !getServerUrl() && !isDemoMode()
  );
  const [serverModalHint, setServerModalHint] = useState<string | null>(null);
  const [setupStatus, setSetupStatus] = useState<SetupStatusResponse | null>(null);
  const [setupModalOpen, setSetupModalOpen] = useState(false);
  const hasLoadedOnceRef = useRef(false);
  const autoPromptedSetupRef = useRef(false);

  const [pendingAction, setPendingAction] = useState<{
    resource: PveResource;
    action: PveAction;
  } | null>(null);
  const [actionBusy, setActionBusy] = useState(false);
  const [toast, setToast] = useState<{
    type: 'success' | 'error';
    message: string;
  } | null>(null);

  const fetchUsersOnly = useCallback(async () => {
    const resp = await fetch('/api/users');
    if (resp.ok) setUsersOverview(await resp.json());
  }, []);

  const fetchOpsOnly = useCallback(async () => {
    const resp = await fetch('/api/ops/overview');
    if (resp.ok) setOpsOverview(await resp.json());
  }, []);

  const fetchAllData = useCallback(async () => {
    if (isNativePlatform() && !getServerUrl() && !isDemoMode()) {
      setServerModalHint(
        'Configurez votre URL Tailscale Serve ou activez le Mode Démo interactif pour explorer l’application.'
      );
      setServerModalOpen(true);
      return;
    }

    setIsRefreshing(true);
    try {
      const [meResp, pveResp, svcResp, widResp, usrResp, opsResp, setupResp] = await Promise.all([
        fetch('/api/me'),
        fetch('/api/pve/overview'),
        fetch('/api/services'),
        fetch('/api/widgets/all'),
        fetch('/api/users'),
        fetch('/api/ops/overview'),
        fetch('/api/setup/status'),
      ]);

      if (meResp.status === 403) {
        const err = await meResp.json().catch(() => ({}));
        setAuthError(err.detail || 'Accès refusé par le middleware Tailscale SSO.');
        return;
      }

      if (!meResp.ok) {
        throw new Error(`HTTP ${meResp.status}`);
      }

      setUser(await meResp.json());
      if (pveResp.ok) setPveOverview(await pveResp.json());
      if (svcResp.ok) {
        const svcData = await svcResp.json();
        setCategories(svcData.categories || []);
      }
      if (widResp.ok) setWidgets(await widResp.json());
      if (usrResp.ok) setUsersOverview(await usrResp.json());
      if (opsResp.ok) setOpsOverview(await opsResp.json());
      if (setupResp.ok) {
        const nextSetup = (await setupResp.json()) as SetupStatusResponse;
        setSetupStatus(nextSetup);
        if (!nextSetup.is_configured && !isDemoMode() && !autoPromptedSetupRef.current) {
          autoPromptedSetupRef.current = true;
          setSetupModalOpen(true);
        }
      }

      hasLoadedOnceRef.current = true;
      setLastUpdated(new Date());
      setAuthError(null);
      setServerModalHint(null);
    } catch {
      if (!hasLoadedOnceRef.current) {
        setServerModalHint(
          'Impossible de joindre le serveur. Vérifiez Tailscale ou passez en Mode Démo interactif.'
        );
        setServerModalOpen(true);
      } else {
        setToast({
          type: 'error',
          message: 'Impossible de joindre le backend FastAPI.',
        });
      }
    } finally {
      setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    fetchAllData();
  }, [fetchAllData]);

  useEffect(() => {
    if (!autoRefresh) return;
    const timer = window.setInterval(fetchAllData, 5000);
    return () => window.clearInterval(timer);
  }, [autoRefresh, fetchAllData]);

  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setToast(null), 4000);
    return () => window.clearTimeout(timer);
  }, [toast]);

  const handleConfirmAction = async () => {
    if (!pendingAction) return;
    setActionBusy(true);
    const { resource, action } = pendingAction;
    try {
      const resp = await fetch(
        `/api/pve/${resource.type}/${resource.vmid}/${action}`,
        { method: 'POST' }
      );
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data.detail || `Erreur HTTP ${resp.status}`);
      }
      setToast({
        type: 'success',
        message: `Action "${action}" envoyée à ${resource.name} (#${resource.vmid}).`,
      });
      setPendingAction(null);
      window.setTimeout(fetchAllData, 1200);
    } catch (err) {
      setToast({
        type: 'error',
        message: err instanceof Error ? err.message : 'Échec de la commande Proxmox.',
      });
    } finally {
      setActionBusy(false);
    }
  };

  if (authError) {
    return (
      <div className="flex min-h-screen items-center justify-center p-6">
        <div className="liquid-glass-elevated max-w-md rounded-3xl p-6 text-center">
          <AlertCircle className="mx-auto h-10 w-10 text-rose-400" />
          <h1 className="mt-3 text-lg font-semibold text-white">
            Accès strictement réservé
          </h1>
          <p className="mt-2 text-sm text-slate-300">{authError}</p>
          <button
            type="button"
            onClick={() => setServerModalOpen(true)}
            className="mt-5 inline-flex items-center gap-2 rounded-2xl border border-cyan-400/40 bg-cyan-500/20 px-4 py-2.5 text-xs font-semibold text-cyan-100 transition hover:bg-cyan-500/30 active:scale-[0.98]"
          >
            <SlidersHorizontal className="h-3.5 w-3.5" />
            Configurer serveur ou Mode Démo
          </button>
        </div>

        <ServerConfigModal
          open={serverModalOpen}
          initialMessage={serverModalHint}
          onClose={() => setServerModalOpen(false)}
          onApplied={() => {
            setServerModalOpen(false);
            setAuthError(null);
            hasLoadedOnceRef.current = false;
            autoPromptedSetupRef.current = false;
            void fetchAllData();
          }}
        />
      </div>
    );
  }

  const query = search.trim().toLowerCase();
  const filteredCategories = categories
    .map((cat) => ({
      ...cat,
      services: cat.services.filter(
        (svc) =>
          !query ||
          svc.name.toLowerCase().includes(query) ||
          svc.description.toLowerCase().includes(query) ||
          cat.name.toLowerCase().includes(query)
      ),
    }))
    .filter((cat) => cat.services.length > 0);

  const pool = pveOverview?.external_storage?.pool;
  const poolBadge =
    pool && pool.total_bytes > 0
      ? `${(pool.total_bytes / 1e12).toFixed(1)} To • ${pool.used_pct}%`
      : '16 To';

  const pendingSeerrCount = (opsOverview?.seerr_requests || []).filter(
    (r) => r.status === 1
  ).length;

  const navTabs: Array<{
    id: ActiveTab;
    label: string;
    shortLabel: string;
    icon: typeof LayoutGrid;
    badge?: string;
    dot?: boolean;
  }> = [
    { id: 'all', label: "Vue d'ensemble", shortLabel: 'Accueil', icon: LayoutGrid },
    {
      id: 'storage',
      label: 'Stockage & Disques',
      shortLabel: 'Stockage',
      icon: HardDrive,
      badge: poolBadge,
    },
    { id: 'proxmox', label: 'Proxmox (LXC / VM)', shortLabel: 'Proxmox', icon: Server },
    { id: 'services', label: 'Services & Widgets', shortLabel: 'Services', icon: Sparkles },
    {
      id: 'ops',
      label: 'Activité & Actions',
      shortLabel: 'Actions',
      icon: Activity,
      badge: pendingSeerrCount > 0 ? `${pendingSeerrCount} en attente` : undefined,
      dot: pendingSeerrCount > 0,
    },
    { id: 'users', label: 'Utilisateurs', shortLabel: 'Comptes', icon: Users },
  ];

  const showSection = (tab: Exclude<ActiveTab, 'all'>) =>
    activeTab === 'all' || activeTab === tab;

  const demoActive = isDemoMode();

  return (
    <div className="min-h-screen pb-28 md:pb-14">
      <Header
        user={user}
        search={search}
        onSearchChange={setSearch}
        autoRefresh={autoRefresh}
        onToggleAutoRefresh={() => setAutoRefresh((v) => !v)}
        isRefreshing={isRefreshing}
        onRefreshNow={fetchAllData}
        lastUpdated={lastUpdated}
        demoActive={demoActive}
        needsSetup={Boolean(setupStatus && !setupStatus.is_configured && !demoActive)}
        onOpenServerConfig={() => setServerModalOpen(true)}
        onOpenSetupWizard={() => setSetupModalOpen(true)}
      />

      {/* Barre d'onglets Liquid Glass (Desktop / iPad) */}
      <div className="hidden border-b border-white/10 bg-slate-950/35 backdrop-blur-xl md:block">
        <div className="mx-auto flex max-w-7xl items-center gap-2 overflow-x-auto px-4 py-2.5 sm:px-6">
          {navTabs.map((tab) => {
            const Icon = tab.icon;
            const active = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`inline-flex shrink-0 items-center gap-2 rounded-full border px-3.5 py-1.5 text-xs font-medium transition active:scale-95 ${
                  active
                    ? 'border-white/25 bg-gradient-to-b from-white/20 to-cyan-500/20 text-white shadow-inner shadow-white/15'
                    : 'border-transparent bg-transparent text-slate-400 hover:border-white/10 hover:bg-white/[0.06] hover:text-slate-100'
                }`}
              >
                <Icon className={`h-3.5 w-3.5 ${active ? 'text-cyan-300' : ''}`} />
                <span>{tab.label}</span>
                {tab.badge && (
                  <span
                    className={`rounded-full px-1.5 py-0.5 text-[10px] font-semibold ${
                      active
                        ? 'bg-cyan-400/25 text-cyan-100'
                        : 'bg-white/10 text-slate-300'
                    }`}
                  >
                    {tab.badge}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Floating Liquid Glass Bottom Tab Bar (iPhone / iOS 26) */}
      <nav
        aria-label="Navigation principale iPhone"
        className="safe-bottom-dock fixed inset-x-3 z-40 md:hidden"
      >
        <div className="liquid-glass-dock mx-auto flex max-w-md items-center justify-between gap-1 rounded-[28px] p-1.5">
          {navTabs.map((tab) => {
            const Icon = tab.icon;
            const active = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => {
                  setActiveTab(tab.id);
                  window.scrollTo({ top: 0, behavior: 'smooth' });
                }}
                className={`relative flex flex-1 flex-col items-center justify-center gap-0.5 rounded-[22px] py-1.5 text-[10px] font-medium transition active:scale-95 ${
                  active
                    ? 'border border-white/20 bg-gradient-to-b from-white/20 to-cyan-400/20 text-white shadow-inner'
                    : 'text-slate-400 hover:text-slate-200'
                }`}
              >
                <Icon className={`h-4 w-4 ${active ? 'text-cyan-300' : ''}`} />
                <span className="truncate leading-none">{tab.shortLabel}</span>
                {tab.dot && (
                  <span className="absolute right-2.5 top-1.5 h-1.5 w-1.5 rounded-full bg-amber-400 shadow-[0_0_8px_rgba(251,191,36,0.9)]" />
                )}
              </button>
            );
          })}
        </div>
      </nav>

      <main className="mx-auto max-w-7xl space-y-10 px-4 pt-6 sm:px-6">
        <AlertsBanner
          pveOverview={pveOverview}
          categories={categories}
          usersOverview={usersOverview}
          opsOverview={opsOverview}
          onJumpToTab={(tab) => setActiveTab(tab)}
        />

        {/* Section 1 : Supervision & Contrôle Proxmox VE */}
        {showSection('proxmox') && (
          <ProxmoxSection
            overview={pveOverview}
            search={search}
            onRequestAction={(resource, action) =>
              setPendingAction({ resource, action })
            }
          />
        )}

        {/* Onglet / Section Stockage Proxmox & 16 To MergerFS */}
        {activeTab === 'storage' && (
          <StorageSection overview={pveOverview} search={search} />
        )}

        {/* Onglet Activité, Actions Rapides Médias/Torrents & Tâches Proxmox */}
        {activeTab === 'ops' && (
          <OperationsSection
            ops={opsOverview}
            search={search}
            onRefreshOps={fetchOpsOnly}
            onToast={setToast}
          />
        )}

        {/* Section 2 : Hub de services & Widgets */}
        {showSection('services') && (
          <section className="space-y-6">
            {filteredCategories.map((category) => (
              <div key={category.name} className="space-y-3">
                <div className="flex items-center justify-between">
                  <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
                    {category.name}
                  </h2>
                  <span className="text-xs text-slate-500">
                    {category.services.filter((s) => s.online).length}/
                    {category.services.length} en ligne
                  </span>
                </div>
                <div className="grid grid-cols-1 gap-3.5 sm:grid-cols-2 lg:grid-cols-3">
                  {category.services.map((service) => (
                    <ServiceCard
                      key={service.id}
                      service={service}
                      widgets={widgets}
                    />
                  ))}
                </div>
              </div>
            ))}
          </section>
        )}

        {/* Section 3 : Gestion unifiée Utilisateurs Jellyfin <-> Jellyseerr */}
        {showSection('users') && (
          <UsersSection
            overview={usersOverview}
            search={search}
            onRefreshUsers={fetchUsersOnly}
            onToast={setToast}
          />
        )}
      </main>

      {pendingAction && (
        <ConfirmModal
          resource={pendingAction.resource}
          action={pendingAction.action}
          busy={actionBusy}
          onCancel={() => setPendingAction(null)}
          onConfirm={handleConfirmAction}
        />
      )}

      <ServerConfigModal
        open={serverModalOpen}
        initialMessage={serverModalHint}
        onClose={() => setServerModalOpen(false)}
        onApplied={() => {
          setServerModalOpen(false);
          setAuthError(null);
          hasLoadedOnceRef.current = false;
          autoPromptedSetupRef.current = false;
          void fetchAllData();
        }}
      />

      <SetupWizardModal
        open={setupModalOpen}
        initialStatus={setupStatus}
        onClose={() => setSetupModalOpen(false)}
        onApplied={(message) => {
          setSetupModalOpen(false);
          setToast({
            type: 'success',
            message: message || 'Configuration enregistrée et appliquée à chaud.',
          });
          void fetchAllData();
        }}
      />

      {toast && (
        <div className="liquid-glass-elevated fixed bottom-24 left-4 right-4 z-50 flex items-center gap-2.5 rounded-2xl px-4 py-3 text-sm text-white sm:left-auto sm:right-5 md:bottom-5">
          {toast.type === 'success' ? (
            <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-400" />
          ) : (
            <AlertCircle className="h-4 w-4 shrink-0 text-rose-400" />
          )}
          <span className="min-w-0 flex-1">{toast.message}</span>
        </div>
      )}
    </div>
  );
}

export default App;

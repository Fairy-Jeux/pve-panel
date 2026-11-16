import { useCallback, useEffect, useState } from 'react';
import {
  Activity,
  AlertCircle,
  CheckCircle2,
  HardDrive,
  LayoutGrid,
  Server,
  Sparkles,
  Users,
} from 'lucide-react';
import { AlertsBanner } from './components/AlertsBanner';
import { ConfirmModal } from './components/ConfirmModal';
import { Header } from './components/Header';
import { OperationsSection } from './components/OperationsSection';
import { ProxmoxSection } from './components/ProxmoxSection';
import { ServiceCard } from './components/ServiceCard';
import { StorageSection } from './components/StorageSection';
import { UsersSection } from './components/UsersSection';
import type {
  AuthUser,
  OpsOverview,
  PveAction,
  PveOverview,
  PveResource,
  ServiceCategory,
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
    setIsRefreshing(true);
    try {
      const [meResp, pveResp, svcResp, widResp, usrResp, opsResp] = await Promise.all([
        fetch('/api/me'),
        fetch('/api/pve/overview'),
        fetch('/api/services'),
        fetch('/api/widgets/all'),
        fetch('/api/users'),
        fetch('/api/ops/overview'),
      ]);

      if (meResp.status === 403) {
        const err = await meResp.json().catch(() => ({}));
        setAuthError(err.detail || 'Accès refusé par le middleware Tailscale SSO.');
        return;
      }

      if (meResp.ok) setUser(await meResp.json());
      if (pveResp.ok) setPveOverview(await pveResp.json());
      if (svcResp.ok) {
        const svcData = await svcResp.json();
        setCategories(svcData.categories || []);
      }
      if (widResp.ok) setWidgets(await widResp.json());
      if (usrResp.ok) setUsersOverview(await usrResp.json());
      if (opsResp.ok) setOpsOverview(await opsResp.json());

      setLastUpdated(new Date());
      setAuthError(null);
    } catch {
      setToast({
        type: 'error',
        message: 'Impossible de joindre le backend FastAPI.',
      });
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
      <div className="flex min-h-screen items-center justify-center bg-slate-950 p-6">
        <div className="max-w-md rounded-2xl border border-rose-500/30 bg-slate-900 p-6 text-center">
          <AlertCircle className="mx-auto h-10 w-10 text-rose-400" />
          <h1 className="mt-3 text-lg font-semibold text-slate-100">
            Accès strictement réservé
          </h1>
          <p className="mt-2 text-sm text-slate-400">{authError}</p>
        </div>
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
    icon: typeof LayoutGrid;
    badge?: string;
  }> = [
    { id: 'all', label: "Vue d'ensemble", icon: LayoutGrid },
    { id: 'storage', label: 'Stockage & Disques', icon: HardDrive, badge: poolBadge },
    { id: 'proxmox', label: 'Proxmox (LXC / VM)', icon: Server },
    { id: 'services', label: 'Services & Widgets', icon: Sparkles },
    {
      id: 'ops',
      label: 'Activité & Actions',
      icon: Activity,
      badge: pendingSeerrCount > 0 ? `${pendingSeerrCount} en attente` : undefined,
    },
    { id: 'users', label: 'Utilisateurs', icon: Users },
  ];

  const showSection = (tab: Exclude<ActiveTab, 'all'>) =>
    activeTab === 'all' || activeTab === tab;

  return (
    <div className="min-h-screen pb-14">
      <Header
        user={user}
        search={search}
        onSearchChange={setSearch}
        autoRefresh={autoRefresh}
        onToggleAutoRefresh={() => setAutoRefresh((v) => !v)}
        isRefreshing={isRefreshing}
        onRefreshNow={fetchAllData}
        lastUpdated={lastUpdated}
      />

      <div className="border-b border-slate-800/70 bg-slate-950/60 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center gap-1.5 overflow-x-auto px-4 py-2.5 sm:px-6">
          {navTabs.map((tab) => {
            const Icon = tab.icon;
            const active = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`inline-flex shrink-0 items-center gap-2 rounded-xl border px-3 py-1.5 text-xs font-medium transition ${
                  active
                    ? 'border-cyan-500/40 bg-cyan-500/15 text-cyan-200 shadow-sm shadow-cyan-500/10'
                    : 'border-transparent bg-transparent text-slate-400 hover:border-slate-800 hover:bg-slate-900 hover:text-slate-200'
                }`}
              >
                <Icon className="h-3.5 w-3.5" />
                <span>{tab.label}</span>
                {tab.badge && (
                  <span
                    className={`rounded-full px-1.5 py-0.5 text-[10px] font-semibold ${
                      active
                        ? 'bg-cyan-500/20 text-cyan-200'
                        : 'bg-slate-800 text-slate-400'
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

      {toast && (
        <div className="fixed bottom-5 right-5 z-50 flex items-center gap-2.5 rounded-xl border border-slate-700 bg-slate-900/95 px-4 py-3 text-sm text-slate-100 shadow-2xl backdrop-blur">
          {toast.type === 'success' ? (
            <CheckCircle2 className="h-4 w-4 text-emerald-400" />
          ) : (
            <AlertCircle className="h-4 w-4 text-rose-400" />
          )}
          <span>{toast.message}</span>
        </div>
      )}
    </div>
  );
}

export default App;

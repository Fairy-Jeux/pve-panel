import { getAuthToken, getServerUrl, isDemoMode } from './apiClient';
import type { RealtimeEvent, RealtimeTransportMode } from '../types';

export type RealtimeEventListener = (event: RealtimeEvent) => void;
export type RealtimeStatusListener = (status: RealtimeTransportMode) => void;
export type RealtimeAuthRequiredListener = () => void;

export class RealtimeClient {
  private ws: WebSocket | null = null;
  private sse: EventSource | null = null;
  private status: RealtimeTransportMode = 'disconnected';
  private stopped = true;
  private reconnectTimer: number | null = null;
  private backoffMs = 1000;
  private wsFailureCount = 0;

  private eventListeners = new Set<RealtimeEventListener>();
  private statusListeners = new Set<RealtimeStatusListener>();
  private authListeners = new Set<RealtimeAuthRequiredListener>();

  getStatus(): RealtimeTransportMode {
    return this.status;
  }

  subscribe(listener: RealtimeEventListener): () => void {
    this.eventListeners.add(listener);
    return () => {
      this.eventListeners.delete(listener);
    };
  }

  onStatusChange(listener: RealtimeStatusListener): () => void {
    this.statusListeners.add(listener);
    listener(this.status);
    return () => {
      this.statusListeners.delete(listener);
    };
  }

  onAuthRequired(listener: RealtimeAuthRequiredListener): () => void {
    this.authListeners.add(listener);
    return () => {
      this.authListeners.delete(listener);
    };
  }

  private setStatus(next: RealtimeTransportMode): void {
    if (this.status === next) return;
    this.status = next;
    this.statusListeners.forEach((cb) => cb(next));
  }

  private emitEvent(event: RealtimeEvent): void {
    this.eventListeners.forEach((cb) => cb(event));
  }

  private clearSockets(): void {
    if (this.reconnectTimer !== null) {
      window.clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      this.ws.onopen = null;
      this.ws.onmessage = null;
      this.ws.onerror = null;
      this.ws.onclose = null;
      try {
        this.ws.close();
      } catch {
        // Ignore close errors during teardown
      }
      this.ws = null;
    }
    if (this.sse) {
      this.sse.onopen = null;
      this.sse.onmessage = null;
      this.sse.onerror = null;
      try {
        this.sse.close();
      } catch {
        // Ignore close errors during teardown
      }
      this.sse = null;
    }
  }

  connect(): void {
    this.clearSockets();
    this.stopped = false;

    if (typeof window === 'undefined') return;

    if (isDemoMode()) {
      this.setStatus('demo');
      return;
    }

    this.wsFailureCount = 0;
    this.backoffMs = 1000;
    this.openWebSocket();
  }

  reconnect(): void {
    this.connect();
  }

  disconnect(): void {
    this.stopped = true;
    this.clearSockets();
    this.setStatus(isDemoMode() ? 'demo' : 'disconnected');
  }

  private buildBaseHttpUrl(): string {
    const remote = getServerUrl();
    if (remote) return remote;
    return window.location.origin;
  }

  private buildWsUrl(): string {
    const httpBase = this.buildBaseHttpUrl();
    const wsBase = httpBase.replace(/^http:/i, 'ws:').replace(/^https:/i, 'wss:');
    const token = getAuthToken();
    const qs = token ? `?token=${encodeURIComponent(token)}` : '';
    return `${wsBase}/api/ws/events${qs}`;
  }

  private buildSseUrl(): string {
    const httpBase = this.buildBaseHttpUrl();
    const token = getAuthToken();
    const qs = token ? `?token=${encodeURIComponent(token)}` : '';
    return `${httpBase}/api/events/stream${qs}`;
  }

  private scheduleReconnect(preferSse: boolean): void {
    if (this.stopped || isDemoMode()) return;
    if (this.reconnectTimer !== null) {
      window.clearTimeout(this.reconnectTimer);
    }
    const delay = this.backoffMs;
    this.backoffMs = Math.min(this.backoffMs * 2, 30_000);

    this.reconnectTimer = window.setTimeout(() => {
      this.reconnectTimer = null;
      if (this.stopped) return;
      if (preferSse) {
        this.openSseFallback();
      } else {
        this.openWebSocket();
      }
    }, delay);
  }

  private openWebSocket(): void {
    if (this.stopped || isDemoMode()) return;
    if (typeof WebSocket === 'undefined') {
      this.openSseFallback();
      return;
    }

    this.setStatus('connecting');
    let openedOnce = false;
    let ws: WebSocket;
    try {
      ws = new WebSocket(this.buildWsUrl());
    } catch {
      this.wsFailureCount += 1;
      this.openSseFallback();
      return;
    }

    this.ws = ws;

    ws.onopen = () => {
      if (this.stopped || this.ws !== ws) return;
      openedOnce = true;
      this.wsFailureCount = 0;
      this.backoffMs = 1000;
      this.setStatus('ws');
    };

    ws.onmessage = (msg) => {
      if (this.stopped || this.ws !== ws) return;
      const raw = typeof msg.data === 'string' ? msg.data : '';
      if (!raw) return;
      try {
        const parsed = JSON.parse(raw) as RealtimeEvent;
        if (parsed.type === 'ping') {
          try {
            ws.send(JSON.stringify({ type: 'pong' }));
          } catch {
            // Ignore send failure on closing socket
          }
          return;
        }
        this.emitEvent(parsed);
      } catch {
        // Ignore malformed frame
      }
    };

    ws.onerror = () => {
      // Handled in onclose
    };

    ws.onclose = (ev) => {
      if (this.ws === ws) {
        this.ws = null;
      }
      if (this.stopped) return;

      if (ev.code === 4401) {
        this.stopped = true;
        this.setStatus('disconnected');
        this.authListeners.forEach((cb) => cb());
        return;
      }

      if (!openedOnce) {
        this.wsFailureCount += 1;
      }

      // Immediately fall back to SSE when WebSocket upgrade fails
      if (!openedOnce || this.wsFailureCount >= 2) {
        this.openSseFallback();
        return;
      }

      this.setStatus('disconnected');
      this.scheduleReconnect(false);
    };
  }

  private openSseFallback(): void {
    if (this.stopped || isDemoMode()) return;
    if (typeof EventSource === 'undefined') {
      this.setStatus('disconnected');
      this.scheduleReconnect(false);
      return;
    }

    this.setStatus('connecting');
    const es = new EventSource(this.buildSseUrl(), { withCredentials: true });
    this.sse = es;

    es.onopen = () => {
      if (this.stopped || this.sse !== es) return;
      this.backoffMs = 1000;
      this.setStatus('sse');
    };

    es.onmessage = (msg) => {
      if (this.stopped || this.sse !== es) return;
      if (!msg.data) return;
      try {
        const parsed = JSON.parse(msg.data) as RealtimeEvent;
        if (parsed.type === 'ping') return;
        this.emitEvent(parsed);
      } catch {
        // Ignore malformed SSE payload
      }
    };

    es.onerror = () => {
      if (this.sse === es) {
        es.close();
        this.sse = null;
      }
      if (this.stopped) return;
      this.setStatus('disconnected');
      // After SSE failure, retry WS cleanly with backoff
      this.scheduleReconnect(false);
    };
  }
}

export const realtimeClient = new RealtimeClient();

"""In-memory pub/sub event bus for WebSocket and SSE real-time broadcasts."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class RealtimeBus:
    """Async per-subscriber queue fan-out bus for snake_case realtime events."""

    def __init__(self, max_queue_size: int = 128) -> None:
        self._max_queue_size = max_queue_size
        self._subscribers: set[asyncio.Queue[dict[str, Any] | None]] = set()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._running = False

    async def start(self) -> None:
        """Bind the bus to the active asyncio event loop."""
        self._loop = asyncio.get_running_loop()
        self._running = True

    async def stop(self) -> None:
        """Signal all active subscribers to close cleanly on shutdown."""
        self._running = False
        self._dispatch_stop()

    def stop_nowait(self) -> None:
        """Signal all active subscribers to close from any thread or sync context."""
        self._running = False
        if not self._subscribers:
            return
        try:
            running_loop = asyncio.get_running_loop()
        except RuntimeError:
            running_loop = None

        if self._loop is not None and running_loop is not self._loop and self._loop.is_running():
            self._loop.call_soon_threadsafe(self._dispatch_stop)
        else:
            self._dispatch_stop()

    def _dispatch_stop(self) -> None:
        for queue in list(self._subscribers):
            self._enqueue_drop_oldest(queue, None)

    def subscriber_count(self) -> int:
        """Return number of currently connected SSE/WebSocket subscribers."""
        return len(self._subscribers)

    async def connect(self) -> asyncio.Queue[dict[str, Any] | None]:
        """Register and return a new subscriber queue."""
        try:
            self._loop = asyncio.get_running_loop()
        except RuntimeError:
            pass
        queue: asyncio.Queue[dict[str, Any] | None] = asyncio.Queue(
            maxsize=self._max_queue_size
        )
        self._subscribers.add(queue)
        return queue

    def disconnect(self, queue: asyncio.Queue[dict[str, Any] | None]) -> None:
        """Unregister a subscriber queue."""
        self._subscribers.discard(queue)

    @asynccontextmanager
    async def subscribe(self) -> AsyncIterator[asyncio.Queue[dict[str, Any] | None]]:
        """Async context manager yielding a subscriber queue and auto-disconnecting."""
        queue = await self.connect()
        try:
            yield queue
        finally:
            self.disconnect(queue)

    def _enqueue_drop_oldest(
        self,
        queue: asyncio.Queue[dict[str, Any] | None],
        item: dict[str, Any] | None,
    ) -> None:
        if queue.full():
            try:
                queue.get_nowait()
            except asyncio.QueueEmpty:
                pass
        try:
            queue.put_nowait(item)
        except asyncio.QueueFull:
            pass

    def _dispatch_event(self, event: dict[str, Any]) -> None:
        for queue in list(self._subscribers):
            self._enqueue_drop_oldest(queue, event)

    def build_event(
        self, event_type: str, payload: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        """Construct canonical snake_case event envelope."""
        return {
            "type": event_type,
            "timestamp": _utc_timestamp(),
            "payload": payload if payload is not None else {},
        }

    def publish_nowait(
        self, event_type: str, payload: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        """Publish an event without awaiting (safe from sync callers or same loop)."""
        event = self.build_event(event_type, payload)
        if not self._subscribers:
            return event

        try:
            running_loop = asyncio.get_running_loop()
        except RuntimeError:
            running_loop = None

        if self._loop is not None and running_loop is not self._loop and self._loop.is_running():
            self._loop.call_soon_threadsafe(self._dispatch_event, event)
        else:
            self._dispatch_event(event)
        return event

    async def publish(
        self, event_type: str, payload: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        """Publish an event to all subscribers asynchronously."""
        try:
            self._loop = asyncio.get_running_loop()
        except RuntimeError:
            pass
        event = self.build_event(event_type, payload)
        self._dispatch_event(event)
        return event


realtime_bus = RealtimeBus()


def get_realtime_bus() -> RealtimeBus:
    """Return the shared singleton RealtimeBus instance."""
    return realtime_bus

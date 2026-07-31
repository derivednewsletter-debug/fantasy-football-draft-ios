"""WebSocket connection manager for live, cross-device draft sync.

Each connected client subscribes to a league.  Every successful pick or
undo on that league broadcasts the fresh draft state to all subscribers,
so any number of devices stay in sync without polling.
"""

from __future__ import annotations

import threading
from collections import defaultdict
from typing import Any

from fastapi import WebSocket


class ConnectionManager:
    """Tracks WebSocket clients per league and pushes draft state updates."""

    def __init__(self) -> None:
        # league_id (name) -> set of connected WebSockets
        self._connections: dict[str, set[WebSocket]] = defaultdict(set)
        # Registry is touched from the event loop (handler + broadcast) and
        # defensively from worker threads, so guard it with a lock.
        self._lock = threading.Lock()

    def connect(self, league_id: str, ws: WebSocket) -> None:
        with self._lock:
            self._connections[league_id].add(ws)

    def disconnect(self, league_id: str, ws: WebSocket) -> None:
        with self._lock:
            conns = self._connections.get(league_id)
            if conns:
                conns.discard(ws)
                if not conns:
                    self._connections.pop(league_id, None)

    def client_count(self, league_id: str) -> int:
        with self._lock:
            return len(self._connections.get(league_id, ()))

    async def broadcast(self, league_id: str, message: dict[str, Any]) -> int:
        """Send a JSON message to every client subscribed to a league.

        Returns the number of clients that received it.  Clients that go
        away mid-broadcast are dropped from the registry quietly.
        """
        with self._lock:
            targets = list(self._connections.get(league_id, ()))

        sent = 0
        for ws in targets:
            try:
                await ws.send_json(message)
                sent += 1
            except Exception:
                self.disconnect(league_id, ws)
        return sent


# Module-level singleton used by the FastAPI app.
manager = ConnectionManager()

"""Durable key-value persistence for the Fantasy Draft API.

Two backends, selected by environment:

* **Postgres** — when ``DATABASE_URL`` is set (Neon / Supabase on Vercel).
  Survives serverless cold starts, so accounts and leagues persist.
* **SQLite** — otherwise, a local file under ``FANTASY_DATA_DIR``.  Durable
  on any filesystem-backed host (local dev, Render, Fly, etc.) with zero
  extra dependencies.

All documents are JSON blobs keyed by ``(collection, key)``.  Collections:

* ``users``   — email -> user record (salt, password hash)
* ``sessions`` — token -> session record (email, expires_at)
* ``leagues:<user_id>`` — league name -> full league payload

Design notes:
* If Postgres is unreachable we fall back to SQLite (logging the failure)
  instead of letting the whole function 500 on serverless — a bare
  FUNCTION_INVOCATION_FAILED on every request is the worst failure mode.
  After a short retry window the app tries Postgres again, so a transient
  Neon blip downgrades storage only temporarily.
* All Postgres access happens under ``_pg_conn_lock`` (psycopg connections
  are not thread-safe); SQLite opens a fresh connection per call.
* On first use we perform a one-time best-effort migration of any existing
  JSON files from the old file-based store, so existing accounts and
  leagues carry over to the new storage automatically.
"""

from __future__ import annotations

import json
import logging
import os
import sqlite3
import threading
import time
from pathlib import Path

# Same default as engine/store.py: FANTASY_DATA_DIR or backend/data.
DATA_DIR = Path(os.environ.get("FANTASY_DATA_DIR", Path(__file__).resolve().parent / "data"))

logger = logging.getLogger("fantasy.db")

_DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
SQLITE_PATH = DATA_DIR / "draft.db"

# Serialises writes for both backends (single-writer semantics).
_write_lock = threading.Lock()
# Guards the shared psycopg connection (reads AND writes).
_pg_conn_lock = threading.Lock()

_pg_conn = None
_fallback_mode = False
_fallback_since = 0.0
_fallback_logged = False
# Try to recover Postgres after this long once it has dropped.
_FALLBACK_RETRY_SECONDS = 30.0

_migrated = False
_migration_lock = threading.Lock()

SCHEMA = """
CREATE TABLE IF NOT EXISTS kv (
    collection TEXT NOT NULL,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    PRIMARY KEY (collection, key)
)
"""


# ---------------------------------------------------------------------------
# Backend selection
# ---------------------------------------------------------------------------

def is_postgres() -> bool:
    return bool(_DATABASE_URL) and not _fallback_mode


def backend_name() -> str:
    if is_postgres():
        return "postgres"
    return "sqlite"


def _sqlite_conn() -> sqlite3.Connection:
    SQLITE_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(SQLITE_PATH, timeout=15)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=15000")
    conn.execute(SCHEMA)
    conn.commit()
    return conn


def _pg_connect():
    """Create a Postgres connection (Neon/Supabase URL).  Caller holds the lock."""
    import psycopg  # imported lazily so local runs need no driver installed

    conn = psycopg.connect(_DATABASE_URL, connect_timeout=8)
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute(SCHEMA)
    return conn


def _pg() -> object | None:
    """Return a live Postgres connection, or None (falls back to SQLite).

    Caller must hold ``_pg_conn_lock``.  Reconnects after a drop once the
    retry window has elapsed, so a transient outage self-heals.
    """
    global _pg_conn, _fallback_mode, _fallback_since, _fallback_logged
    if _pg_conn is not None and _pg_conn.closed == 0:
        return _pg_conn
    if _fallback_mode and time.time() - _fallback_since < _FALLBACK_RETRY_SECONDS:
        return None
    try:
        _pg_conn = _pg_connect()
        _fallback_mode = False
        _fallback_since = 0.0
        return _pg_conn
    except Exception as exc:  # noqa: BLE001 - any failure falls back
        _fallback_mode = True
        _fallback_since = time.time()
        if not _fallback_logged:
            _fallback_logged = True
            logger.error(
                "Postgres unavailable (%s) — falling back to SQLite at %s. "
                "Accounts/leagues will NOT survive cold starts until "
                "DATABASE_URL is reachable. Retrying in %.0fs.",
                exc,
                SQLITE_PATH,
                _FALLBACK_RETRY_SECONDS,
            )
        return None


def _pg_reset() -> None:
    """Drop a dead Postgres connection.  Caller must hold ``_pg_conn_lock``."""
    global _pg_conn
    if _pg_conn is not None:
        try:
            _pg_conn.close()
        except Exception:  # noqa: BLE001
            pass
    _pg_conn = None


# ---------------------------------------------------------------------------
# CRUD (same shape for both backends)
# ---------------------------------------------------------------------------

def get(collection: str, key: str) -> dict | None:
    _migrate_once()
    if is_postgres():
        with _pg_conn_lock:
            conn = _pg()
            if conn is not None:
                try:
                    with conn.cursor() as cur:
                        cur.execute(
                            "SELECT value FROM kv WHERE collection = %s AND key = %s",
                            (collection, key),
                        )
                        row = cur.fetchone()
                    return json.loads(row[0]) if row else None
                except Exception:  # noqa: BLE001
                    _pg_reset()
    conn = _sqlite_conn()
    try:
        row = conn.execute(
            "SELECT value FROM kv WHERE collection = ? AND key = ?",
            (collection, key),
        ).fetchone()
        return json.loads(row["value"]) if row else None
    finally:
        conn.close()


def set(collection: str, key: str, value: dict) -> None:
    _migrate_once()
    payload = json.dumps(value, default=str)
    with _write_lock:
        if is_postgres():
            with _pg_conn_lock:
                conn = _pg()
                if conn is not None:
                    try:
                        with conn.cursor() as cur:
                            cur.execute(
                                """
                                INSERT INTO kv (collection, key, value) VALUES (%s, %s, %s)
                                ON CONFLICT (collection, key) DO UPDATE SET value = EXCLUDED.value
                                """,
                                (collection, key, payload),
                            )
                        return
                    except Exception:  # noqa: BLE001
                        _pg_reset()
        conn = _sqlite_conn()
        try:
            conn.execute(
                """
                INSERT INTO kv (collection, key, value) VALUES (?, ?, ?)
                ON CONFLICT (collection, key) DO UPDATE SET value = excluded.value
                """,
                (collection, key, payload),
            )
            conn.commit()
        finally:
            conn.close()


def delete(collection: str, key: str) -> bool:
    _migrate_once()
    with _write_lock:
        if is_postgres():
            with _pg_conn_lock:
                conn = _pg()
                if conn is not None:
                    try:
                        with conn.cursor() as cur:
                            cur.execute(
                                "DELETE FROM kv WHERE collection = %s AND key = %s",
                                (collection, key),
                            )
                        return True
                    except Exception:  # noqa: BLE001
                        _pg_reset()
        conn = _sqlite_conn()
        try:
            cur = conn.execute(
                "DELETE FROM kv WHERE collection = ? AND key = ?",
                (collection, key),
            )
            conn.commit()
            return cur.rowcount > 0
        finally:
            conn.close()


def all_values(collection: str) -> dict[str, dict]:
    _migrate_once()
    if is_postgres():
        with _pg_conn_lock:
            conn = _pg()
            if conn is not None:
                try:
                    with conn.cursor() as cur:
                        cur.execute(
                            "SELECT key, value FROM kv WHERE collection = %s", (collection,)
                        )
                        return {r[0]: json.loads(r[1]) for r in cur.fetchall()}
                except Exception:  # noqa: BLE001
                    _pg_reset()
    conn = _sqlite_conn()
    try:
        rows = conn.execute(
            "SELECT key, value FROM kv WHERE collection = ?", (collection,)
        ).fetchall()
        return {r["key"]: json.loads(r["value"]) for r in rows}
    finally:
        conn.close()


def count_collections_with_prefix(prefix: str) -> int:
    _migrate_once()
    if is_postgres():
        with _pg_conn_lock:
            conn = _pg()
            if conn is not None:
                try:
                    with conn.cursor() as cur:
                        cur.execute(
                            "SELECT COUNT(*) FROM kv WHERE collection LIKE %s",
                            (f"{prefix}%",),
                        )
                        return cur.fetchone()[0]
                except Exception:  # noqa: BLE001
                    _pg_reset()
    conn = _sqlite_conn()
    try:
        row = conn.execute(
            "SELECT COUNT(*) AS n FROM kv WHERE collection LIKE ?", (f"{prefix}%",)
        ).fetchone()
        return row["n"]
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# One-time migration from the legacy JSON files
# ---------------------------------------------------------------------------

def _migrate_once() -> None:
    """Copy legacy JSON files (users/sessions/leagues) into the KV store."""
    global _migrated
    if _migrated:
        return
    with _migration_lock:
        if _migrated:
            return
        _migrated = True
        try:
            _migrate_users_and_sessions()
            _migrate_leagues()
        except Exception:  # noqa: BLE001 - best effort
            logger.exception("Legacy JSON migration failed")


def _migrate_users_and_sessions() -> None:
    auth_dir = DATA_DIR / "auth"
    users_file = auth_dir / "users.json"
    if users_file.exists():
        try:
            users = json.loads(users_file.read_text())
        except (json.JSONDecodeError, OSError):
            users = {}
        for email, rec in users.items():
            if get("users", email) is None:
                set("users", email, rec)
    sessions_file = auth_dir / "sessions.json"
    if sessions_file.exists():
        try:
            sessions = json.loads(sessions_file.read_text())
        except (json.JSONDecodeError, OSError):
            sessions = {}
        for token, rec in sessions.items():
            if get("sessions", token) is None:
                set("sessions", token, rec)


def _migrate_leagues() -> None:
    users_root = DATA_DIR / "users"
    if not users_root.exists():
        return
    for user_dir in sorted(users_root.iterdir()):
        if not user_dir.is_dir():
            continue
        for path in sorted(user_dir.glob("*.json")):
            try:
                data = json.loads(path.read_text())
            except (json.JSONDecodeError, OSError):
                continue
            name = data.get("name") or path.stem
            if get(f"leagues:{user_dir.name}", name) is None:
                set(f"leagues:{user_dir.name}", name, data)

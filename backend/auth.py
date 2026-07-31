"""Email/password authentication for the Fantasy Draft API.

Users and sessions are persisted through :mod:`backend.db`, a durable
key-value store: SQLite locally, Postgres via ``DATABASE_URL`` on Vercel
(so accounts survive serverless cold starts).  Passwords are hashed with
PBKDF2-HMAC-SHA256 (stdlib `hashlib` — no extra dependencies), and every
login issues a bearer token that expires after TOKEN_TTL_DAYS.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import threading
import time

from . import db

_PBKDF2_ITERATIONS = 200_000
TOKEN_TTL_DAYS = 30
TOKEN_TTL_SECONDS = TOKEN_TTL_DAYS * 24 * 3600

_lock = threading.Lock()


class AuthError(Exception):
    """Raised for invalid credentials or a taken email."""


# ---------------------------------------------------------------------------
# Passwords
# ---------------------------------------------------------------------------

def _hash_password(password: str, salt_hex: str) -> str:
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        bytes.fromhex(salt_hex),
        _PBKDF2_ITERATIONS,
    )
    return digest.hex()


def _new_salt() -> str:
    return secrets.token_hex(16)


def _verify_password(password: str, salt_hex: str, expected_hash: str) -> bool:
    return hmac.compare_digest(_hash_password(password, salt_hex), expected_hash)


# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------

def _normalize_email(email: str) -> str:
    return email.strip().lower()


def create_user(email: str, password: str) -> dict:
    """Create a user account.  Raises AuthError if the email is taken or
    the password is too short."""
    email = _normalize_email(email)
    if len(password) < 6:
        raise AuthError("Password must be at least 6 characters")
    with _lock:
        if db.get("users", email) is not None:
            raise AuthError("An account with that email already exists")
        salt = _new_salt()
        record = {
            "email": email,
            "salt": salt,
            "password_hash": _hash_password(password, salt),
            "created_at": int(time.time()),
        }
        db.set("users", email, record)
        return record


def get_user(email: str) -> dict | None:
    return db.get("users", _normalize_email(email))


_DUMMY_SALT = "0" * 32
_DUMMY_HASH = _hash_password("dummy-password", _DUMMY_SALT)


def authenticate_user(email: str, password: str) -> dict | None:
    """Return the user record if credentials are valid, else None.

    When the email doesn't exist, a dummy PBKDF2 verify still runs so the
    response time doesn't reveal whether an address is registered.
    """
    user = get_user(email)
    if user is None:
        _verify_password(password, _DUMMY_SALT, _DUMMY_HASH)
        return None
    if _verify_password(password, user["salt"], user["password_hash"]):
        return user
    return None


# ---------------------------------------------------------------------------
# Sessions / tokens
# ---------------------------------------------------------------------------

def _prune_expired(sessions: dict) -> None:
    now = int(time.time())
    for token in [t for t, s in sessions.items() if s.get("expires_at", 0) < now]:
        sessions.pop(token, None)


def issue_token(email: str) -> str:
    """Issue a bearer token for a user, persisted across restarts."""
    email = _normalize_email(email)
    with _lock:
        sessions = db.all_values("sessions")
        _prune_expired(sessions)
        token = secrets.token_urlsafe(32)
        sessions[token] = {"email": email, "expires_at": int(time.time()) + TOKEN_TTL_SECONDS}
        db.set("sessions", token, sessions[token])
        return token


def resolve_token(token: str) -> str | None:
    """Return the email for a valid, unexpired token, else None."""
    if not token:
        return None
    session = db.get("sessions", token)
    if session is None:
        return None
    if session.get("expires_at", 0) < int(time.time()):
        with _lock:
            db.delete("sessions", token)
        return None
    return session.get("email")


def revoke_token(token: str) -> None:
    with _lock:
        db.delete("sessions", token)


def active_session_count() -> int:
    return len(db.all_values("sessions"))

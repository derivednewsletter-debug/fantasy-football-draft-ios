"""Pytest fixtures for the Fantasy Draft Assistant API tests."""

from __future__ import annotations

import os
import shutil
import tempfile
import uuid

import httpx
import pytest

# Isolate runtime data BEFORE importing the app (store reads FANTASY_DATA_DIR
# at import time).
_TMP = tempfile.mkdtemp(prefix="fantasy-test-")
os.environ["FANTASY_DATA_DIR"] = _TMP
# Force the NVIDIA AI advisor off in tests unless explicitly mocked.
os.environ.setdefault("NVIDIA_API_KEY", "")

from backend.main import app  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _isolated_data_dir():
    """Point the store at a throwaway temp dir for the whole session."""
    os.environ["FANTASY_DATA_DIR"] = _TMP
    yield
    shutil.rmtree(_TMP, ignore_errors=True)


@pytest.fixture()
async def bare_client():
    """Unauthenticated httpx.AsyncClient (for auth/401 tests)."""
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture()
async def client():
    """httpx.AsyncClient signed up + logged in as a fresh per-test user.

    Every test gets its own account, so leagues are naturally isolated
    between tests.
    """
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        token, email = await signup_and_login(c)
        c.headers["Authorization"] = f"Bearer {token}"
        yield c


async def signup_and_login(c, email: str | None = None) -> tuple[str, str]:
    """Create a fresh account and return (token, email)."""
    email = email or f"user-{uuid.uuid4().hex[:12]}@test.com"
    resp = await c.post("/auth/signup", json={"email": email, "password": "secret123"})
    assert resp.status_code == 201, resp.text
    body = resp.json()
    return body["token"], body["email"]


@pytest.fixture()
def make_league():
    """Factory: create a league (authed via the client's header) and return
    its decoded summary + name."""

    async def _factory(client, name: str = "Test League", num_teams: int = 12,
                       user_team_number: int = 4, scoring: str = "PPR"):
        resp = await client.post(
            "/leagues",
            json={
                "name": name,
                "num_teams": num_teams,
                "user_team_number": user_team_number,
                "scoring_format": scoring,
            },
        )
        assert resp.status_code == 201, resp.text
        return resp.json()

    return _factory


def url_escape(name: str) -> str:
    """URL-encode a league name for path segments."""
    from urllib.parse import quote
    return quote(name, safe="")

"""Pytest fixtures for the Fantasy Draft Assistant API tests."""

from __future__ import annotations

import os
import shutil
import tempfile

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
async def client():
    """httpx.AsyncClient wired to the FastAPI app via ASGITransport."""
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


@pytest.fixture()
def make_league():
    """Factory: create a league and return its decoded summary + name."""

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

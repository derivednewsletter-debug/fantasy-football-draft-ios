"""Durable persistence for leagues.

Each user's leagues are stored in the :mod:`backend.db` key-value store
under the ``leagues:<user_id>`` collection — SQLite locally, Postgres via
``DATABASE_URL`` on Vercel — so draft data is separated per account and
survives serverless cold starts.
"""

from __future__ import annotations

import copy
import os
import re
import threading
from pathlib import Path
from typing import Callable, TypeVar

from .. import db
from .models import League, Player, ROSTER_PRESETS

DEFAULT_CSV = Path(__file__).resolve().parent.parent / "default_projections.csv"
DATA_DIR = db.DATA_DIR

_lock = threading.Lock()
_template_pool: list[Player] | None = None

T = TypeVar("T")


def _league_collection(user_id: str) -> str:
    safe = re.sub(r"[^a-z0-9@._-]", "_", (user_id or "anon").lower())[:64] or "anon"
    return f"leagues:{safe}"


# ---------------------------------------------------------------------------
# Player pool
# ---------------------------------------------------------------------------

def _load_template_pool(csv_path: Path | None = None) -> list[Player]:
    """Load the pristine player template from the projections CSV (cached).

    The returned list is never mutated.  Each league gets its own deep copy
    so picks in one league can never contaminate another league's pool.
    """
    global _template_pool
    if _template_pool is not None:
        return _template_pool

    import csv

    path = csv_path or DEFAULT_CSV
    players: list[Player] = []
    if path.exists():
        with open(path, "r") as f:
            for row in csv.DictReader(f):
                try:
                    players.append(
                        Player(
                            name=row["name"].strip(),
                            position=row["position"].strip(),
                            team=row["team"].strip(),
                            projected_points=float(row.get("projected_points", 0) or 0),
                            adp=float(row.get("adp", 999) or 999),
                            tier=int(row.get("tier", 5) or 5),
                        )
                    )
                except (ValueError, KeyError):
                    continue
    players.sort(key=lambda p: (p.tier, -p.projected_points))
    _template_pool = players
    return players


def fresh_pool() -> list[Player]:
    """Deep copy of the pristine player pool, safe to mutate per-league."""
    return [copy.deepcopy(p) for p in _load_template_pool()]


# ---------------------------------------------------------------------------
# League persistence (per user)
# ---------------------------------------------------------------------------

def load_league(name: str, user_id: str) -> League | None:
    """Load a user's league, re-attaching a fresh player pool."""
    data = db.get(_league_collection(user_id), name)
    if data is None:
        return None
    league = League.from_dict(data)

    # Rebuild the pool from the pristine template, applying the draft state
    # persisted in the league file.  This keeps pool ordering canonical while
    # preserving which players have been drafted.
    pool = fresh_pool()
    by_name = {p.name: p for p in pool}
    for player in league.players_pool:
        canonical = by_name.get(player.name)
        if canonical is not None:
            canonical.is_drafted = player.is_drafted
            canonical.drafted_by = player.drafted_by
            canonical.drafted_at_pick = player.drafted_at_pick
    league.players_pool = pool
    return league


def list_leagues(user_id: str) -> list[dict]:
    """Return lightweight metadata for the user's saved leagues."""
    collection = _league_collection(user_id)
    metas = []
    for name, data in db.all_values(collection).items():
        if not isinstance(data, dict):
            continue
        metas.append(
            {
                "name": data.get("name", name),
                "num_teams": data.get("num_teams", 0),
                "user_team_number": data.get("user_team_number", 1),
                "scoring_format": data.get("scoring_format", "PPR"),
                "current_round": data.get("current_round", 1),
                "overall_pick": data.get("overall_pick", 1),
                "is_active": data.get("is_active", True),
                "completed": data.get("completed", False),
                "total_picks": len(data.get("draft_log", [])),
                "team_on_clock": _team_on_clock_from_meta(data),
            }
        )
    return sorted(metas, key=lambda m: m["name"])


def total_leagues() -> int:
    """Total league documents across all users (public health endpoint)."""
    return db.count_collections_with_prefix("leagues:")


def _team_on_clock_from_meta(data: dict) -> int:
    r = data.get("current_round", 1)
    p = data.get("current_pick_in_round", 1)
    n = data.get("num_teams", 1)
    return p if r % 2 == 1 else n - p + 1


def save_league(league: League, user_id: str) -> None:
    db.set(_league_collection(user_id), league.name, league.to_dict())


def update_league(name: str, user_id: str, mutator: Callable[[League], T]) -> tuple[League, T]:
    """Atomically load, mutate, and save a user's league.

    Runs inside a thread lock so concurrent pick/undo requests can't
    interleave and lose updates (FastAPI runs sync endpoints in a threadpool).
    """
    with _lock:
        league = load_league(name, user_id)
        if league is None:
            raise KeyError(name)
        result = mutator(league)
        save_league(league, user_id)
        return league, result


def delete_league(name: str, user_id: str) -> bool:
    with _lock:
        return db.delete(_league_collection(user_id), name)


# ---------------------------------------------------------------------------
# League factory
# ---------------------------------------------------------------------------

def create_league(name: str, num_teams: int, user_team_number: int,
                  scoring_format: str, user_id: str) -> League:
    """Build a fresh League with its own pristine player pool, saved for the user."""
    slots = dict(ROSTER_PRESETS.get(scoring_format, ROSTER_PRESETS["PPR"]))
    league = League(
        name=name,
        num_teams=num_teams,
        user_team_number=min(max(user_team_number, 1), num_teams),
        scoring_format=scoring_format,
        roster_slots=slots,
        players_pool=fresh_pool(),
    )
    save_league(league, user_id)
    return league

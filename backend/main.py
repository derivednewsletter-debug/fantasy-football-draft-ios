"""FastAPI backend for the Fantasy Football Draft Assistant.

Exposes the existing Python draft engine (VBD + NVIDIA NIM AI) over REST.
Run with:  uvicorn backend.main:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

from typing import Optional

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from .engine import (
    League,
    build_draft_matrix,
    picks_before_next_user_turn,
    recommend,
    recommend_ai,
)
from .engine.store import create_league, delete_league, list_leagues, load_league
from .engine.store import update_league as _update_league
from .schemas import (
    HealthResponse,
    LeagueCreate,
    LeagueState,
    LeagueSummary,
    PickRequest,
    PickResult,
    RecommendationsResponse,
    Recommendation,
    UndoResult,
)

app = FastAPI(
    title="Fantasy Draft Assistant API",
    description="Multi-league fantasy football draft engine + AI recommendations.",
    version="1.0.0",
)

# Allow the iOS simulator / device and local dev clients.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _load_or_404(name: str) -> League:
    league = load_league(name)
    if league is None:
        raise HTTPException(status_code=404, detail=f"League '{name}' not found")
    return league


def _league_summary(league: League) -> dict:
    return {
        "name": league.name,
        "num_teams": league.num_teams,
        "user_team_number": league.user_team_number,
        "scoring_format": league.scoring_format,
        "current_round": league.current_round,
        "overall_pick": league.overall_pick,
        "is_active": league.is_active,
        "completed": league.completed,
        "total_picks": len(league.draft_log),
        "team_on_clock": league.team_on_clock,
    }


def _recommendation_dict(r: dict) -> dict:
    """Normalise an engine recommendation row into the schema shape."""
    return {
        "name": r.get("name", ""),
        "position": r.get("position", ""),
        "team": r.get("team", ""),
        "projected_points": r.get("projected_points", 0),
        "adp": r.get("adp", 999),
        "vbd": r.get("vbd"),
        "score": r.get("score"),
        "turn_loss_pct": r.get("turn_loss_pct"),
        "rationale": r.get("rationale"),
    }


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/", response_model=HealthResponse, tags=["system"])
def health():
    try:
        from .engine.ai_advisor import is_available as ai_available
        ai_ok = ai_available()
    except ImportError:
        # openai / ai_advisor dependencies not installed — engine degrades gracefully.
        ai_ok = False

    return HealthResponse(
        status="ok",
        leagues=len(list_leagues()),
        ai_available=ai_ok,
    )


# ---------------------------------------------------------------------------
# Leagues
# ---------------------------------------------------------------------------

@app.get("/leagues", response_model=list[LeagueSummary], tags=["leagues"])
def get_leagues():
    """List all active league draft configurations."""
    return list_leagues()


@app.post("/leagues", response_model=LeagueSummary, status_code=201, tags=["leagues"])
def post_league(body: LeagueCreate):
    """Create a new league (team count, pick position, scoring, roster layout)."""
    # League names are used as URL path segments by every other endpoint and
    # percent-encoded by clients — a literal "/" can never round-trip through
    # the router (it is decoded back into a path separator).  Reject early.
    hostile = {"/", "\\", "?", "#", "%"}
    if any(ch in body.name for ch in hostile) or body.name.startswith("."):
        raise HTTPException(
            status_code=400,
            detail="League name cannot contain '/', '\\', '?', '#', or '%' and cannot start with '.'",
        )
    if load_league(body.name) is not None:
        raise HTTPException(status_code=409, detail=f"League '{body.name}' already exists")
    league = create_league(
        name=body.name,
        num_teams=body.num_teams,
        user_team_number=body.user_team_number,
        scoring_format=body.scoring_format,
    )
    return _league_summary(league)


# ---------------------------------------------------------------------------
# Draft state
# ---------------------------------------------------------------------------

@app.get("/leagues/{league_id}/state", response_model=LeagueState, tags=["draft"])
def get_state(league_id: str):
    """Get full current draft state (round, pick, on-the-clock team, rosters)."""
    league = _load_or_404(league_id)
    return LeagueState(
        name=league.name,
        num_teams=league.num_teams,
        user_team_number=league.user_team_number,
        scoring_format=league.scoring_format,
        roster_slots=dict(league.roster_slots),
        current_round=league.current_round,
        current_pick_in_round=league.current_pick_in_round,
        overall_pick=league.overall_pick,
        is_active=league.is_active,
        completed=league.completed,
        team_on_clock=league.team_on_clock,
        is_user_on_clock=league.is_user_on_clock,
        picks_before_user=picks_before_next_user_turn(league),
        draft_log=[p.to_dict() for p in league.draft_log],
        teams=[t.to_dict() for t in league.teams],
        available_players=[p.to_dict() for p in league.available_players],
        matrix=build_draft_matrix(league),
    )


@app.post("/leagues/{league_id}/pick", response_model=PickResult, tags=["draft"])
def make_pick(league_id: str, body: PickRequest):
    """Submit a pick for the team currently on the clock (fuzzy match)."""
    try:
        def _pick(league: League):
            if league.completed:
                return None, "Draft is complete"
            try:
                pick = league.record_pick(body.player_name)
            except ValueError as exc:
                # e.g. the team on the clock already has a full roster
                return None, str(exc)
            if pick is None:
                return None, f"Could not match '{body.player_name}' to an available player"
            return pick.to_dict(), None

        _, (pick, error) = _update_league(league_id, _pick)
    except KeyError:
        raise HTTPException(status_code=404, detail=f"League '{league_id}' not found")

    if error:
        return PickResult(success=False, error=error)
    return PickResult(success=True, pick=pick)


@app.post("/leagues/{league_id}/undo", response_model=UndoResult, tags=["draft"])
def undo_pick(league_id: str):
    """Roll back the last draft pick."""
    try:
        def _undo(league: League):
            ok = league.undo_last_pick()
            return ok, (None if ok else "No picks to undo")

        _, (ok, error) = _update_league(league_id, _undo)
    except KeyError:
        raise HTTPException(status_code=404, detail=f"League '{league_id}' not found")

    if not ok:
        return UndoResult(success=False, error=error)
    return UndoResult(success=True)


# ---------------------------------------------------------------------------
# Recommendations
# ---------------------------------------------------------------------------

@app.get("/leagues/{league_id}/recommendations", response_model=RecommendationsResponse, tags=["recommendations"])
def get_recommendations(league_id: str, ai: bool = Query(True, description="Include NVIDIA NIM AI analysis")):
    """Trigger the recommendation engine for the active user's turn."""
    league = _load_or_404(league_id)
    recs = recommend(league)

    ai_analysis: Optional[str] = None
    ai_top: Optional[dict] = None

    if ai:
        ai_result = recommend_ai(league)
        if ai_result:
            ai_analysis = ai_result.get("ai_analysis")
            top = ai_result.get("ai_top_target") or {}
            if top:
                ai_top = {
                    "name": top.get("name", ""),
                    "position": top.get("position", ""),
                    "team": top.get("team", ""),
                    "projected_points": 0,
                    "adp": 0,
                    "rationale": top.get("rationale"),
                }

    return RecommendationsResponse(
        safe_picks=[Recommendation(**_recommendation_dict(r)) for r in recs["safe_picks"]],
        upside_picks=[Recommendation(**_recommendation_dict(r)) for r in recs["upside_picks"]],
        sleepers=[Recommendation(**_recommendation_dict(r)) for r in recs["sleepers"]],
        all_ranked=[Recommendation(**_recommendation_dict(r)) for r in recs["all_ranked"]],
        picks_before_user=recs["picks_before_user"],
        ai_analysis=ai_analysis,
        ai_top_target=Recommendation(**ai_top) if ai_top else None,
    )


# ---------------------------------------------------------------------------
# Admin
# ---------------------------------------------------------------------------

@app.delete("/leagues/{league_id}", tags=["leagues"])
def remove_league(league_id: str):
    """Delete a league (admin convenience)."""
    if not delete_league(league_id):
        raise HTTPException(status_code=404, detail=f"League '{league_id}' not found")
    return {"success": True}

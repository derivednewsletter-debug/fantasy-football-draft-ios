"""FastAPI backend for the Fantasy Football Draft Assistant.

Exposes the existing Python draft engine (VBD + NVIDIA NIM AI) over REST,
with email/password accounts so each user's leagues and drafts are stored
separately.

Run with:  uvicorn backend.main:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

from typing import Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from starlette.concurrency import run_in_threadpool

from . import auth
from .engine import (
    League,
    build_draft_matrix,
    picks_before_next_user_turn,
    recommend,
    recommend_ai,
)
from .engine.store import (
    create_league,
    delete_league,
    list_leagues,
    load_league,
    total_leagues,
)
from .engine.store import update_league as _update_league
from .engine.ws_manager import manager as ws_manager
from .schemas import (
    AuthResponse,
    HealthResponse,
    LeagueCreate,
    LeagueState,
    LeagueSummary,
    LoginRequest,
    MeResponse,
    PickRequest,
    PickResult,
    RecommendationsResponse,
    Recommendation,
    SignupRequest,
    UndoResult,
)

app = FastAPI(
    title="Fantasy Draft Assistant API",
    description="Multi-league fantasy football draft engine + AI recommendations, with per-user accounts.",
    version="1.1.0",
)

# Allow the iOS simulator / device and local dev clients.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Auth dependency
# ---------------------------------------------------------------------------

def get_current_user(authorization: Optional[str] = Header(default=None)) -> str:
    """Resolve the bearer token from the Authorization header to an email."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Not authenticated")
    token = authorization.split(" ", 1)[1].strip()
    email = auth.resolve_token(token)
    if email is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return email


# ---------------------------------------------------------------------------
# Auth endpoints
# ---------------------------------------------------------------------------

@app.post("/auth/signup", response_model=AuthResponse, status_code=201, tags=["auth"])
def signup(body: SignupRequest):
    try:
        user = auth.create_user(body.email, body.password)
    except auth.AuthError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    return AuthResponse(token=auth.issue_token(user["email"]), email=user["email"])


@app.post("/auth/login", response_model=AuthResponse, tags=["auth"])
def login(body: LoginRequest):
    user = auth.authenticate_user(body.email, body.password)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return AuthResponse(token=auth.issue_token(user["email"]), email=user["email"])


@app.post("/auth/logout", tags=["auth"])
def logout(authorization: Optional[str] = Header(default=None)):
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()
        auth.revoke_token(token)
    return {"success": True}


@app.get("/auth/me", response_model=MeResponse, tags=["auth"])
def me(user_email: str = Depends(get_current_user)):
    return MeResponse(email=user_email)


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
        leagues=total_leagues(),
        ai_available=ai_ok,
    )


# ---------------------------------------------------------------------------
# League helpers
# ---------------------------------------------------------------------------

def _load_or_404(name: str, user_id: str) -> League:
    league = load_league(name, user_id)
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


def _state_payload(league: League) -> dict:
    """Build the full draft-state dict, shared by the REST and WS endpoints."""
    return {
        "name": league.name,
        "num_teams": league.num_teams,
        "user_team_number": league.user_team_number,
        "scoring_format": league.scoring_format,
        "roster_slots": dict(league.roster_slots),
        "current_round": league.current_round,
        "current_pick_in_round": league.current_pick_in_round,
        "overall_pick": league.overall_pick,
        "is_active": league.is_active,
        "completed": league.completed,
        "team_on_clock": league.team_on_clock,
        "is_user_on_clock": league.is_user_on_clock,
        "picks_before_user": picks_before_next_user_turn(league),
        "draft_log": [p.to_dict() for p in league.draft_log],
        "teams": [t.to_dict() for t in league.teams],
        "available_players": [p.to_dict() for p in league.available_players],
        "matrix": build_draft_matrix(league),
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
# Leagues
# ---------------------------------------------------------------------------

@app.get("/leagues", response_model=list[LeagueSummary], tags=["leagues"])
def get_leagues(user_id: str = Depends(get_current_user)):
    """List all active league draft configurations for the signed-in user."""
    return list_leagues(user_id)


@app.post("/leagues", response_model=LeagueSummary, status_code=201, tags=["leagues"])
def post_league(body: LeagueCreate, user_id: str = Depends(get_current_user)):
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
    if load_league(body.name, user_id) is not None:
        raise HTTPException(status_code=409, detail=f"League '{body.name}' already exists")
    league = create_league(
        name=body.name,
        num_teams=body.num_teams,
        user_team_number=body.user_team_number,
        scoring_format=body.scoring_format,
        user_id=user_id,
    )
    return _league_summary(league)


# ---------------------------------------------------------------------------
# Draft state
# ---------------------------------------------------------------------------

@app.get("/leagues/{league_id}/state", response_model=LeagueState, tags=["draft"])
def get_state(league_id: str, user_id: str = Depends(get_current_user)):
    """Get full current draft state (round, pick, on-the-clock team, rosters)."""
    league = _load_or_404(league_id, user_id)
    return LeagueState(**_state_payload(league))


@app.websocket("/leagues/{league_id}/ws")
async def league_ws(websocket: WebSocket, league_id: str, token: str = Query("")):
    """Live draft feed: pushes every state change to all connected devices.

    Auth is taken from the Authorization header when present, falling back to
    the `token` query parameter (kept for clients that can't set WS headers).
    On connect the client immediately receives the current state envelope,
    then every successful pick/undo is broadcast to all subscribers of the
    league.  The server also answers "ping" text frames with "pong".
    """
    await websocket.accept()

    # Prefer the header (not logged) over the query param (loggable).
    header_auth = websocket.headers.get("authorization", "")
    if header_auth.lower().startswith("bearer "):
        token = header_auth.split(" ", 1)[1].strip()
    user_email = auth.resolve_token(token)
    if user_email is None:
        await websocket.send_json({"type": "error", "detail": "Not authenticated"})
        await websocket.close(code=4401)
        return

    # Leagues are per-user, so the broadcast channel is namespaced by user.
    channel = f"{user_email}|{league_id}"
    ws_manager.connect(channel, websocket)
    try:
        # Fresh read AFTER registering: a concurrent pick's _update_league
        # saves to disk before broadcasting, so this load is consistent with
        # any broadcast already in flight (no stale initial snapshot).
        league = load_league(league_id, user_email)
        if league is None:
            await websocket.send_json({"type": "error", "detail": f"League '{league_id}' not found"})
            await websocket.close(code=4404)
            return

        # Initial snapshot so clients can render immediately without polling.
        await websocket.send_json({
            "type": "state",
            "league_id": league.name,
            "state": _state_payload(league),
        })
        while True:
            message = await websocket.receive_text()
            if message == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        pass
    finally:
        ws_manager.disconnect(channel, websocket)


@app.post("/leagues/{league_id}/pick", response_model=PickResult, tags=["draft"])
async def make_pick(league_id: str, body: PickRequest, user_id: str = Depends(get_current_user)):
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

        # Blocking store work runs in the threadpool; broadcast happens on the
        # event loop so WebSocket sends are safe.
        league, (pick, error) = await run_in_threadpool(_update_league, league_id, user_id, _pick)
    except KeyError:
        raise HTTPException(status_code=404, detail=f"League '{league_id}' not found")

    if error:
        return PickResult(success=False, error=error)

    await ws_manager.broadcast(
        f"{user_id}|{league.name}",
        {"type": "state", "league_id": league.name, "state": _state_payload(league)},
    )
    return PickResult(success=True, pick=pick)


@app.post("/leagues/{league_id}/undo", response_model=UndoResult, tags=["draft"])
async def undo_pick(league_id: str, user_id: str = Depends(get_current_user)):
    """Roll back the last draft pick."""
    try:
        def _undo(league: League):
            ok = league.undo_last_pick()
            return ok, (None if ok else "No picks to undo")

        league, (ok, error) = await run_in_threadpool(_update_league, league_id, user_id, _undo)
    except KeyError:
        raise HTTPException(status_code=404, detail=f"League '{league_id}' not found")

    if not ok:
        return UndoResult(success=False, error=error)

    await ws_manager.broadcast(
        f"{user_id}|{league.name}",
        {"type": "state", "league_id": league.name, "state": _state_payload(league)},
    )
    return UndoResult(success=True)


# ---------------------------------------------------------------------------
# Recommendations
# ---------------------------------------------------------------------------

@app.get("/leagues/{league_id}/recommendations", response_model=RecommendationsResponse, tags=["recommendations"])
def get_recommendations(league_id: str, ai: bool = Query(True, description="Include NVIDIA NIM AI analysis"),
                        user_id: str = Depends(get_current_user)):
    """Trigger the recommendation engine for the active user's turn."""
    league = _load_or_404(league_id, user_id)
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
def remove_league(league_id: str, user_id: str = Depends(get_current_user)):
    """Delete a league (admin convenience)."""
    if not delete_league(league_id, user_id):
        raise HTTPException(status_code=404, detail=f"League '{league_id}' not found")
    return {"success": True}

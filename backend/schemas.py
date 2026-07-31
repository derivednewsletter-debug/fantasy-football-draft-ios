"""Pydantic request/response models for the Fantasy Draft API."""

from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# League
# ---------------------------------------------------------------------------

class LeagueCreate(BaseModel):
    """Payload for creating a new league."""

    name: str = Field(..., min_length=1, max_length=80, description="League name")
    num_teams: int = Field(4, ge=2, le=32, description="Number of teams")
    user_team_number: int = Field(1, ge=1, description="Your pick position (1-indexed)")
    scoring_format: str = Field("PPR", description="PPR, 0.5_PPR, Standard, or 2QB/Superflex")


class LeagueSummary(BaseModel):
    """Lightweight league descriptor for the dashboard list."""

    name: str
    num_teams: int
    user_team_number: int
    scoring_format: str
    current_round: int
    overall_pick: int
    is_active: bool
    completed: bool
    total_picks: int
    team_on_clock: int


# ---------------------------------------------------------------------------
# Draft state
# ---------------------------------------------------------------------------

class LeagueState(BaseModel):
    """Full snapshot of a league's live draft state."""

    name: str
    num_teams: int
    user_team_number: int
    scoring_format: str
    roster_slots: dict[str, int]
    current_round: int
    current_pick_in_round: int
    overall_pick: int
    is_active: bool
    completed: bool
    team_on_clock: int
    is_user_on_clock: bool
    picks_before_user: int
    draft_log: list[dict]
    teams: list[dict]
    available_players: list[dict]
    matrix: list[dict]


class PickRequest(BaseModel):
    """Submit a draft pick. `player_name` is fuzzy-matched against the pool."""

    player_name: str = Field(..., min_length=1, description="Player name (fuzzy match OK)")


class PickResult(BaseModel):
    success: bool
    pick: Optional[dict] = None
    error: Optional[str] = None


class UndoResult(BaseModel):
    success: bool
    error: Optional[str] = None


# ---------------------------------------------------------------------------
# Recommendations
# ---------------------------------------------------------------------------

class Recommendation(BaseModel):
    """One recommended player from the engine."""

    name: str
    position: str
    team: str
    projected_points: float
    adp: float
    vbd: Optional[float] = None
    score: Optional[float] = None
    turn_loss_pct: Optional[float] = None
    rationale: Optional[str] = None


class RecommendationsResponse(BaseModel):
    safe_picks: list[Recommendation]
    upside_picks: list[Recommendation]
    sleepers: list[Recommendation]
    all_ranked: list[Recommendation]
    picks_before_user: int
    ai_analysis: Optional[str] = None
    ai_top_target: Optional[Recommendation] = None


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

class HealthResponse(BaseModel):
    status: str
    leagues: int
    ai_available: bool

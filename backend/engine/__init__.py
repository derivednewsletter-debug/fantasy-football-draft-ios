"""Core fantasy football draft engine (FastAPI backend package)."""

from .models import League, Player, Pick, Team, ROSTER_PRESETS
from .engine import (
    build_draft_matrix,
    compute_vbd,
    get_positional_baselines,
    picks_before_next_user_turn,
    recommend,
    recommend_ai,
    roster_needs_score,
)

__all__ = [
    "League",
    "Player",
    "Pick",
    "Team",
    "ROSTER_PRESETS",
    "build_draft_matrix",
    "compute_vbd",
    "get_positional_baselines",
    "picks_before_next_user_turn",
    "recommend",
    "recommend_ai",
    "roster_needs_score",
]

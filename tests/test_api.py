"""End-to-end API tests for the Fantasy Draft Assistant backend.

Run from fantasy_app/ with:
    .venv/bin/python -m pytest tests/ -v
"""

from __future__ import annotations

import pytest

from tests.conftest import url_escape


# ===========================================================================
# League creation
# ===========================================================================

@pytest.mark.parametrize("num_teams", [8, 10, 12, 14])
@pytest.mark.parametrize("scoring", ["PPR", "0.5_PPR", "Standard", "2QB/Superflex"])
async def test_create_league_variants(client, num_teams: int, scoring: str):
    """POST /leagues works across team sizes and scoring formats."""
    # League names are URL path segments, so "/" is not allowed in the name
    # (the scoring *format* still supports it via the body).
    name = f"{scoring.replace('/', '-')}-{num_teams}L"
    resp = await client.post(
        "/leagues",
        json={"name": name, "num_teams": num_teams,
              "user_team_number": 1, "scoring_format": scoring},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["name"] == name
    assert body["num_teams"] == num_teams
    assert body["scoring_format"] == scoring

    state = await client.get(f"/leagues/{url_escape(name)}/state")
    assert state.status_code == 200
    s = state.json()
    assert len(s["teams"]) == num_teams
    assert len(s["matrix"]) == num_teams
    # Superflex requires 2 QB starters
    if scoring == "2QB/Superflex":
        assert s["roster_slots"]["QB"] == 2
    else:
        assert s["roster_slots"]["QB"] == 1


async def test_create_league_rejects_slash_in_name(client):
    """Names containing '/' are rejected — they can't round-trip through URLs."""
    resp = await client.post(
        "/leagues",
        json={"name": "A/B League", "num_teams": 8,
              "user_team_number": 1, "scoring_format": "PPR"},
    )
    assert resp.status_code == 400
    assert "cannot contain" in resp.json()["detail"]


async def test_create_league_user_pick_clamped(client):
    """user_team_number beyond team count is clamped to the league size."""
    resp = await client.post(
        "/leagues",
        json={"name": "Clamp League", "num_teams": 8,
              "user_team_number": 99, "scoring_format": "PPR"},
    )
    assert resp.status_code == 201
    assert resp.json()["user_team_number"] == 8


async def test_create_league_duplicate_conflict(client):
    """Duplicate league name returns 409."""
    payload = {"name": "Dup League", "num_teams": 10,
               "user_team_number": 3, "scoring_format": "PPR"}
    assert (await client.post("/leagues", json=payload)).status_code == 201
    resp = await client.post("/leagues", json=payload)
    assert resp.status_code == 409


async def test_league_list(client, make_league):
    await make_league(client, name="List A")
    await make_league(client, name="List B", num_teams=10)
    resp = await client.get("/leagues")
    assert resp.status_code == 200
    names = {l["name"] for l in resp.json()}
    assert {"List A", "List B"} <= names


async def test_unknown_league_404(client):
    resp = await client.get("/leagues/Nope/state")
    assert resp.status_code == 404


# ===========================================================================
# Draft picks, snake math, and turn calculation
# ===========================================================================

async def test_pick_logging_and_snake_round1(client, make_league):
    """Round 1 picks go 1 -> N in order; pick metadata is logged."""
    await make_league(client, name="Snake R1", num_teams=12, user_team_number=4)
    name = "Snake R1"

    for expected_team in range(1, 13):
        state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
        assert state["team_on_clock"] == expected_team
        assert state["current_round"] == 1
        assert state["current_pick_in_round"] == expected_team
        assert state["overall_pick"] == expected_team

        # Pick the first available player
        first = state["available_players"][0]
        resp = await client.post(
            f"/leagues/{url_escape(name)}/pick",
            json={"player_name": first["name"]},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["success"] is True

    # After 12 picks: round 2 begins, snake reverses to team 12
    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    assert state["current_round"] == 2
    assert state["current_pick_in_round"] == 1
    assert state["team_on_clock"] == 12
    assert len(state["draft_log"]) == 12
    assert state["overall_pick"] == 13

    # Log integrity: pick 1 belongs to team 1, has correct metadata
    first_pick = state["draft_log"][0]
    assert first_pick["team_number"] == 1
    assert first_pick["overall_pick"] == 1
    assert first_pick["round_number"] == 1
    assert first_pick["player_position"] in {"QB", "RB", "WR", "TE", "K", "DST"}
    assert first_pick["player_name"]  # non-empty


async def test_snake_reverse_round2(client, make_league):
    """Round 2 (even) goes N -> 1; the pick after team 12 is team 11."""
    await make_league(client, name="Snake R2", num_teams=12, user_team_number=4)
    name = "Snake R2"

    # Complete round 1
    for _ in range(12):
        state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
        first = state["available_players"][0]
        await client.post(f"/leagues/{url_escape(name)}/pick", json={"player_name": first["name"]})

    # Round 2 pick 1 = team 12, pick 2 = team 11
    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    first = state["available_players"][0]
    await client.post(f"/leagues/{url_escape(name)}/pick", json={"player_name": first["name"]})
    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    assert state["team_on_clock"] == 11
    assert state["current_pick_in_round"] == 2
    assert state["draft_log"][-1]["team_number"] == 12


async def test_turn_calculation_picks_before_user(client, make_league):
    """picks_before_user reports correctly in round 1 and reversed round 2."""
    await make_league(client, name="Turns", num_teams=12, user_team_number=4)
    name = "Turns"

    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    # Team 1 on clock, user is team 4 -> 3 picks before user's turn
    assert state["picks_before_user"] == 3
    assert state["is_user_on_clock"] is False

    # Advance to the user's pick (3 picks later)
    for _ in range(3):
        s = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
        await client.post(f"/leagues/{url_escape(name)}/pick",
                          json={"player_name": s["available_players"][0]["name"]})
    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    assert state["is_user_on_clock"] is True
    assert state["picks_before_user"] == 0
    assert state["team_on_clock"] == 4

    # Finish round 1 (9 more picks -> 12 total) so round 2 begins reversed.
    # Team 4 drafts 8th in round 2 (order 12,11,...,1), so 8 picks before.
    for _ in range(9):
        s = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
        await client.post(f"/leagues/{url_escape(name)}/pick",
                          json={"player_name": s["available_players"][0]["name"]})
    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    assert state["current_round"] == 2
    assert state["picks_before_user"] == 8


async def test_pick_marks_player_unavailable(client, make_league):
    """A drafted player leaves the available pool and joins the team roster."""
    await make_league(client, name="Pool Check", num_teams=12, user_team_number=1)
    name = "Pool Check"

    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    target = state["available_players"][0]
    assert target["is_drafted"] is False

    resp = await client.post(f"/leagues/{url_escape(name)}/pick",
                             json={"player_name": target["name"]})
    assert resp.json()["success"] is True

    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    names = {p["name"] for p in state["available_players"]}
    assert target["name"] not in names
    assert state["teams"][0]["roster"][0]["name"] == target["name"]


async def test_draft_completion_state(client, make_league):
    """Drafting every slot eventually marks the draft completed."""
    await make_league(client, name="Full Draft", num_teams=4, user_team_number=1)
    name = "Full Draft"
    slots_per_team = 15  # PPR: 1+2+2+1+1+1+1+6 = 15

    for _ in range(4 * slots_per_team):
        state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
        if state["completed"]:
            break
        assert state["available_players"], "pool ran dry before draft completed"
        await client.post(f"/leagues/{url_escape(name)}/pick",
                          json={"player_name": state["available_players"][0]["name"]})

    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    assert state["completed"] is True
    assert len(state["draft_log"]) == 4 * slots_per_team


# ===========================================================================
# Undo / rollback
# ===========================================================================

async def test_undo_restores_state(client, make_league):
    """Undo removes the last pick and restores player availability."""
    await make_league(client, name="Undo Restore", num_teams=12, user_team_number=1)
    name = "Undo Restore"

    # Pick 2 players
    picked = []
    for _ in range(2):
        state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
        target = state["available_players"][0]
        picked.append(target["name"])
        await client.post(f"/leagues/{url_escape(name)}/pick",
                          json={"player_name": target["name"]})

    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    assert len(state["draft_log"]) == 2
    assert state["overall_pick"] == 3

    resp = await client.post(f"/leagues/{url_escape(name)}/undo")
    assert resp.status_code == 200
    assert resp.json()["success"] is True

    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    assert len(state["draft_log"]) == 1
    assert state["overall_pick"] == 2
    names = {p["name"] for p in state["available_players"]}
    assert picked[1] in names          # second player freed
    assert picked[0] not in names      # first player still drafted
    assert state["teams"][0]["roster"][0]["name"] == picked[0]


async def test_undo_snake_math_rolls_back_round(client, make_league):
    """Undo across a round boundary restores round/pick state exactly."""
    await make_league(client, name="Undo Round", num_teams=12, user_team_number=1)
    name = "Undo Round"

    # 12 picks -> round 2, pick 1, team 12 on clock
    for _ in range(12):
        state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
        await client.post(f"/leagues/{url_escape(name)}/pick",
                          json={"player_name": state["available_players"][0]["name"]})

    await client.post(f"/leagues/{url_escape(name)}/undo")

    state = (await client.get(f"/leagues/{url_escape(name)}/state")).json()
    assert state["current_round"] == 1
    assert state["current_pick_in_round"] == 12
    assert state["team_on_clock"] == 12
    assert state["overall_pick"] == 12
    assert len(state["draft_log"]) == 11


async def test_undo_empty_log_fails_gracefully(client, make_league):
    await make_league(client, name="Undo Empty", num_teams=8, user_team_number=1)
    resp = await client.post("/leagues/Undo%20Empty/undo")
    assert resp.status_code == 200
    body = resp.json()
    assert body["success"] is False
    assert body["error"]


# ===========================================================================
# Recommendations (NVIDIA NIM mocked)
# ===========================================================================

async def test_recommendations_schema_without_ai(client, make_league):
    """ai=false returns VBD picks with the full schema and no AI fields."""
    await make_league(client, name="Rec VBD", num_teams=12, user_team_number=4)
    resp = await client.get("/leagues/Rec%20VBD/recommendations?ai=false")
    assert resp.status_code == 200, resp.text
    recs = resp.json()

    assert len(recs["safe_picks"]) == 3
    assert len(recs["upside_picks"]) == 3
    assert len(recs["sleepers"]) == 3
    assert len(recs["all_ranked"]) > 0
    assert recs["picks_before_user"] == 3
    assert recs["ai_analysis"] is None
    assert recs["ai_top_target"] is None

    for category in ("safe_picks", "upside_picks", "sleepers"):
        for r in recs[category]:
            assert r["name"]
            assert r["position"] in {"QB", "RB", "WR", "TE", "K", "DST"}
            assert r["team"]
            assert r["projected_points"] > 0
            assert r["adp"] > 0


async def test_recommendations_with_ai_mock(client, make_league, monkeypatch):
    """Mock NVIDIA NIM response and verify the endpoint parses it into schema."""
    await make_league(client, name="Rec AI", num_teams=12, user_team_number=4)

    fake_ai = {
        "ai_analysis": "You need RB depth before your next turn.",
        "ai_top_target": {"name": "Bijan Robinson", "position": "RB",
                          "team": "ATL", "rationale": "Workhorse volume."},
        "ai_safe_picks": [],
        "ai_upside_picks": [],
        "ai_sleepers": [],
        "vbd_safe_picks": [],
        "vbd_upside_picks": [],
        "vbd_sleepers": [],
        "picks_before_user": 3,
    }

    import backend.main as main_mod

    monkeypatch.setattr(main_mod, "recommend_ai", lambda league: fake_ai)

    resp = await client.get("/leagues/Rec%20AI/recommendations?ai=true")
    assert resp.status_code == 200, resp.text
    recs = resp.json()

    assert recs["ai_analysis"] == "You need RB depth before your next turn."
    assert recs["ai_top_target"]["name"] == "Bijan Robinson"
    assert recs["ai_top_target"]["position"] == "RB"
    # VBD fallbacks still populate even when AI returns no picks
    assert len(recs["safe_picks"]) == 3
    assert len(recs["sleepers"]) == 3


async def test_recommendations_ai_failure_falls_back(client, make_league, monkeypatch):
    """When the AI call returns None (unavailable), the endpoint still works."""
    await make_league(client, name="Rec Fallback", num_teams=12, user_team_number=4)

    import backend.main as main_mod

    monkeypatch.setattr(main_mod, "recommend_ai", lambda league: None)

    resp = await client.get("/leagues/Rec%20Fallback/recommendations?ai=true")
    assert resp.status_code == 200
    recs = resp.json()
    assert recs["ai_analysis"] is None
    assert recs["ai_top_target"] is None
    assert len(recs["safe_picks"]) == 3
    assert len(recs["all_ranked"]) > 0


# ===========================================================================
# Fuzzy name matching edge cases
# ===========================================================================

async def test_fuzzy_match_misspelling(client, make_league):
    """A misspelled player name resolves to the right player."""
    await make_league(client, name="Fuzzy Misspell", num_teams=12, user_team_number=1)
    resp = await client.post("/leagues/Fuzzy%20Misspell/pick",
                             json={"player_name": "Patrick Mahom"})
    assert resp.json()["success"] is True
    assert resp.json()["pick"]["player_name"] == "Patrick Mahomes"


async def test_fuzzy_match_special_characters(client, make_league):
    """Names with apostrophes and initials still fuzzy-match."""
    await make_league(client, name="Fuzzy Special", num_teams=12, user_team_number=1)
    # "De'Von Achane" -> apostrophe spelling variants
    resp = await client.post("/leagues/Fuzzy%20Special/pick",
                             json={"player_name": "Devon Achane"})
    assert resp.json()["success"] is True
    assert resp.json()["pick"]["player_name"] == "De'Von Achane"


async def test_fuzzy_match_initials(client, make_league):
    """A.J. Brown matches when typed without periods."""
    await make_league(client, name="Fuzzy Initials", num_teams=12, user_team_number=1)
    resp = await client.post("/leagues/Fuzzy%20Initials/pick",
                             json={"player_name": "AJ Brown"})
    assert resp.json()["success"] is True
    assert resp.json()["pick"]["player_name"] == "A.J. Brown"


async def test_fuzzy_match_garbage_rejected(client, make_league):
    """Garbage queries must NOT fuzzy-match into a real pick."""
    await make_league(client, name="Fuzzy Garbage", num_teams=12, user_team_number=1)
    resp = await client.post("/leagues/Fuzzy%20Garbage/pick",
                             json={"player_name": "zzz not a real player"})
    body = resp.json()
    assert body["success"] is False
    assert body["error"]


async def test_fuzzy_match_long_nonsense_rejected(client, make_league):
    """Long nonsense that length-scores high is still rejected."""
    await make_league(client, name="Fuzzy Long", num_teams=12, user_team_number=1)
    resp = await client.post("/leagues/Fuzzy%20Long/pick",
                             json={"player_name": "banana republic zanzibar"})
    body = resp.json()
    assert body["success"] is False


async def test_fuzzy_match_draft_board_reflects_pick(client, make_league):
    """The board matrix reflects the fuzzy-matched pick."""
    await make_league(client, name="Fuzzy Board", num_teams=12, user_team_number=1)
    resp = await client.post("/leagues/Fuzzy%20Board/pick",
                             json={"player_name": "Christian McCaff"})
    assert resp.json()["success"] is True
    state = (await client.get("/leagues/Fuzzy%20Board/state")).json()
    assert state["matrix"][0]["roster"][0]["name"] == "Christian McCaffrey"
    assert state["matrix"][0]["pick_count"] == 1


# ===========================================================================
# WebSocket live sync
# ===========================================================================
# httpx's ASGITransport doesn't support WebSockets, so these use Starlette's
# TestClient (sync tests; pytest-asyncio's auto mode only affects async tests).

from fastapi.testclient import TestClient  # noqa: E402

from backend.main import app as _app  # noqa: E402


def test_ws_initial_state_envelope():
    """On connect the client receives the current state immediately."""
    with TestClient(_app) as client:
        resp = client.post("/leagues", json={
            "name": "WS Initial", "num_teams": 12,
            "user_team_number": 4, "scoring_format": "PPR",
        })
        assert resp.status_code == 201

        with client.websocket_connect("/leagues/WS%20Initial/ws") as ws:
            env = ws.receive_json()
            assert env["type"] == "state"
            assert env["league_id"] == "WS Initial"
            st = env["state"]
            assert st["overall_pick"] == 1
            assert st["current_round"] == 1
            assert st["team_on_clock"] == 1
            assert len(st["matrix"]) == 12
            assert st["picks_before_user"] == 3


def test_ws_broadcasts_pick_to_all_clients():
    """A pick made over REST is pushed to every connected device."""
    with TestClient(_app) as client:
        client.post("/leagues", json={
            "name": "WS Broadcast", "num_teams": 8,
            "user_team_number": 1, "scoring_format": "PPR",
        })

        with client.websocket_connect("/leagues/WS%20Broadcast/ws") as ws:
            ws.receive_json()  # initial snapshot

            pick = client.post("/leagues/WS%20Broadcast/pick",
                               json={"player_name": "Patrick Mahomes"})
            assert pick.json()["success"] is True

            update = ws.receive_json()
            assert update["type"] == "state"
            assert update["state"]["overall_pick"] == 2
            assert update["state"]["team_on_clock"] == 2
            assert update["state"]["draft_log"][-1]["player_name"] == "Patrick Mahomes"


def test_ws_broadcasts_undo():
    """Undo pushes the rolled-back state to subscribers."""
    with TestClient(_app) as client:
        client.post("/leagues", json={
            "name": "WS Undo", "num_teams": 8,
            "user_team_number": 1, "scoring_format": "PPR",
        })

        with client.websocket_connect("/leagues/WS%20Undo/ws") as ws:
            ws.receive_json()
            client.post("/leagues/WS%20Undo/pick", json={"player_name": "Josh Allen"})
            ws.receive_json()  # pick broadcast

            undo = client.post("/leagues/WS%20Undo/undo")
            assert undo.json()["success"] is True

            update = ws.receive_json()
            assert update["type"] == "state"
            assert update["state"]["overall_pick"] == 1
            assert update["state"]["draft_log"] == []


def test_ws_ping_pong():
    """The server answers ping frames so clients can keep alive."""
    with TestClient(_app) as client:
        client.post("/leagues", json={
            "name": "WS Ping", "num_teams": 8,
            "user_team_number": 1, "scoring_format": "PPR",
        })
        with client.websocket_connect("/leagues/WS%20Ping/ws") as ws:
            ws.receive_json()  # initial snapshot
            ws.send_text("ping")
            assert ws.receive_text() == "pong"


def test_ws_unknown_league_gets_error():
    """Connecting to a nonexistent league returns an error envelope."""
    with TestClient(_app) as client:
        with client.websocket_connect("/leagues/NoSuchLeague/ws") as ws:
            env = ws.receive_json()
            assert env["type"] == "error"
            assert "not found" in env["detail"]

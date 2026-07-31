"""Smoke test for the FastAPI backend — run: python3 _smoke_test.py"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from fastapi.testclient import TestClient  # noqa: E402

from backend.main import app  # noqa: E402

client = TestClient(app)

passed = 0
failed = 0


def check(label: str, ok: bool, detail: str = ""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  PASS  {label}")
    else:
        failed += 1
        print(f"  FAIL  {label}  {detail}")


print("== Health ==")
r = client.get("/")
check("GET / -> 200", r.status_code == 200)
check("status == ok", r.json().get("status") == "ok", str(r.json()))

print("== Create league ==")
r = client.post(
    "/leagues",
    json={"name": "Test League", "num_teams": 12, "user_team_number": 4, "scoring_format": "PPR"},
)
check("POST /leagues -> 201", r.status_code == 201, str(r.status_code))
data = r.json()
check("league name echoed", data.get("name") == "Test League", str(data))
check("user_team_number == 4", data.get("user_team_number") == 4)

print("== Duplicate league ==")
r = client.post(
    "/leagues",
    json={"name": "Test League", "num_teams": 12, "user_team_number": 4, "scoring_format": "PPR"},
)
check("duplicate -> 409", r.status_code == 409, str(r.status_code))

print("== League list ==")
r = client.get("/leagues")
check("GET /leagues -> 200", r.status_code == 200)
check("list has 1 league", len(r.json()) == 1, str(r.json()))

print("== State ==")
r = client.get("/leagues/Test%20League/state")
check("GET state -> 200", r.status_code == 200, str(r.status_code))
st = r.json()
check("round 1 pick 1", st["current_round"] == 1 and st["current_pick_in_round"] == 1)
check("on clock == 1", st["team_on_clock"] == 1)
check("user (4) NOT on clock", st["is_user_on_clock"] is False)
check("matrix has 12 teams", len(st["matrix"]) == 12, str(len(st.get("matrix", []))))
check("player pool non-empty", len(st["available_players"]) > 100, str(len(st.get("available_players", []))))

print("== Pick (fuzzy match) ==")
r = client.post("/leagues/Test%20League/pick", json={"player_name": "Patrick Mahom"})
check("POST pick -> 200", r.status_code == 200)
pj = r.json()
check("pick success", pj["success"], str(pj))
check("picked Mahomes", pj["pick"]["player_name"] == "Patrick Mahomes", str(pj))

print("== State after pick ==")
r = client.get("/leagues/Test%20League/state")
st = r.json()
check("advanced to pick 2", st["overall_pick"] == 2, str(st["overall_pick"]))
check("on clock == 2", st["team_on_clock"] == 2)

print("== Bad player ==")
r = client.post("/leagues/Test%20League/pick", json={"player_name": "zzz not a real player"})
check("bad pick handled", r.json()["success"] is False, str(r.json()))

print("== Undo ==")
r = client.post("/leagues/Test%20League/undo")
check("undo success", r.json()["success"] is True, str(r.json()))
r = client.get("/leagues/Test%20League/state")
check("back to pick 1", r.json()["overall_pick"] == 1, str(r.json()["overall_pick"]))

print("== Undo empty ==")
r = client.post("/leagues/Test%20League/undo")
check("second undo fails gracefully", r.json()["success"] is False, str(r.json()))

print("== Recommendations (VBD only, no AI) ==")
r = client.get("/leagues/Test%20League/recommendations?ai=false")
check("recs -> 200", r.status_code == 200, str(r.status_code))
recs = r.json()
check("3 safe picks", len(recs["safe_picks"]) == 3, str(len(recs.get("safe_picks", []))))
check("3 upside picks", len(recs["upside_picks"]) == 3)
check("3 sleepers", len(recs["sleepers"]) == 3)
check("all_ranked present", len(recs["all_ranked"]) > 0)
check("picks_before_user present", "picks_before_user" in recs)
check("ai_analysis None (ai off)", recs["ai_analysis"] is None)

print("== 404 ==")
r = client.get("/leagues/Nope/state")
check("unknown league -> 404", r.status_code == 404)

print("== Delete ==")
r = client.delete("/leagues/Test%20League")
check("delete -> 200", r.status_code == 200)
r = client.get("/leagues")
check("list empty after delete", len(r.json()) == 0)

print(f"\nRESULT: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

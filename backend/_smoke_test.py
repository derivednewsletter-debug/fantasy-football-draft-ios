"""Smoke test for the FastAPI backend — run: python3 _smoke_test.py"""

from __future__ import annotations

import sys
import uuid
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


print("== Health ==\u200b")
r = client.get("/")
check("GET / -> 200", r.status_code == 200)
check("status == ok", r.json().get("status") == "ok", str(r.json()))

print("== Auth: signup + login ==")
email = f"smoke-{uuid.uuid4().hex[:8]}@test.com"
r = client.post("/auth/signup", json={"email": email, "password": "secret123"})
check("POST /auth/signup -> 201", r.status_code == 201, str(r.status_code))
token = r.json()["token"]
headers = {"Authorization": f"Bearer {token}"}
check("signup returns token", bool(token))

r = client.post("/auth/login", json={"email": email, "password": "secret123"})
check("POST /auth/login -> 200", r.status_code == 200)
check("login returns token", bool(r.json().get("token")))

r = client.get("/auth/me", headers=headers)
check("GET /auth/me -> 200", r.status_code == 200, str(r.status_code))
check("me echoes email", r.json()["email"] == email, str(r.json()))

r = client.get("/leagues")
check("unauthed GET /leagues -> 401", r.status_code == 401, str(r.status_code))

print("== Create league ==")
r = client.post(
    "/leagues",
    json={"name": "Test League", "num_teams": 12, "user_team_number": 4, "scoring_format": "PPR"},
    headers=headers,
)
check("POST /leagues -> 201", r.status_code == 201, str(r.status_code))
data = r.json()
check("league name echoed", data.get("name") == "Test League", str(data))
check("user_team_number == 4", data.get("user_team_number") == 4)

print("== Duplicate league ==")
r = client.post(
    "/leagues",
    json={"name": "Test League", "num_teams": 12, "user_team_number": 4, "scoring_format": "PPR"},
    headers=headers,
)
check("duplicate -> 409", r.status_code == 409, str(r.status_code))

print("== League list ==")
r = client.get("/leagues", headers=headers)
check("GET /leagues -> 200", r.status_code == 200)
check("list has 1 league", len(r.json()) == 1, str(r.json()))

print("== State ==")
r = client.get("/leagues/Test%20League/state", headers=headers)
check("GET state -> 200", r.status_code == 200, str(r.status_code))
st = r.json()
check("round 1 pick 1", st["current_round"] == 1 and st["current_pick_in_round"] == 1)
check("on clock == 1", st["team_on_clock"] == 1)
check("user (4) NOT on clock", st["is_user_on_clock"] is False)
check("matrix has 12 teams", len(st["matrix"]) == 12, str(len(st.get("matrix", []))))
check("player pool non-empty", len(st["available_players"]) > 100, str(len(st.get("available_players", []))))

print("== Pick (fuzzy match) ==")
r = client.post("/leagues/Test%20League/pick", json={"player_name": "Patrick Mahom"}, headers=headers)
check("POST pick -> 200", r.status_code == 200)
pj = r.json()
check("pick success", pj["success"], str(pj))
check("picked Mahomes", pj["pick"]["player_name"] == "Patrick Mahomes", str(pj))

print("== State after pick ==")
r = client.get("/leagues/Test%20League/state", headers=headers)
st = r.json()
check("advanced to pick 2", st["overall_pick"] == 2, str(st["overall_pick"]))
check("on clock == 2", st["team_on_clock"] == 2)

print("== Bad player ==")
r = client.post("/leagues/Test%20League/pick", json={"player_name": "zzz not a real player"}, headers=headers)
check("bad pick handled", r.json()["success"] is False, str(r.json()))

print("== Undo ==")
r = client.post("/leagues/Test%20League/undo", headers=headers)
check("undo success", r.json()["success"] is True, str(r.json()))
r = client.get("/leagues/Test%20League/state", headers=headers)
check("back to pick 1", r.json()["overall_pick"] == 1, str(r.json()["overall_pick"]))

print("== Undo empty ==")
r = client.post("/leagues/Test%20League/undo", headers=headers)
check("second undo fails gracefully", r.json()["success"] is False, str(r.json()))

print("== Recommendations (VBD only, no AI) ==")
r = client.get("/leagues/Test%20League/recommendations?ai=false", headers=headers)
check("recs -> 200", r.status_code == 200, str(r.status_code))
recs = r.json()
check("3 safe picks", len(recs["safe_picks"]) == 3, str(len(recs.get("safe_picks", []))))
check("3 upside picks", len(recs["upside_picks"]) == 3)
check("3 sleepers", len(recs["sleepers"]) == 3)
check("all_ranked present", len(recs["all_ranked"]) > 0)
check("picks_before_user present", "picks_before_user" in recs)
check("ai_analysis None (ai off)", recs["ai_analysis"] is None)

print("== 404 ==")
r = client.get("/leagues/Nope/state", headers=headers)
check("unknown league -> 404", r.status_code == 404)

print("== Delete ==")
r = client.delete("/leagues/Test%20League", headers=headers)
check("delete -> 200", r.status_code == 200)
r = client.get("/leagues", headers=headers)
check("list empty after delete", len(r.json()) == 0)

print("== Logout ==")
r = client.post("/auth/logout", headers=headers)
check("logout -> 200", r.status_code == 200)
r = client.get("/auth/me", headers=headers)
check("token revoked after logout -> 401", r.status_code == 401, str(r.status_code))

print(f"\nRESULT: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

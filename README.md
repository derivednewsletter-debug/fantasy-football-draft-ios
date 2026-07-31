# Fantasy Draft Assistant — iOS + FastAPI

Multi-league fantasy football draft engine, wrapped in a FastAPI REST backend
and fronted by a native **SwiftUI iOS 17+** app. The backend reuses the exact
draft engine from the Fantasy Draft CLI (snake order, VBD scoring, roster-need
analysis) plus optional **NVIDIA NIM** AI recommendations.

```
fantasy_app/
├── backend/                 # FastAPI REST backend
│   ├── main.py              # Routes: auth + league + WebSocket
│   ├── auth.py              # Email/password auth (PBKDF2), bearer sessions
│   ├── schemas.py           # Pydantic request/response models
│   ├── default_projections.csv
│   └── engine/              # Core draft engine (models, VBD, AI advisor, store)
└── ios_app/
    └── FantasyDraftAssistant/
        ├── FantasyDraftAssistant.xcodeproj
        └── FantasyDraftAssistant/
            ├── App/         # SwiftUI entry point (auth gate)
            ├── Models/      # Codable structs (League, Player, Pick, Position, Auth)
            ├── Services/    # APIService.swift (URLSession async/await, bearer auth)
            ├── ViewModels/  # DraftViewModel, AuthViewModel (@Observable)
            └── Views/       # AuthView, LeagueListView, DraftRoomView, board/roster/AI views
```

---

## 1. Backend

### Requirements

Python 3.11+.

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

### Run

```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

Interactive docs: http://127.0.0.1:8000/docs

### Accounts & per-user storage

Every league belongs to an account. Sign up with an email + password, and all
subsequent requests authenticate with a **bearer token**:

```bash
# Create an account (or log in — same shape, /auth/login)
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"hunter2"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')

# Use it on every league call
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:8000/leagues
```

- Passwords are hashed with **PBKDF2-HMAC-SHA256** (200k iterations, per-user
  salt); sessions are opaque random tokens with a 30-day expiry.
- Data is stored **per user** under `backend/data/users/<user_id>/` — account A
  can never see account B's leagues.
- Log out with `POST /auth/logout` to revoke the token.

### NVIDIA NIM AI (optional)

Set the API key to enable AI recommendations:

```bash
export NVIDIA_API_KEY="nvapi-..."
# or: export NVIDIA_NIM_API_KEY="nvapi-..."
```

The endpoint falls back to pure VBD (statistical) recommendations when the key
is missing or the AI call fails.

### Smoke test

```bash
python3 backend/_smoke_test.py    # 42 checks: signup, login, create, state, pick, undo, recs
```

### Automated E2E test suite

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r backend/requirements.txt pytest pytest-asyncio httpx
pytest tests/ -v                  # 52 checks across every endpoint
```

Covers: signup/login/logout/me, per-user league isolation, 401s on missing or
expired tokens, WebSocket auth (bad token → 4401), league creation across team
sizes (8/10/12/14) and scoring formats (PPR/Superflex), snake-order pick
progression and turn calculation, undo rollback integrity, NVIDIA NIM
recommendations (mocked), and fuzzy name matching edge cases (misspellings,
apostrophes, initials, garbage queries).

The suite runs against an isolated temp data dir — no real leagues are
created, and it works with or without the NVIDIA API key.

---

## 2. iOS App

### Run the test suite (requires a Mac with Xcode)

```bash
cd ios_app
xcodebuild test \
  -scheme FantasyDraftAssistant \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest'
```

- **Unit tests** (`FantasyDraftAssistantTests`): decode the backend JSON
  contract into the Swift models, verify snake_case→camelCase conversion,
  Position enum mapping/colors, and turn-probability flags.
- **UI tests** (`FantasyDraftAssistantUITests`): launch the app and verify the
  league dashboard renders.
- The shared scheme lives in `xcshareddata/xcschemes/` so the command works
  headlessly (no need to open Xcode first).

### Open in Xcode

```bash
open ios_app/FantasyDraftAssistant.xcodeproj
```

- Target: iOS 17.0+, SwiftUI, dark-first UI.
- Select a simulator (or your device) and hit Run.

### Sign in & point the app at your backend

The app opens on a **sign-in screen**: enter your email + password (or switch
to **Create an account**). The **Backend URL** field on that screen sets where
the app connects — no more dead localhost defaults:

- **Simulator + local backend**: `http://127.0.0.1:8000` (the default).
- **Physical device**: your Mac's LAN IP, e.g. `http://192.168.x.x:8000` (same
  Wi-Fi; Info.plist allows local networking).
- **Deployed backend**: `https://your-app.vercel.app`.

The URL and auth token are persisted in `UserDefaults` (`apiBaseURL`,
`authToken`, `authEmail`), so you only sign in once. If the session expires,
the app returns to the sign-in screen automatically.

### Screens

| Screen | What it does |
|--------|--------------|
| **Sign In** | Email/password sign-in + create-account, with an editable **Backend URL** field |
| **League List** | All leagues (per account) with status badges (`Drafting — Pick 3.04`, `On the clock`) + quick-create form (teams, your pick, scoring) |
| **Draft Room** | Round/pick header, flashing **YOU ARE ON THE CLOCK** banner, countdown of picks until your turn, undo last pick |
| **Quick Pick Bar** | Type-ahead autocomplete (players & teams) + one-tap **Draft** |
| **Draft Board** | Every pick pick-by-pick, color-coded by position (QB red, RB green, WR blue, TE yellow); your picks highlighted |
| **My Roster** | Starter slots laid out by position with empty-slot callouts + bench grid |
| **AI Picks** | Top-3 Safe / Upside / Sleeper cards with **turn-loss probability** flags; full AI breakdown sheet |

---

## 3. API Reference

Base URL: `http://127.0.0.1:8000`

| Method | Path | Description |
|--------|------|-------------|
| `GET`  | `/` | Health check (status, league count, AI availability) — public |
| `POST` | `/auth/signup` | Create account `{email, password}` → `{token, email}` |
| `POST` | `/auth/login` | Log in → `{token, email}` (401 on bad credentials) |
| `POST` | `/auth/logout` | Revoke the current token |
| `GET`  | `/auth/me` | Current account email |
| `GET`  | `/leagues` | List **your** leagues (Bearer token required) |
| `POST` | `/leagues` | Create league `{name, num_teams, user_team_number, scoring_format}` |
| `GET`  | `/leagues/{id}/state` | Full draft state (round, pick, on-the-clock team, rosters, board matrix) |
| `POST` | `/leagues/{id}/pick` | `{player_name}` — fuzzy-matched, drafted by the team on the clock |
| `POST` | `/leagues/{id}/undo` | Roll back the last pick |
| `GET`  | `/leagues/{id}/recommendations?ai=true` | VBD + NVIDIA AI recommendations |
| `DELETE` | `/leagues/{id}` | Delete a league |
| `WS`   | `/leagues/{id}/ws` | Live draft feed — **auth via `Authorization: Bearer` header (or `?token=`)**; pushes a fresh state envelope on every pick/undo from any device |

All league and auth-inspection routes require `Authorization: Bearer <token>`.
League IDs are URL-encoded names (e.g. `Friday%20Night%20Legends`).

### Live sync (WebSocket)

Every league exposes a WebSocket feed at `/leagues/{id}/ws`. On connect it
immediately sends the current draft state, then broadcasts a fresh state
envelope after **every** successful pick or undo — so any number of devices
in the room stay in sync with no pull-to-refresh.

```json
{"type": "state", "league_id": "Friday Night Legends", "state": { ...full draft state... }}
```

The iOS app connects automatically when you enter a draft room (see the **LIVE**
indicator) and disconnects when you leave. The socket authenticates with the
account's bearer token. If the socket drops it reconnects with capped
exponential backoff (2s → 8s, max 5 attempts) and resumes the feed.

### Example flow

```bash
# Create an account and grab a token
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/auth/signup \
  -H 'Content-Type: application/json' \
  -d '{"email":"you@example.com","password":"hunter2"}' | python3 -c 'import sys,json; print(json.load(sys.stdin)["token"])')
AUTH="Authorization: Bearer $TOKEN"

# Create a league (scoped to your account)
curl -X POST http://127.0.0.1:8000/leagues \
  -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"name":"Friday Night Legends","num_teams":12,"user_team_number":4,"scoring_format":"PPR"}'

# Pick for the team on the clock (fuzzy match — "Patrick Mahom" works)
curl -X POST http://127.0.0.1:8000/leagues/Friday%20Night%20Legends/pick \
  -H "$AUTH" -H 'Content-Type: application/json' -d '{"player_name":"Patrick Mahom"}'

# AI recommendations
curl -H "$AUTH" "http://127.0.0.1:8000/leagues/Friday%20Night%20Legends/recommendations?ai=true"
```

---

## 4. Deploy the backend to Vercel

The repo ships a ready-to-deploy serverless setup (`vercel.json` +
`api/index.py`) modeled on the web app. Deploy from the `fantasy_app/`
project root:

```bash
vercel --prod
```

What happens:
- **`api/index.py`** wraps the FastAPI app in **Mangum**, the ASGI adapter
  Vercel's Python runtime needs, and redirects league storage to
  `/tmp/leagues` (the only writable location on Vercel).
- **`vercel.json`** routes every request to that single function.
- The root **`requirements.txt`** (backend deps + `mangum`) is what Vercel
  installs.

### Storage: durable on Vercel (set `DATABASE_URL`)

The backend ships a **durable key-value store** (`backend/db.py`):

- **`DATABASE_URL` set** → all accounts, sessions, and leagues live in
  managed **Postgres** (Neon / Supabase). Data survives serverless cold
  starts, so sign-ins and leagues persist.
- **`DATABASE_URL` unset** → a local **SQLite** file
  (`FANTASY_DATA_DIR/draft.db`), durable on any filesystem-backed host and
  dependency-free for local dev.

If Postgres is unreachable the store logs once and degrades to SQLite
instead of 500-ing, then retries Postgres every 30s. A one-time migration
imports any pre-existing JSON data (`backend/data/auth/*`, `backend/data/users/*`)
the first time the new store runs.

> ⚠️ Without `DATABASE_URL` on Vercel, the SQLite file lands in `/tmp` and
> is still wiped on cold starts — **always set `DATABASE_URL` on Vercel**
> (Vercel → your project → Storage → Create Neon Postgres, which sets the
> env var automatically).

### Environment variables (Vercel project settings)

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | Managed Postgres URL — makes accounts/leagues durable across cold starts (required for production) |
| `NVIDIA_API_KEY` | Enables NVIDIA NIM AI recommendations (endpoint falls back to pure VBD without it) |

### iOS pointing at the deployed URL

Type the deployed URL into the **Backend URL** field on the app's sign-in
screen (e.g. `https://your-app.vercel.app`) — it's persisted in `UserDefaults`
key `apiBaseURL`.

**Vercel doesn't support WebSockets**, so the live draft socket won't connect
in production. The app detects this automatically: the toolbar shows an
**AUTO** chip instead of **LIVE**, and the draft room falls back to
auto-refreshing state via REST every 4 seconds — picks from other devices
still show up, just on a short poll instead of a push.

---

## 5. Draft Engine Notes

- **Snake order** — odd rounds go 1→N, even rounds N→1; the API reports exactly
  how many picks before your turn.
- **VBD scoring** — value over replacement vs. league baseline, blended 60/40
  with roster-need score.
- **Safe picks** = low turn-loss probability; **upside** = highest projected
  ceiling; **sleepers** = late-ADP value (always exactly 3 returned).
- **Fuzzy pick matching** guards against accidental picks: length-disproportionate
  queries are rejected even if thefuzz partial-ratio scores them highly.
- Per-league player pools are isolated (deep-copied from a cached template), so
  drafting in one league can never mark players taken in another.

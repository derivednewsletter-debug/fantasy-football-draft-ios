# Fantasy Draft Assistant — iOS + FastAPI

Multi-league fantasy football draft engine, wrapped in a FastAPI REST backend
and fronted by a native **SwiftUI iOS 17+** app. The backend reuses the exact
draft engine from the Fantasy Draft CLI (snake order, VBD scoring, roster-need
analysis) plus optional **NVIDIA NIM** AI recommendations.

```
fantasy_app/
├── backend/                 # FastAPI REST backend
│   ├── main.py              # Routes (6 core endpoints)
│   ├── schemas.py           # Pydantic request/response models
│   ├── default_projections.csv
│   └── engine/              # Core draft engine (models, VBD, AI advisor, store)
└── ios_app/
    └── FantasyDraftAssistant/
        ├── FantasyDraftAssistant.xcodeproj
        └── FantasyDraftAssistant/
            ├── App/         # SwiftUI entry point
            ├── Models/      # Codable structs (League, Player, Pick, Position)
            ├── Services/    # APIService.swift (URLSession async/await)
            ├── ViewModels/  # DraftViewModel.swift (@Observable)
            └── Views/       # LeagueListView, DraftRoomView, board/roster/AI views
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

Leagues persist as JSON files in `backend/data/` (survives restarts).

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
python3 backend/_smoke_test.py    # 33 checks: create, state, pick, undo, recs
```

### Automated E2E test suite

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r backend/requirements.txt pytest pytest-asyncio httpx
pytest tests/ -v                  # 38 checks across every endpoint
```

Covers: league creation across team sizes (8/10/12/14) and scoring formats
(PPR/Superflex), snake-order pick progression and turn calculation, undo
rollback integrity, NVIDIA NIM recommendations (mocked), and fuzzy name
matching edge cases (misspellings, apostrophes, initials, garbage queries).

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

### Point the app at your backend

`APIService.swift` reads the base URL from `UserDefaults` key `apiBaseURL`,
defaulting to `http://127.0.0.1:8000`:

- **Simulator**: works out of the box (`127.0.0.1` = your Mac).
- **Physical device**: change the URL to your Mac's LAN IP:
  `http://192.168.x.x:8000` (both machines on the same Wi-Fi; the Info.plist
  allows local networking).

To override without editing code, run this once in the app (or set the default
in `APIService.swift`):

```swift
UserDefaults.standard.set("http://192.168.1.50:8000", forKey: "apiBaseURL")
```

### Screens

| Screen | What it does |
|--------|--------------|
| **League List** | All leagues with status badges (`Drafting — Pick 3.04`, `On the clock`) + quick-create form (teams, your pick, scoring) |
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
| `GET`  | `/` | Health check (status, league count, AI availability) |
| `GET`  | `/leagues` | List all leagues |
| `POST` | `/leagues` | Create league `{name, num_teams, user_team_number, scoring_format}` |
| `GET`  | `/leagues/{id}/state` | Full draft state (round, pick, on-the-clock team, rosters, board matrix) |
| `POST` | `/leagues/{id}/pick` | `{player_name}` — fuzzy-matched, drafted by the team on the clock |
| `POST` | `/leagues/{id}/undo` | Roll back the last pick |
| `GET`  | `/leagues/{id}/recommendations?ai=true` | VBD + NVIDIA AI recommendations |
| `DELETE` | `/leagues/{id}` | Delete a league |
| `WS`   | `/leagues/{id}/ws` | Live draft feed — pushes a fresh state envelope on every pick/undo from any device |

League IDs are URL-encoded names (e.g. `Friday%20Night%20Legends`).

### Live sync (WebSocket)

Every league exposes a WebSocket feed at `/leagues/{id}/ws`. On connect it
immediately sends the current draft state, then broadcasts a fresh state
envelope after **every** successful pick or undo — so any number of devices
in the room stay in sync with no pull-to-refresh.

```json
{"type": "state", "league_id": "Friday Night Legends", "state": { ...full draft state... }}
```

The iOS app connects automatically when you open a draft room (see the **LIVE**
indicator) and disconnects when you leave. If the socket drops it reconnects
with capped exponential backoff (2s → 8s, max 5 attempts) and resumes the feed.

### Example flow

```bash
# Create
curl -X POST http://127.0.0.1:8000/leagues \
  -H 'Content-Type: application/json' \
  -d '{"name":"Friday Night Legends","num_teams":12,"user_team_number":4,"scoring_format":"PPR"}'

# Pick for the team on the clock (fuzzy match — "Patrick Mahom" works)
curl -X POST http://127.0.0.1:8000/leagues/Friday%20Night%20Legends/pick \
  -H 'Content-Type: application/json' -d '{"player_name":"Patrick Mahom"}'

# AI recommendations
curl "http://127.0.0.1:8000/leagues/Friday%20Night%20Legends/recommendations?ai=true"
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

### ⚠️ Storage is ephemeral on Vercel

Serverless functions are recycled constantly, and `/tmp` is wiped on every
cold start. **Leagues created on the deployed backend can disappear.** The
backend always starts empty after a recycle, so:

- Use the deployed backend for demoing / one-shot drafts.
- For durable data, run the backend locally (`uvicorn backend.main:app`) or
  on a long-running host — the storage layer is a drop-in JSON-file store.

### Environment variables (Vercel project settings)

| Variable | Purpose |
|----------|---------|
| `NVIDIA_API_KEY` | Enables NVIDIA NIM AI recommendations (endpoint falls back to pure VBD without it) |

### iOS pointing at the deployed URL

The app already reads its backend URL from `UserDefaults` key `apiBaseURL`.
Point it at your Vercel deployment (e.g. `https://your-app.vercel.app`):

```swift
UserDefaults.standard.set("https://your-app.vercel.app", forKey: "apiBaseURL")
```

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

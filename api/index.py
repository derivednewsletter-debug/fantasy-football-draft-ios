"""Vercel serverless entry point for the Fantasy Draft Assistant API.

Vercel's Python runtime cannot serve ASGI apps (like FastAPI) directly, so
we wrap the application with Mangum, which adapts it to the Lambda-style
`handler(event, context)` signature that Vercel Python functions expect.

Deployment notes:
  * League data lives in /tmp/leagues on Vercel (the only writable location).
    It is ephemeral per cold start — the same tradeoff as the web app.
  * Vercel serverless does NOT support WebSockets, so /leagues/{id}/ws will
    not upgrade in production.  The iOS app detects this and falls back to
    periodic REST polling so picks still show up in real time.
  * Set NVIDIA_API_KEY in the Vercel project's Environment Variables to
    enable AI recommendations.
"""

import os
import sys
from pathlib import Path

# Ensure the project root is on sys.path so `backend` (and `api`) import.
_project_root = Path(__file__).resolve().parent.parent
if str(_project_root) not in sys.path:
    sys.path.insert(0, str(_project_root))

# Vercel's filesystem is read-only except /tmp — redirect league storage there
# BEFORE importing the app (store.py reads the env at import time).
os.environ.setdefault("FANTASY_DATA_DIR", "/tmp/leagues")

from mangum import Mangum

from backend.main import app

# Vercel Python functions import `handler` and call it as handler(event, context).
handler = Mangum(app)

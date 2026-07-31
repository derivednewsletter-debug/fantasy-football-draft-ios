#!/usr/bin/env bash
#
# End-to-end verification for a deployed Fantasy Draft Assistant backend.
#
# Usage:
#   ./verify_deploy.sh <base-url>
#
# Examples:
#   ./verify_deploy.sh https://your-backend.vercel.app
#   ./verify_deploy.sh http://127.0.0.1:8000        # local dry run
#
# Runs the full user journey against the LIVE database: health check,
# sign-up, login, create league, list leagues, and duplicate rejection.
# Uses a throwaway account (random email) so your real account is untouched.
#
set -euo pipefail

BASE_URL="${1:?usage: ./verify_deploy.sh <base-url>}"
EMAIL="verify-$(date +%s)-$RANDOM@test.com"
PASSWORD="verify-pass-123"
PASSED=0
FAILED=0

# Per-run temp dir so concurrent runs never clobber each other's responses.
# (Named RUN_TMP, not TMPDIR — that standard env var is respected by curl/python.)
RUN_TMP=$(mktemp -d)
trap 'rm -rf "$RUN_TMP"' EXIT

say()  { printf '  %-40s %s\n' "$1" "$2"; }
pass() { PASSED=$((PASSED+1)); say "$1" "PASS"; }
fail() { FAILED=$((FAILED+1)); say "$1" "FAIL ($2)"; }

# --- 1. Health ---------------------------------------------------------------
echo "== $BASE_URL =="
# Cold Vercel Python functions can take 10-30s to boot, so give the first
# request (health) a generous timeout rather than a false failure.
code=$(curl -s -o "$RUN_TMP/health.json" -w '%{http_code}' --max-time 40 "$BASE_URL/" || true)
if [ "$code" = "200" ] && grep -q '"status":"ok"' "$RUN_TMP/health.json"; then
  pass "GET / health check"
else
  fail "GET / health check" "HTTP $code"
fi

# --- 2. Sign-up --------------------------------------------------------------
code=$(curl -s -o "$RUN_TMP/signup.json" -w '%{http_code}' --max-time 30 \
  -X POST "$BASE_URL/auth/signup" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" || true)
TOKEN=""
if [ "$code" = "201" ]; then
  TOKEN=$(python3 -c "import json;print(json.load(open('$RUN_TMP/signup.json')).get('token',''))" 2>/dev/null || true)
  if [ -n "$TOKEN" ]; then pass "POST /auth/signup (new account)"; else fail "POST /auth/signup" "no token in response"; fi
else
  fail "POST /auth/signup" "HTTP $code — $(head -c 200 "$RUN_TMP/signup.json")"
fi

# --- 3. Login ----------------------------------------------------------------
if [ -n "$TOKEN" ]; then
  code=$(curl -s -o "$RUN_TMP/login.json" -w '%{http_code}' --max-time 30 \
    -X POST "$BASE_URL/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" || true)
  if [ "$code" = "200" ]; then
    pass "POST /auth/login"
  else
    fail "POST /auth/login" "HTTP $code"
  fi

  # Wrong password must be rejected (401)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
    -X POST "$BASE_URL/auth/login" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$EMAIL\",\"password\":\"wrong-pass\"}" || true)
  if [ "$code" = "401" ]; then
    pass "POST /auth/login (wrong password -> 401)"
  else
    fail "POST /auth/login (wrong password -> 401)" "HTTP $code"
  fi
fi

# --- 4. Create league --------------------------------------------------------
LEAGUE="Verify League $RANDOM"
if [ -n "$TOKEN" ]; then
  code=$(curl -s -o "$RUN_TMP/league.json" -w '%{http_code}' --max-time 60 \
    -X POST "$BASE_URL/leagues" -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$LEAGUE\",\"num_teams\":10,\"user_team_number\":3,\"scoring_format\":\"PPR\"}" || true)
  if [ "$code" = "201" ]; then
    pass "POST /leagues (create)"
  else
    fail "POST /leagues (create)" "HTTP $code — $(head -c 200 "$RUN_TMP/league.json")"
  fi

  # Duplicate must be rejected (409)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 \
    -X POST "$BASE_URL/leagues" -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$LEAGUE\",\"num_teams\":10,\"user_team_number\":3,\"scoring_format\":\"PPR\"}" || true)
  if [ "$code" = "409" ]; then
    pass "POST /leagues (duplicate -> 409)"
  else
    fail "POST /leagues (duplicate -> 409)" "HTTP $code"
  fi

  # List must include the new league
  code=$(curl -s -o "$RUN_TMP/list.json" -w '%{http_code}' --max-time 30 \
    "$BASE_URL/leagues" -H "Authorization: Bearer $TOKEN" || true)
  if [ "$code" = "200" ] && grep -q "$LEAGUE" "$RUN_TMP/list.json"; then
    pass "GET /leagues (lists new league)"
  else
    fail "GET /leagues (lists new league)" "HTTP $code"
  fi
fi

echo
echo "RESULT: $PASSED passed, $FAILED failed  (account: $EMAIL)"
[ "$FAILED" = "0" ] || exit 1

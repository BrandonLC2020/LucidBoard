#!/usr/bin/env bash
# End-to-end smoke test against a running local backend.
# Usage: ./scripts/smoke.sh
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8000}"

echo "==> signup"
PY="${PY:-python3}"
TOKEN=$(curl -sf -X POST "$BASE/auth/v1/signup?anonymous=true" | "$PY" -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
AUTH="Authorization: Bearer $TOKEN"

echo "==> seed board (boards are normally created by the Swift app; insert via psql for a deterministic smoke run)"
BOARD_ID=$("$PY" -c 'import uuid;print(uuid.uuid4())')
USER_ID=$("$PY" -c 'import sys,json,base64;tok=sys.argv[1].split(".")[1];tok+="="*((4-len(tok)%4)%4);print(json.loads(base64.urlsafe_b64decode(tok))["sub"])' "$TOKEN")
docker exec -i lucidboard-db psql -U lucidboard -d lucidboard -c \
  "INSERT INTO boards (id, user_id, title, background_color, background_layout, created_at, updated_at) VALUES ('$BOARD_ID', '$USER_ID', 'Smoke', '#FFFFFF', 'grid', now(), now());"

echo "==> list boards"
curl -sf -H "$AUTH" "$BASE/api/boards" | "$PY" -m json.tool

echo "==> create note"
NOTE_ID=$("$PY" -c 'import uuid;print(uuid.uuid4())')
curl -sf -X PUT -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"board_id\":\"$BOARD_ID\",\"color\":\"#FFF9C4\",\"pos_x\":1.0,\"pos_y\":2.0,\"z_index\":0,\"content_text\":\"smoke\",\"template\":\"plain\",\"checklist_items\":[]}" \
  "$BASE/api/notes/$NOTE_ID" | "$PY" -m json.tool

echo "==> list notes"
curl -sf -H "$AUTH" "$BASE/api/boards/$BOARD_ID/notes" | "$PY" -m json.tool

echo "==> delete note"
curl -sf -X DELETE -H "$AUTH" "$BASE/api/notes/$NOTE_ID" -o /dev/null -w "delete status: %{http_code}\n"

echo "==> SMOKE OK"

#!/usr/bin/env bash
# End-to-end smoke test against a running local backend + Firestore emulator.
# Usage: ./scripts/smoke.sh
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8000}"
# Must be run from the backend/ directory (where pyproject.toml lives) so
# `uv run` resolves the project venv — that's where google-cloud-firestore
# is installed; the system python3 doesn't have it.
PY="${PY:-uv run python}"

echo "==> signup"
TOKEN=$(curl -sf -X POST "$BASE/auth/v1/signup?anonymous=true" | $PY -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
AUTH="Authorization: Bearer $TOKEN"
USER_ID=$($PY -c 'import sys,json,base64;tok=sys.argv[1].split(".")[1];tok+="="*((4-len(tok)%4)%4);print(json.loads(base64.urlsafe_b64decode(tok))["sub"])' "$TOKEN")

echo "==> seed board directly in the Firestore emulator (boards are normally created by the Swift app)"
BOARD_ID=$($PY - "$USER_ID" <<'EOF'
import os, sys, uuid
from datetime import datetime, timezone
from google.cloud import firestore

user_id = sys.argv[1]
board_id = str(uuid.uuid4())
client = firestore.Client(project=os.environ.get("FIRESTORE_PROJECT_ID", "demo-lucidboard"))
now = datetime.now(tz=timezone.utc)
client.collection("boards").document(board_id).set({
    "user_id": user_id,
    "title": "Smoke",
    "background_color": "#FFFFFF",
    "background_layout": "grid",
    "created_at": now,
    "updated_at": now,
})
print(board_id)
EOF
)

echo "==> list boards"
curl -sf -H "$AUTH" "$BASE/api/boards" | $PY -m json.tool

echo "==> create note"
NOTE_ID=$($PY -c 'import uuid;print(uuid.uuid4())')
curl -sf -X PUT -H "$AUTH" -H "Content-Type: application/json" \
  -d "{\"board_id\":\"$BOARD_ID\",\"color\":\"#FFF9C4\",\"pos_x\":1.0,\"pos_y\":2.0,\"z_index\":0,\"content_text\":\"smoke\",\"template\":\"plain\",\"checklist_items\":[]}" \
  "$BASE/api/notes/$NOTE_ID" | $PY -m json.tool

echo "==> list notes"
curl -sf -H "$AUTH" "$BASE/api/boards/$BOARD_ID/notes" | $PY -m json.tool

echo "==> delete note"
curl -sf -X DELETE -H "$AUTH" "$BASE/api/notes/$NOTE_ID" -o /dev/null -w "delete status: %{http_code}\n"

echo "==> SMOKE OK"

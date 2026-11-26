#!/usr/bin/env bash
# Run from any directory. Only the throwaway Compose project and its own accounts are used.
set -euo pipefail
client=$(cd "$(dirname "$0")/.." && pwd)
server=$(cd "${1:-$client/../server}" && pwd)
work=$(mktemp -d)
project="papyrus-fault-$(basename "$work" | tr '[:upper:].' '[:lower:]-')"
export COMPOSE_PROJECT_NAME="$project"
export COMPOSE_FILE="$work/docker-compose.yml:$work/docker-compose.override.yml"
api_pid=
proxy_pid=
cleanup() {
  if [[ -n "$api_pid" ]]; then kill "$api_pid" 2>/dev/null || true; fi
  if [[ -n "$proxy_pid" ]]; then kill "$proxy_pid" 2>/dev/null || true; fi
  if [[ -f "$work/.env" ]]; then (cd "$work" && docker compose down -v) || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
git -C "$server" archive HEAD | tar -x -C "$work"
cd "$work"
python3 - <<'PY'
from pathlib import Path
import secrets
values = {
    "POSTGRES_PORT": "25432", "POSTGRES_DB": "papyrus_chaos_test",
    "PORT": "28080", "POWERSYNC_SERVICE_PORT": "28081",
    "POWERSYNC_JWKS_URI": "http://host.docker.internal:28080/v1/auth/jwks",
    "SECRET_KEY": secrets.token_hex(32),
}
lines = []
for line in Path(".env.example").read_text().splitlines():
    key = line.partition("=")[0]
    if key in values:
        line = f"{key}={values[key]}"
    lines.append(line)

Path(".env").write_text("\n".join(lines) + "\n")
PY
# The API, migrations and Compose must all use the same disposable database.
set -a
source <(grep -E '^(POSTGRES_|POWERSYNC_|PORT=|SECRET_KEY=)' .env)
set +a
cat > docker-compose.override.yml <<'YAML'
services:
  database:
    ports: !override ["127.0.0.1:25432:5432"]
  powersync:
    ports: !override ["127.0.0.1:28081:8080"]
YAML
./scripts/generate_dev_powersync_keys.sh
docker compose up -d --wait database powersync-storage
uv sync --locked --no-dev
.venv/bin/alembic upgrade head
./scripts/setup_local_powersync.sh
export PAPYRUS_DISPOSABLE_OWNER_EMAIL=writer@example.com
export PAPYRUS_DISPOSABLE_OTHER_EMAIL=other@example.com
export PAPYRUS_DISPOSABLE_PASSWORD="$(openssl rand -hex 24)"
.venv/bin/python - <<'PY'
import asyncio
import os
from datetime import UTC, datetime
from papyrus.core.database import async_session_maker
from papyrus.core.security import hash_password
from papyrus.models.auth import PasswordCredential
from papyrus.models.user import User

async def create_accounts():
    async with async_session_maker.begin() as session:
        for key in ("PAPYRUS_DISPOSABLE_OWNER_EMAIL", "PAPYRUS_DISPOSABLE_OTHER_EMAIL"):
            user = User(primary_email=os.environ[key], display_name="Journey reader",
                        email_verified_at=datetime.now(UTC), email_verification_source="papyrus_email")
            session.add(user)
            await session.flush()
            session.add(PasswordCredential(user_id=user.user_id,
                                           password_hash=hash_password(os.environ["PAPYRUS_DISPOSABLE_PASSWORD"])))

asyncio.run(create_accounts())
PY
.venv/bin/uvicorn papyrus.main:app --host 0.0.0.0 --port 28080 > "$work/api.log" 2>&1 &
api_pid=$!
toxiproxy-server -port 28474 > "$work/proxy.log" 2>&1 &
proxy_pid=$!
docker compose up -d --wait powersync
kill -0 "$api_pid" "$proxy_pid"
curl -fsS --retry 12 --retry-connrefused http://127.0.0.1:28080/health
curl -fsS --retry 8 --retry-connrefused http://127.0.0.1:28474/version
cd "$client/app"
export PAPYRUS_TOXIPROXY=http://127.0.0.1:28474
"${FLUTTER_BIN:-flutter}" test --concurrency=1 test/powersync/lost_acknowledgement_test.dart test/powersync/profile_note_journey_test.dart \
  --dart-define=PAPYRUS_API_BASE_URL=http://127.0.0.1:28080 \
  --dart-define=POWERSYNC_SERVICE_URL=http://127.0.0.1:28081 --reporter expanded || {
    tail -60 "$work/api.log"
    exit 1
  }

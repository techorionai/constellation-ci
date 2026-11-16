#!/usr/bin/env bash
# Smoke test of the fixture. It starts the service, runs one check, and removes everything.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
project=constellation-ci-fixture
trap 'docker compose -p "$project" down -v --remove-orphans >/dev/null 2>&1 || true' EXIT

docker compose -p "$project" up -d --wait
docker compose -p "$project" exec -T app echo "service is up"
docker compose -p "$project" down -v --remove-orphans

containers=$(docker compose -p "$project" ps -a -q)
volumes=$(docker volume ls -q --filter "label=com.docker.compose.project=$project")
if [ -n "$containers" ] || [ -n "$volumes" ]; then
  echo "The project $project left containers or volumes." >&2
  exit 1
fi
echo "Smoke test passed."

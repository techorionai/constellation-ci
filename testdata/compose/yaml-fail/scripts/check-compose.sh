#!/usr/bin/env bash
# Static check of the Compose file of the fixture.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
project=constellation-ci-fixture
docker compose -p "$project" config --quiet

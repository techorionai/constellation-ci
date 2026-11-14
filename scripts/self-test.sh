#!/usr/bin/env bash
# Run the caller workflows in a folder with act. Each caller must fail at the job and step
# that its header line names: "# expect-fail: <job>/<step>".
# Usage: scripts/self-test.sh <folder>
set -euo pipefail

# Runner image of the act runs. A new digest comes with a new release of constellation-ci.
RUNNER_IMAGE='ghcr.io/catthehacker/ubuntu@sha256:19619a010b204f44c5340bff7d39b68551109fe6a56a53f75201ea91e05d4270'

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "Usage: $0 <folder>" >&2
  exit 2
fi

folder=$1
log_dir=$(mktemp -d)
trap 'rm -rf "$log_dir"' EXIT

total=0
failed=0

for caller in "$folder"/*.yml; do
  [ -e "$caller" ] || continue
  total=$((total + 1))
  name=$(basename "$caller")

  header=$(sed -n 's/^# expect-fail: //p' "$caller" | head -n 1)
  job=${header%%/*}
  step=${header#*/}
  if [ -z "$header" ] || [ "$job" = "$header" ]; then
    echo "FAIL  $name: no valid '# expect-fail: <job>/<step>' header"
    failed=$((failed + 1))
    continue
  fi

  log="$log_dir/$name.log"
  code=0
  gh act pull_request -W "$caller" --concurrent-jobs 1 \
    -P "ubuntu-latest=$RUNNER_IMAGE" > "$log" 2>&1 || code=$?

  if [ "$code" -eq 0 ]; then
    echo "FAIL  $name: no failure (expected $job/$step)"
    failed=$((failed + 1))
    continue
  fi

  # The act log has the line "[<caller job>/<workflow>/<job>] ... Failure - Main <step> [<time>]".
  if awk -v job="$job" -v step="$step" '
    (index($0, "/" job " ") > 0 || index($0, "/" job "]") > 0) && index($0, "Failure - Main " step " [") > 0 { found = 1 }
    END { exit found ? 0 : 1 }' "$log"; then
    echo "PASS  $name: failed at $job/$step"
  else
    echo "FAIL  $name: wrong step (expected $job/$step). Failure lines in the log:"
    grep -a 'Failure - ' "$log" | sed 's/^/        /' || true
    failed=$((failed + 1))
  fi
done

echo "$((total - failed)) of $total cases passed."
if [ "$total" -eq 0 ] || [ "$failed" -ne 0 ]; then
  exit 1
fi

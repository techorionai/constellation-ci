#!/usr/bin/env bash
# Static checks of the workflows in a folder. The folder has a .github/workflows/ folder.
# Usage: scripts/check-repo.sh <folder>
# The checks assume 2 spaces of indentation in the workflow files.
set -uo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1/.github/workflows" ]; then
  echo "Usage: $0 <folder with .github/workflows>" >&2
  exit 2
fi

root=$1
workflows=$(find "$root/.github/workflows" -maxdepth 1 -name '*.yml' | sort)
errors=0

fail() {
  echo "ERROR: $*"
  errors=$((errors + 1))
}

if [ -z "$workflows" ]; then
  fail "no workflow files in $root/.github/workflows"
fi

# Run actionlint on the given files.
run_actionlint() {
  if ! actionlint "$@"; then
    fail "actionlint found problems"
  fi
}

# shellcheck disable=SC2086
run_actionlint $workflows

for file in $workflows; do
  # Top-level permissions: contents read.
  if ! grep -qE '^permissions:' "$file"; then
    fail "$file: no top-level permissions"
  else
    block=$(awk '/^permissions:/ { print; inb = 1; next } inb && /^[^ #]/ { exit } inb { print }' "$file")
    if ! printf '%s\n' "$block" | grep -qE 'contents: read'; then
      fail "$file: top-level permissions do not have 'contents: read'"
    fi
  fi

  # No write permission at the top level or in a job. Comments do not count.
  # One exception: packages: write is allowed in the job build of .github/workflows/image.yml
  # and in a caller job of image.yml. Any other write permission in these jobs still fails.
  rel=${file#"$root"/}
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    fail "$file:${entry%%:*}: ${entry#*:} permissions have a write permission"
  done < <(awk -v rel="$rel" '
    function finish(   n, i, lines) {
      if (pend != "" && !allowed) {
        n = split(pend, lines, " ")
        for (i = 1; i <= n; i++) print lines[i] ":job-level"
      }
      pend = ""
    }
    {
      line = $0
      sub(/#.*/, "", line)
      gsub(/["\047]/, "", line)
      match(line, /^ */); ind = RLENGTH
      if (line ~ /^[^ ]/) { if (injobs) finish(); injobs = (line ~ /^jobs:/); job = ""; uses = ""; allowed = 0 }
      if (injobs && line ~ /^  [A-Za-z_][A-Za-z0-9_-]*:/) {
        finish()
        job = line; sub(/^  /, "", job); sub(/:.*/, "", job)
        uses = ""
        allowed = (job == "build" && rel == ".github/workflows/image.yml")
      }
      if (injobs && ind == 4 && line ~ /^ *uses:/) {
        uses = line; sub(/^ *uses: */, "", uses); sub(/ +$/, "", uses)
        if (uses == "./.github/workflows/image.yml" || uses ~ /^techorionai\/constellation-ci\/\.github\/workflows\/image\.yml@[^ ]+$/) allowed = 1
      }
      if (inb && line !~ /^ *$/ && ind <= pind) inb = 0
      if (line ~ /^ *permissions:/) {
        pind = ind; inb = 1
        level = (ind == 0) ? "top-level" : "job-level"
        chk = line; sub(/^ *permissions:/, "", chk)
      } else if (inb) {
        chk = line
      } else {
        next
      }
      if (chk ~ /(^|[ :{,])write(-all)?([ ,}]|$)/) {
        rest = chk
        gsub(/packages: *write/, "", rest)
        if (level == "job-level" && injobs && rest !~ /(^|[ :{,])write(-all)?([ ,}]|$)/) pend = pend " " NR
        else print NR ":" level
      }
    }
    END { if (injobs) finish() }' "$file")

  # The metadata step of image.yml must set latest=false, and the step No latest tag must exist.
  if [ "$(basename "$file")" = image.yml ] && grep -q 'docker/metadata-action@' "$file"; then
    if ! awk '
      /^ *- name:/ { inmeta = 0 }
      /uses: *docker\/metadata-action@/ { inmeta = 1 }
      inmeta && /latest=false/ { found = 1 }
      END { exit found ? 0 : 1 }' "$file"; then
      fail "$file: the metadata-action step has no 'latest=false' flavor"
    fi
    if ! grep -qE '^ *- name: No latest tag$' "$file"; then
      fail "$file: no step named 'No latest tag'"
    fi
  fi

  # Each checkout step has persist-credentials: false.
  missing=$(awk '
    function stepend(   ) {
      if (pending) { print pending_line; pending = 0 }
    }
    {
      match($0, /^ */); ind = RLENGTH
      isdash = ($0 ~ /^ *- /)
      if (pending) {
        if (($0 ~ /^ *$/)) next
        if ((isdash && ind <= stepind) || (!isdash && ind < stepind)) stepend()
        else if ($0 ~ /persist-credentials: false/) pending = 0
      }
      if ($0 ~ /uses: *["\047]?actions\/checkout@/) {
        pending = 1; pending_line = NR; stepind = isdash ? ind : ind - 2
      }
    }
    END { stepend() }' "$file")
  for line in $missing; do
    fail "$file:$line: actions/checkout has no 'persist-credentials: false'"
  done

  # No secrets block in a workflow_call trigger.
  if awk '
    /^  workflow_call:/ { inwc = 1; next }
    inwc && /^  [^ #]/ { inwc = 0 }
    inwc && /^    secrets:/ { found = 1 }
    END { exit found ? 0 : 1 }' "$file"; then
    fail "$file: workflow_call has a secrets block"
  fi

  # No pull_request_target trigger and no inherited secrets.
  while IFS= read -r line; do
    fail "$file:${line%%:*}: pull_request_target is not allowed"
  done < <(grep -nE '^[^#]*pull_request_target' "$file" || true)
  while IFS= read -r line; do
    fail "$file:${line%%:*}: 'secrets: inherit' is not allowed"
  done < <(grep -nE '^[^#]*secrets:[[:space:]]*inherit' "$file" || true)

  # Each job that runs on a runner has timeout-minutes.
  while IFS= read -r job; do
    fail "$file: job '$job' has no timeout-minutes"
  done < <(awk '
    function finish() { if (job != "" && runs && !timeout) print job }
    /^[^ #]/ { if (injobs) finish(); injobs = ($0 ~ /^jobs:/); job = ""; next }
    !injobs { next }
    /^  [A-Za-z_][A-Za-z0-9_-]*:/ { finish(); job = $1; sub(/:$/, "", job); runs = 0; timeout = 0; next }
    /^    runs-on:/ { runs = 1 }
    /^    timeout-minutes:/ { timeout = 1 }
    END { if (injobs) finish() }' "$file")

  # A caller job passes fixed strings only. No github context in the with: values.
  # The check finds the word github inside any ${{ }} expression, in any letter case.
  # An expression can continue on the next line. A flow style with: value is also checked.
  while IFS= read -r line; do
    fail "$file:$line: a 'with:' value of a job uses event data (the github context)"
  done < <(awk '
    {
      match($0, /^ */); ind = RLENGTH
      if (inw && $0 !~ /^ *$/ && ind <= 4) inw = 0
      if ($0 ~ /^    with:/) inw = 1
      if (!inw) next
      rest = tolower($0)
      sub(/(^| )#.*/, "", rest)
      hit = 0
      while (rest != "") {
        if (!inexpr) {
          p = index(rest, "${{")
          if (!p) break
          rest = substr(rest, p + 3); inexpr = 1
        } else {
          p = index(rest, "}}")
          if (p) { seg = substr(rest, 1, p - 1); rest = substr(rest, p + 2); inexpr = 0 }
          else { seg = rest; rest = "" }
          if (seg ~ /(^|[^a-z0-9_-])github([^a-z0-9_-]|$)/) hit = 1
        }
      }
      if (hit) print NR
    }' "$file")

  # Each non-local action has a full commit SHA. A docker:// action has a sha256 digest.
  while IFS= read -r entry; do
    line=${entry%%:*}
    ref=${entry#*:}
    ref=${ref#*uses:}
    ref=$(echo "$ref" | sed -E "s/#.*//; s/^ +//; s/ +\$//; s/^[\"']//; s/[\"']\$//")
    case "$ref" in
      ./*) continue ;;
      docker://*)
        if ! echo "$ref" | grep -qE '@sha256:[0-9a-f]{64}$'; then
          fail "$file:$line: '$ref' is not pinned to a sha256 digest"
        fi
        continue
        ;;
    esac
    if ! echo "$ref" | grep -qE '@[0-9a-f]{40}$'; then
      fail "$file:$line: '$ref' is not pinned to a full commit SHA"
    fi
  done < <(grep -nE '^\s*(-\s+)?uses:' "$file")
done

# The golangci-lint copy in go.yml must be identical to config/golangci.yml.
if [ -f "$root/config/golangci.yml" ] && [ -f "$root/.github/workflows/go.yml" ]; then
  copy=$(awk '
    /<<.GOLANGCI_CONFIG.$/ { inb = 1; next }
    inb && /^ *GOLANGCI_CONFIG$/ { exit }
    inb { sub(/^          /, ""); print }' "$root/.github/workflows/go.yml")
  if [ "$copy" != "$(cat "$root/config/golangci.yml")" ]; then
    fail "the golangci-lint configuration in go.yml is not identical to config/golangci.yml"
  fi
fi

# The callers in testdata/callers are valid.
if [ -d "$root/testdata/callers" ]; then
  run_actionlint "$root"/testdata/callers/*.yml "$root"/testdata/self-test-wrong-step/*.yml
fi

# The YAML examples in docs/usage.md are valid workflow files.
if [ -f "$root/docs/usage.md" ]; then
  tmp=$(mktemp -d)
  awk -v dir="$tmp" '
    /^```yaml$/ { n++; inb = 1; next }
    /^```$/ { inb = 0; next }
    inb { print > (dir "/example-" n ".yml") }' "$root/docs/usage.md"
  examples=$(find "$tmp" -name '*.yml' | sort)
  if [ -n "$examples" ]; then
    # shellcheck disable=SC2086
    run_actionlint $examples
  fi
  rm -rf "$tmp"
fi

if [ "$errors" -ne 0 ]; then
  echo "$errors error(s) found."
  exit 1
fi
echo "All checks passed."

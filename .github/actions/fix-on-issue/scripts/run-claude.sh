#!/usr/bin/env bash
set -euo pipefail

# ── Inputs (from env) ────────────────────────────────────────────────
: "${BOXD_TOKEN:?}"
: "${ANTHROPIC_API_KEY:?}"
: "${ISSUE_NUMBER:?}"
: "${ISSUE_TITLE:?}"
: "${ISSUE_BODY:?}"
: "${REPO_CLONE_URL:?}"
: "${VM_TIMEOUT_SECS:=1800}"
: "${MAX_TURNS:=40}"
: "${ACTION_PATH:?}"

VM_NAME="claude-fix-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
PATCH_LOCAL="${RUNNER_TEMP}/claude.mbox"

echo "vm-name=${VM_NAME}" >> "$GITHUB_OUTPUT"

# ── Create VM ────────────────────────────────────────────────────────
echo "::group::Create VM ${VM_NAME}"
boxd new --name "${VM_NAME}"
# `boxd new` is async; poll info until status=running.
for i in $(seq 1 60); do
  status=$(boxd info "${VM_NAME}" --json | jq -r '.status')
  echo "  [${i}] status=${status}"
  [[ "${status}" == "running" ]] && break
  sleep 2
done
[[ "${status}" == "running" ]] || { echo "VM never reached running"; exit 1; }
echo "::endgroup::"

# ── Clone repo inside VM ─────────────────────────────────────────────
echo "::group::Clone repo"
boxd exec "${VM_NAME}" --timeout "${VM_TIMEOUT_SECS}" -- \
  bash -lc "set -euo pipefail; git clone --depth=50 ${REPO_CLONE_URL} /workspace && cd /workspace && git config user.email 'boxd-bot@users.noreply.github.com' && git config user.name 'boxd-bot'"
echo "::endgroup::"

# ── Write prompt file inside VM ──────────────────────────────────────
echo "::group::Write prompt"
prompt=$(cat "${ACTION_PATH}/prompts/fix-issue.md")
prompt="${prompt//\{\{ISSUE_NUMBER\}\}/${ISSUE_NUMBER}}"
prompt="${prompt//\{\{ISSUE_TITLE\}\}/${ISSUE_TITLE}}"
# Body may contain quotes / backticks; pass via env to avoid shell interpolation.
tmp_prompt="${RUNNER_TEMP}/prompt.md"
printf '%s' "${prompt}" > "${tmp_prompt}"
# Write the static part (no body) into a file; append body via env-piped stdin.
boxd cp "${tmp_prompt}" "${VM_NAME}:/workspace/.claude-prompt.md"
boxd exec "${VM_NAME}" -e ISSUE_BODY="${ISSUE_BODY}" -- \
  bash -lc 'sed -i "s|{{ISSUE_BODY}}|$(printf "%s" "$ISSUE_BODY" | sed "s|/|\\\\/|g; s|&|\\\\&|g")|" /workspace/.claude-prompt.md'
echo "::endgroup::"

# ── Run Claude ───────────────────────────────────────────────────────
echo "::group::Run Claude"
boxd exec "${VM_NAME}" \
  --timeout "${VM_TIMEOUT_SECS}" \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
  -e MAX_TURNS="${MAX_TURNS}" \
  -- bash -lc 'cd /workspace && cat .claude-prompt.md | claude -p --max-turns "$MAX_TURNS" 2>&1 | tee /workspace/.claude.log'
echo "::endgroup::"

# ── Extract patch ────────────────────────────────────────────────────
echo "::group::Extract patch"
# If Claude made no commits, there's nothing to patch — set has-patch=false and bail out cleanly.
commit_count=$(boxd exec "${VM_NAME}" -- \
  bash -lc 'cd /workspace && git rev-list --count HEAD ^origin/main 2>/dev/null || echo 0' | tr -d '\r\n')
if [[ "${commit_count}" == "0" ]]; then
  echo "No commits produced — nothing to patch."
  echo "has-patch=false" >> "$GITHUB_OUTPUT"
  exit 0
fi
boxd exec "${VM_NAME}" -- \
  bash -lc 'cd /workspace && git format-patch origin/main --stdout' > "${PATCH_LOCAL}"
echo "patch-file=${PATCH_LOCAL}" >> "$GITHUB_OUTPUT"
echo "has-patch=true" >> "$GITHUB_OUTPUT"
echo "::endgroup::"

#!/usr/bin/env bash
set -euo pipefail

# ── Inputs (from env) ────────────────────────────────────────────────
: "${BOXD_TOKEN:?}"
: "${ANTHROPIC_API_KEY:?}"
: "${ISSUE_NUMBER:?}"
: "${ISSUE_TITLE:?}"
: "${ISSUE_BODY:?}"
: "${VM_TIMEOUT_SECS:=1800}"
: "${MAX_TURNS:=40}"
: "${ACTION_PATH:?}"

GOLDEN_VM="boxd-action-demo-golden"
VM_NAME="claude-fix-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
WORKDIR="/home/boxd/boxd-action-demo"
PATCH_LOCAL="${RUNNER_TEMP}/claude.mbox"

echo "vm-name=${VM_NAME}" >> "$GITHUB_OUTPUT"

# ── Fork golden VM ───────────────────────────────────────────────────
echo "::group::Fork golden VM ${GOLDEN_VM} → ${VM_NAME}"
boxd fork "${GOLDEN_VM}" --name "${VM_NAME}"
# Poll `boxd list --json` until the fork reports running.
for i in $(seq 1 60); do
  status=$(boxd list --json | jq -r --arg n "${VM_NAME}" '.[] | select(.name==$n) | .status')
  echo "  [${i}] status=${status:-<none>}"
  [[ "${status}" == "running" ]] && break
  sleep 2
done
[[ "${status}" == "running" ]] || { echo "VM never reached running"; exit 1; }
echo "::endgroup::"

# ── Sync repo to latest main ─────────────────────────────────────────
echo "::group::Sync repo to origin/main"
boxd exec "${VM_NAME}" --timeout "${VM_TIMEOUT_SECS}" -- \
  bash -lc "set -e; cd ${WORKDIR} && git fetch origin && git reset --hard origin/main && npm install --prefer-offline --no-audit --no-fund 2>&1 | tail -3"
echo "::endgroup::"

# ── Render prompt on the runner, ship into VM ────────────────────────
echo "::group::Write prompt"
prompt=$(cat "${ACTION_PATH}/prompts/fix-issue.md")
prompt="${prompt//\{\{ISSUE_NUMBER\}\}/${ISSUE_NUMBER}}"
prompt="${prompt//\{\{ISSUE_TITLE\}\}/${ISSUE_TITLE}}"
prompt="${prompt//\{\{ISSUE_BODY\}\}/${ISSUE_BODY}}"
tmp_prompt="${RUNNER_TEMP}/prompt.md"
printf '%s' "${prompt}" > "${tmp_prompt}"
boxd cp "${tmp_prompt}" "${VM_NAME}:${WORKDIR}/.claude-prompt.md"
echo "::endgroup::"

# ── Run Claude ───────────────────────────────────────────────────────
echo "::group::Run Claude"
boxd exec "${VM_NAME}" \
  --timeout "${VM_TIMEOUT_SECS}" \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
  -e MAX_TURNS="${MAX_TURNS}" \
  -- bash -lc "cd ${WORKDIR} && cat .claude-prompt.md | claude -p --max-turns \"\$MAX_TURNS\" 2>&1 | tee .claude.log"
echo "::endgroup::"

# ── Extract patch ────────────────────────────────────────────────────
echo "::group::Extract patch"
commit_count=$(boxd exec "${VM_NAME}" -- \
  bash -lc "cd ${WORKDIR} && git rev-list --count HEAD ^origin/main 2>/dev/null || echo 0" | tr -d '\r\n')
if [[ "${commit_count}" == "0" ]]; then
  echo "No commits produced — nothing to patch."
  echo "has-patch=false" >> "$GITHUB_OUTPUT"
  exit 0
fi
boxd exec "${VM_NAME}" -- \
  bash -lc "cd ${WORKDIR} && git format-patch origin/main --stdout" > "${PATCH_LOCAL}"
echo "patch-file=${PATCH_LOCAL}" >> "$GITHUB_OUTPUT"
echo "has-patch=true" >> "$GITHUB_OUTPUT"
echo "::endgroup::"

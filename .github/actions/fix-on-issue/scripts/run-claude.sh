#!/usr/bin/env bash
set -euo pipefail

# ── Inputs (from env) ────────────────────────────────────────────────
: "${BOXD_JWT:?}"
: "${BOXD_GRPC_HOST:?}"
: "${ANTHROPIC_API_KEY:?}"
: "${GOLDEN_VM:?}"
: "${ISSUE_NUMBER:?}"
: "${ISSUE_TITLE:?}"
: "${ISSUE_BODY:?}"
: "${VM_TIMEOUT_SECS:=1800}"
: "${MAX_TURNS:=40}"
: "${ACTION_PATH:?}"

VM_NAME="claude-fix-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
WORKDIR="/home/boxd/boxd-action-demo"
PATCH_LOCAL="${RUNNER_TEMP}/claude.mbox"

echo "vm-name=${VM_NAME}" >> "$GITHUB_OUTPUT"

# ── gRPC helpers ─────────────────────────────────────────────────────

grpc_call() {
  local method=$1 body=$2
  grpcurl -plaintext -max-time 120 \
    -H "authorization: Bearer ${BOXD_JWT}" \
    -d "${body}" \
    "${BOXD_GRPC_HOST}" "boxd.api.v1.BoxdApi/${method}"
}

# exec_in_vm "<bash command>" — runs via streaming Exec RPC.
# The remote default shell is dash (sh) — wrap in bash -lc so bash
# features ([[, arrays, pipefail, etc.) are available.
# Echoes stdout+stderr to our stdout. Returns the VM-side exit code.
exec_in_vm() {
  local cmd=$1
  local wrapped="bash -lc $(printf %q "${cmd}")"
  local msg out data rc
  msg=$(jq -nc --arg vm "${FORK_ID}" --arg cmd "${wrapped}" '{vm_id:$vm,command:$cmd}')
  out=$(printf '%s' "${msg}" | grpcurl -plaintext -emit-defaults \
    -max-time "${VM_TIMEOUT_SECS}" \
    -H "authorization: Bearer ${BOXD_JWT}" \
    -d @ \
    "${BOXD_GRPC_HOST}" boxd.api.v1.BoxdApi/Exec 2>&1) || {
      echo "!! grpc Exec failed:" >&2
      echo "${out}" >&2
      return 127
    }
  # Reassemble stdout (and stderr, interleaved) from base64 data chunks.
  data=$(echo "${out}" | jq -s -r 'map(.data // "") | join("")')
  if [[ -n "${data}" ]]; then
    echo "${data}" | base64 -d 2>/dev/null || echo "${data}"
  fi
  rc=$(echo "${out}" | jq -s 'last.exitCode // 0')
  return "${rc}"
}

# ── Resolve golden VM id ─────────────────────────────────────────────
echo "::group::Resolve golden ${GOLDEN_VM}"
GOLDEN_ID=$(grpc_call ListVms '{}' | jq -r --arg n "${GOLDEN_VM}" '.vms[] | select(.name==$n) | .vmId')
[[ -n "${GOLDEN_ID}" ]] || { echo "golden VM '${GOLDEN_VM}' not found"; exit 1; }
echo "golden_id=${GOLDEN_ID}"
echo "::endgroup::"

# ── Fork golden ──────────────────────────────────────────────────────
echo "::group::Fork → ${VM_NAME}"
fork_req=$(jq -nc --arg src "${GOLDEN_ID}" --arg name "${VM_NAME}" '{source_vm_id:$src,name:$name}')
fork_resp=$(grpc_call ForkVm "${fork_req}")
FORK_ID=$(echo "${fork_resp}" | jq -r .vmId)
[[ -n "${FORK_ID}" ]] || { echo "fork failed: ${fork_resp}"; exit 1; }
echo "fork-id=${FORK_ID}" >> "$GITHUB_OUTPUT"
echo "fork_id=${FORK_ID}"
echo "::endgroup::"

# ── Poll until fork is running ───────────────────────────────────────
echo "::group::Wait for fork running"
status=""
for i in $(seq 1 60); do
  status=$(grpc_call GetVm "$(jq -nc --arg id "${FORK_ID}" '{vm_id:$id}')" | jq -r .status)
  echo "  [${i}] status=${status}"
  [[ "${status}" == "running" ]] && break
  sleep 2
done
[[ "${status}" == "running" ]] || { echo "fork never reached running"; exit 1; }
echo "::endgroup::"

# ── Sync repo to origin/main + npm install ───────────────────────────
echo "::group::Sync repo to origin/main"
exec_in_vm "set -e; cd ${WORKDIR} && git fetch origin && git reset --hard origin/main && npm install --prefer-offline --no-audit --no-fund 2>&1 | tail -3"
echo "::endgroup::"

# ── Render prompt on runner, UploadFile into VM ──────────────────────
echo "::group::Upload prompt"
prompt=$(cat "${ACTION_PATH}/prompts/fix-issue.md")
prompt="${prompt//\{\{ISSUE_NUMBER\}\}/${ISSUE_NUMBER}}"
prompt="${prompt//\{\{ISSUE_TITLE\}\}/${ISSUE_TITLE}}"
prompt="${prompt//\{\{ISSUE_BODY\}\}/${ISSUE_BODY}}"
b64=$(printf '%s' "${prompt}" | base64 -w0)
upload_req=$(jq -nc --arg vm "${FORK_ID}" --arg path "${WORKDIR}/.claude-prompt.md" --arg data "${b64}" '{vm_id:$vm,path:$path,data:$data}')
grpc_call UploadFile "${upload_req}" >/dev/null
echo "::endgroup::"

# ── Run Claude ───────────────────────────────────────────────────────
echo "::group::Run Claude"
# Export ANTHROPIC_API_KEY in the VM via an in-shell assignment; we can't
# pass env via the current proto's Exec, so inline it.
exec_in_vm "cd ${WORKDIR} && export ANTHROPIC_API_KEY='${ANTHROPIC_API_KEY}' && cat .claude-prompt.md | claude -p --max-turns ${MAX_TURNS} --dangerously-skip-permissions 2>&1 | tee .claude.log"
echo "::endgroup::"

# ── Check for commits; extract patch ─────────────────────────────────
echo "::group::Extract patch"
# Write patch to a file inside the VM, then DownloadFile it to the runner.
set +e
exec_in_vm "cd ${WORKDIR} && commits=\$(git rev-list --count HEAD ^origin/main 2>/dev/null || echo 0); echo \"commits=\$commits\"; if [[ \"\$commits\" != \"0\" ]]; then git format-patch origin/main --stdout > /tmp/claude.mbox; else : > /tmp/claude.mbox; fi; exit 0"
set -e

# Probe: did we produce a non-empty patch?
set +e
exec_in_vm "stat -c '%s' /tmp/claude.mbox" >/tmp/patch-size.txt 2>/dev/null
set -e
patch_size=$(tr -dc '0-9' </tmp/patch-size.txt || echo 0)
echo "patch size in VM: ${patch_size:-0} bytes"

if [[ -z "${patch_size}" || "${patch_size}" == "0" ]]; then
  echo "No commits produced — nothing to patch."
  echo "has-patch=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

dl_req=$(jq -nc --arg vm "${FORK_ID}" --arg path "/tmp/claude.mbox" '{vm_id:$vm,path:$path}')
grpc_call DownloadFile "${dl_req}" | jq -r .data | base64 -d > "${PATCH_LOCAL}"
echo "patch-file=${PATCH_LOCAL}" >> "$GITHUB_OUTPUT"
echo "has-patch=true" >> "$GITHUB_OUTPUT"
echo "::endgroup::"

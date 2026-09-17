#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dispatcher="${project_root}/scripts/dispatch-approved-provider-release.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

fail() { echo "Provider approval contract failed: $1" >&2; exit 1; }
mkdir -p "${temp_dir}/bin"
cat >"${temp_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while (($#)); do
  if [[ "$1" == "--data" ]]; then printf '%s' "$2" >"${CAPTURED_DISPATCH_PAYLOAD}"; exit 0; fi
  shift
done
exit 1
EOF
chmod +x "${temp_dir}/bin/curl"

capture="${temp_dir}/dispatch.json"
PATH="${temp_dir}/bin:${PATH}" CAPTURED_DISPATCH_PAYLOAD="${capture}" \
  TARGET_GITHUB_REPOSITORY="example/voice-app" TARGET_GITHUB_TOKEN="test-token" \
  APPROVED_RELEASE_ID="release-2026-09-17" \
  APPROVED_CHANGE_SUMMARY="Updated Advisor greeting and tool routing" \
  bash "${dispatcher}"

CAPTURED_DISPATCH_PAYLOAD="${capture}" node <<'NODE' || fail "approved release payload is missing traceable metadata"
const fs = require("node:fs");
const payload = JSON.parse(fs.readFileSync(process.env.CAPTURED_DISPATCH_PAYLOAD, "utf8"));
if (payload.event_type !== "elevenlabs_configuration_approved") process.exit(1);
if (payload.client_payload?.release_id !== "release-2026-09-17") process.exit(1);
if (payload.client_payload?.change_summary !== "Updated Advisor greeting and tool routing") process.exit(1);
NODE

for missing_field in release_id change_summary; do
  release_id="release-sensitive-value"
  change_summary="summary-sensitive-value"
  [[ "${missing_field}" == "release_id" ]] && release_id=""
  [[ "${missing_field}" == "change_summary" ]] && change_summary=""
  error_file="${temp_dir}/${missing_field}.error"
  if PATH="${temp_dir}/bin:${PATH}" CAPTURED_DISPATCH_PAYLOAD="${capture}" \
    TARGET_GITHUB_REPOSITORY="example/voice-app" TARGET_GITHUB_TOKEN="token-sensitive-value" \
    APPROVED_RELEASE_ID="${release_id}" APPROVED_CHANGE_SUMMARY="${change_summary}" \
    bash "${dispatcher}" >"${error_file}" 2>&1; then
    fail "missing ${missing_field} was accepted"
  fi
  grep -q "requires ${missing_field}" "${error_file}" || fail "failure does not identify ${missing_field}"
  if grep -Eq 'sensitive-value|example/voice-app' "${error_file}"; then fail "failure logs dispatch inputs"; fi
done

echo "Provider approval contract passed"

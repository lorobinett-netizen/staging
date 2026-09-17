#!/usr/bin/env bash
set -euo pipefail

repository="${TARGET_GITHUB_REPOSITORY:-}"
token="${TARGET_GITHUB_TOKEN:-}"
release_id="${APPROVED_RELEASE_ID:-}"
change_summary="${APPROVED_CHANGE_SUMMARY:-}"

[[ -n "${repository}" ]] || { echo "Approved provider release dispatch requires TARGET_GITHUB_REPOSITORY." >&2; exit 1; }
[[ -n "${token}" ]] || { echo "Approved provider release dispatch requires TARGET_GITHUB_TOKEN." >&2; exit 1; }

payload="$(
  RELEASE_ID="${release_id}" CHANGE_SUMMARY="${change_summary}" node <<'NODE'
const releaseId = (process.env.RELEASE_ID || "").trim();
const changeSummary = (process.env.CHANGE_SUMMARY || "").trim();
const validate = (name, value, maxLength) => {
  if (!value) { console.error(`Approved provider release dispatch requires ${name}.`); process.exit(1); }
  if (value.length > maxLength || /[\u0000-\u001f\u007f]/.test(value)) {
    console.error(`Approved provider release dispatch requires valid single-line ${name} within ${maxLength} characters.`);
    process.exit(1);
  }
};
validate("release_id", releaseId, 120);
validate("change_summary", changeSummary, 240);
process.stdout.write(JSON.stringify({
  event_type: "elevenlabs_configuration_approved",
  client_payload: { release_id: releaseId, change_summary: changeSummary },
}));
NODE
)"

curl --fail --silent --show-error \
  --request POST \
  --header "Accept: application/vnd.github+json" \
  --header "Authorization: Bearer ${token}" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  --data "${payload}" \
  "https://api.github.com/repos/${repository}/dispatches"

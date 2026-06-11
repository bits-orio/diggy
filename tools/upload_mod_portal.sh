#!/usr/bin/env bash
# Upload a built mod zip to the Factorio mod portal.
# Idempotent: skips upload (exit 0) if the version is already published.
#
# Usage: tools/upload_mod_portal.sh <mod_name> <version> <zip_path>
# Env:   FACTORIO_API_KEY (required) — token with "ModPortal: Upload Mods" scope
#
# API: https://wiki.factorio.com/Mod_upload_API
set -euo pipefail

MOD="${1:?mod name required}"
VERSION="${2:?version required}"
ZIP="${3:?zip path required}"

: "${FACTORIO_API_KEY:?FACTORIO_API_KEY env var not set}"
[[ -f "$ZIP" ]] || { echo "zip not found: $ZIP" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

echo "::group::Idempotency check"
# Public endpoint — no auth needed. /full includes the releases array with
# every published version. If our version is already there, this is a re-run
# and we should noop.
FIRST_PUBLISH=""
PORTAL_INFO=$(curl -fsSL "https://mods.factorio.com/api/mods/${MOD}/full" || echo "")
if [[ -z "$PORTAL_INFO" ]]; then
    echo "mod '${MOD}' not on the portal yet — using init_publish (first release)"
    FIRST_PUBLISH=1
else
    EXISTING=$(echo "$PORTAL_INFO" \
        | jq -r --arg v "$VERSION" '.releases[]? | select(.version == $v) | .version')
    if [[ "$EXISTING" == "$VERSION" ]]; then
        echo "version ${VERSION} already published to mod portal — skipping upload"
        echo "::endgroup::"
        exit 0
    fi
fi
echo "::endgroup::"

# Brand-new mods go through init_publish (creates the portal entry); released
# mods add versions through init_upload.
if [[ -n "$FIRST_PUBLISH" ]]; then
    INIT_ENDPOINT="https://mods.factorio.com/api/v2/mods/init_publish"
else
    INIT_ENDPOINT="https://mods.factorio.com/api/v2/mods/releases/init_upload"
fi

echo "::group::Step 1 — ${INIT_ENDPOINT##*/}"
INIT_RESPONSE=$(curl -sS \
    -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer ${FACTORIO_API_KEY}" \
    -F "mod=${MOD}" \
    "$INIT_ENDPOINT")

INIT_HTTP=$(echo "$INIT_RESPONSE" | tail -n1 | cut -d: -f2)
INIT_BODY=$(echo "$INIT_RESPONSE" | sed '$d')

# Don't echo the body unredacted — it contains a one-shot upload URL with
# embedded auth that we still need to use in step 2. Show structure only.
echo "init_upload HTTP ${INIT_HTTP}"

if [[ "$INIT_HTTP" -lt 200 ]] || [[ "$INIT_HTTP" -ge 300 ]]; then
    echo "init_upload failed:" >&2
    echo "$INIT_BODY" >&2
    exit 1
fi

UPLOAD_URL=$(echo "$INIT_BODY" | jq -r '.upload_url // empty')
if [[ -z "$UPLOAD_URL" ]]; then
    echo "init_upload returned no upload_url:" >&2
    echo "$INIT_BODY" >&2
    exit 1
fi
echo "got upload_url"
echo "::endgroup::"

echo "::group::Step 2 — upload zip"
UPLOAD_RESPONSE=$(curl -sS \
    -w "\nHTTP_CODE:%{http_code}" \
    -F "file=@${ZIP}" \
    "$UPLOAD_URL")

UPLOAD_HTTP=$(echo "$UPLOAD_RESPONSE" | tail -n1 | cut -d: -f2)
UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | sed '$d')

echo "upload HTTP ${UPLOAD_HTTP}"
echo "$UPLOAD_BODY"

if [[ "$UPLOAD_HTTP" -lt 200 ]] || [[ "$UPLOAD_HTTP" -ge 300 ]]; then
    echo "upload failed" >&2
    exit 1
fi

SUCCESS=$(echo "$UPLOAD_BODY" | jq -r '.success // false')
if [[ "$SUCCESS" != "true" ]]; then
    echo "upload returned non-success body" >&2
    exit 1
fi

echo "uploaded ${MOD} ${VERSION} to mod portal"
echo "::endgroup::"

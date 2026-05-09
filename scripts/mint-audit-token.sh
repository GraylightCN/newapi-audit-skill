#!/usr/bin/env bash
# mint 新 audit token
# 环境变量：NEWAPI_BASE_URL, NEWAPI_ADMIN_ACCESS_TOKEN, NEWAPI_ADMIN_USER_ID
# 输出：token 明文到 stdout，提示用户存入 NEWAPI_AUDIT_TOKEN secret

set -euo pipefail

if [[ -z "${NEWAPI_BASE_URL:-}" ]]; then
  echo "ERROR: NEWAPI_BASE_URL is required" >&2
  exit 2
fi
if [[ -z "${NEWAPI_ADMIN_ACCESS_TOKEN:-}" ]]; then
  echo "ERROR: NEWAPI_ADMIN_ACCESS_TOKEN is required" >&2
  exit 2
fi
if [[ -z "${NEWAPI_ADMIN_USER_ID:-}" ]]; then
  echo "ERROR: NEWAPI_ADMIN_USER_ID is required" >&2
  exit 2
fi

base="${NEWAPI_BASE_URL%/}"
name="${NEWAPI_AUDIT_TOKEN_NAME:-openclaw-graylight-audit}"

tmp_body="$(mktemp)"
trap 'rm -f "$tmp_body"' EXIT

# Expected NewAPI audit-token mint endpoint from graylight-audit-readonly PR.
# If the deployed endpoint differs, adjust only this generic mint helper; reporting logic stays in SKILL.md.
http_code="$(
  curl -sS -X POST "$base/api/audit-token/" \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    -H "Authorization: ${NEWAPI_ADMIN_ACCESS_TOKEN}" \
    -H "New-Api-User: ${NEWAPI_ADMIN_USER_ID}" \
    -d "{\"name\":\"${name}\"}" \
    -w '%{http_code}' \
    -o "$tmp_body"
)"

if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  cat "$tmp_body" >&2
  echo "" >&2
  echo "ERROR: failed to mint audit token, HTTP $http_code" >&2
  exit 1
fi

python3 - "$tmp_body" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

if not data.get('success'):
    print(json.dumps(data, ensure_ascii=False, indent=2), file=sys.stderr)
    print('ERROR: mint returned success=false', file=sys.stderr)
    sys.exit(1)

token = data.get('data', {}).get('token')
if not isinstance(token, str) or not token:
    print(json.dumps(data, ensure_ascii=False, indent=2), file=sys.stderr)
    print('ERROR: data.data.token missing or empty in response; schema may have changed', file=sys.stderr)
    sys.exit(1)

print(token)
PY

echo "Store the token above in OpenClaw secrets as NEWAPI_AUDIT_TOKEN." >&2

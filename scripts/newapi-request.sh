#!/usr/bin/env bash
# 通用 NewAPI 请求脚本
# 环境变量：
#   NEWAPI_BASE_URL    必须
#   NEWAPI_AUDIT_TOKEN 必须（或 NEWAPI_ADMIN_ACCESS_TOKEN for admin endpoints）
#   NEWAPI_ADMIN_USER_ID 可选
#   TOKEN_TYPE         可选，audit(默认) 或 admin
# 用法：
#   NEWAPI_BASE_URL=https://ai.graylight.cn \
#   NEWAPI_AUDIT_TOKEN=xxx \
#   bash scripts/newapi-request.sh GET /api/user/?page_size=100
#
# 输出：HTTP 响应 JSON（stdout），错误信息（stderr）

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: bash scripts/newapi-request.sh GET /api/path[?query]

Environment:
  NEWAPI_BASE_URL              required
  NEWAPI_AUDIT_TOKEN           required when TOKEN_TYPE=audit (default)
  NEWAPI_ADMIN_ACCESS_TOKEN    required when TOKEN_TYPE=admin
  NEWAPI_ADMIN_USER_ID         optional; sent as New-Api-User when set
  TOKEN_TYPE                   audit (default) or admin
USAGE
}

if [[ $# -lt 2 ]]; then
  usage
  exit 2
fi

method="$1"
path="$2"
token_type="${TOKEN_TYPE:-audit}"

if [[ -z "${NEWAPI_BASE_URL:-}" ]]; then
  echo "ERROR: NEWAPI_BASE_URL is required" >&2
  exit 2
fi

case "$method" in
  GET) ;;
  *) echo "ERROR: only GET is supported by the audit skill" >&2; exit 2 ;;
esac

base="${NEWAPI_BASE_URL%/}"
if [[ "$path" != /* ]]; then
  path="/$path"
fi
url="$base$path"

headers=( -H 'Accept: application/json' )

case "$token_type" in
  audit)
    if [[ -z "${NEWAPI_AUDIT_TOKEN:-}" ]]; then
      echo "ERROR: NEWAPI_AUDIT_TOKEN is required for TOKEN_TYPE=audit" >&2
      exit 2
    fi
    headers+=( -H "Authorization: Bearer ${NEWAPI_AUDIT_TOKEN}" )
    ;;
  admin)
    if [[ -z "${NEWAPI_ADMIN_ACCESS_TOKEN:-}" ]]; then
      echo "ERROR: NEWAPI_ADMIN_ACCESS_TOKEN is required for TOKEN_TYPE=admin" >&2
      exit 2
    fi
    headers+=( -H "Authorization: ${NEWAPI_ADMIN_ACCESS_TOKEN}" )
    ;;
  *)
    echo "ERROR: TOKEN_TYPE must be audit or admin" >&2
    exit 2
    ;;
esac

if [[ -n "${NEWAPI_ADMIN_USER_ID:-}" ]]; then
  headers+=( -H "New-Api-User: ${NEWAPI_ADMIN_USER_ID}" )
fi

tmp_body="$(mktemp)"
trap 'rm -f "$tmp_body"' EXIT

http_code="$(
  curl -sS -X GET "${headers[@]}" \
    -w '%{http_code}' \
    -o "$tmp_body" \
    "$url"
)"

cat "$tmp_body"

if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  echo "" >&2
  echo "ERROR: NewAPI request failed with HTTP $http_code: $method $path" >&2
  exit 1
fi

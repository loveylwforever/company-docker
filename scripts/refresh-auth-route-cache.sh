#!/usr/bin/env bash
# 在服务器上手动刷新 company-auth 路由/配置缓存（POST /tools/cache/refresh）。
#
# 用法（在 company-docker 目录或任意路径）：
#   ./scripts/refresh-auth-route-cache.sh
#   AUTH_API_BASE=http://127.0.0.1:8080 ./scripts/refresh-auth-route-cache.sh
#   AUTH_API_BASE=http://192.168.0.125:8080 ./scripts/refresh-auth-route-cache.sh
#
# 从 admin-dashboard 容器内调用（同 compose 网络，需容器内有 curl）：
#   docker exec company-admin-dashboard sh -c 'AUTH_API_BASE=http://auth:8080 /path/to/refresh-auth-route-cache.sh'
#
set -euo pipefail

AUTH_API_BASE="${AUTH_API_BASE:-http://127.0.0.1:8080}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-5}"
CURL_MAX_TIME="${CURL_MAX_TIME:-30}"

# 去掉末尾 /
AUTH_API_BASE="${AUTH_API_BASE%/}"
URL="${AUTH_API_BASE}/tools/cache/refresh"

if ! command -v curl >/dev/null 2>&1; then
  echo "error: curl 未安装" >&2
  exit 1
fi

echo "POST ${URL}"

HTTP_BODY="$(mktemp)"
HTTP_CODE="$(
  curl -sS \
    -X POST \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    --connect-timeout "$CURL_CONNECT_TIMEOUT" \
    --max-time "$CURL_MAX_TIME" \
    -o "$HTTP_BODY" \
    -w '%{http_code}' \
    "$URL" \
    || echo "000"
)"

BODY="$(cat "$HTTP_BODY")"
rm -f "$HTTP_BODY"

echo "HTTP ${HTTP_CODE}"
echo "${BODY}"

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "error: 请求失败 (HTTP ${HTTP_CODE})" >&2
  exit 1
fi

# 响应示例: {"success":true,"message":"cache refresh triggered"}
if command -v python3 >/dev/null 2>&1; then
  SUCCESS="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('success', False))" <<<"$BODY" 2>/dev/null || echo "False")"
elif command -v jq >/dev/null 2>&1; then
  SUCCESS="$(jq -r '.success // false' <<<"$BODY")"
else
  if [[ "$BODY" == *'"success":true'* ]] || [[ "$BODY" == *'"success": true'* ]]; then
    SUCCESS="True"
  else
    SUCCESS="False"
  fi
fi

if [[ "$SUCCESS" != "True" && "$SUCCESS" != "true" ]]; then
  echo "error: auth 返回 success=false" >&2
  exit 1
fi

echo "ok: 路由/配置缓存已刷新"

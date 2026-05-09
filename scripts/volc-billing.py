#!/usr/bin/env python3
"""
通用火山 Billing API 请求脚本
环境变量：
  VOLC_ACCESS_KEY  必须
  VOLC_SECRET_KEY  必须
  VOLC_REGION      可选，默认 cn-beijing
用法：
  VOLC_ACCESS_KEY=xxx VOLC_SECRET_KEY=xxx python scripts/volc-billing.py QueryBalanceAcct
  VOLC_ACCESS_KEY=xxx VOLC_SECRET_KEY=xxx python scripts/volc-billing.py ListBill '{"BillPeriod":"2026-05"}'
输出：API 响应 JSON（stdout），错误信息（stderr）
"""

from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

SERVICE = "billing"
VERSION = "2022-01-01"
HOST = "open.volcengineapi.com"
ENDPOINT = f"https://{HOST}/"
ALGORITHM = "HMAC-SHA256"
DEFAULT_REGION = "cn-beijing"


def die(message: str, code: int = 2) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(code)


def hmac_sha256(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def sha256_hex(data: str | bytes) -> str:
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def canonical_query(params: dict[str, object]) -> str:
    pairs: list[tuple[str, str]] = []
    for key, value in params.items():
        if value is None:
            continue
        if isinstance(value, bool):
            value = "true" if value else "false"
        pairs.append((str(key), str(value)))
    pairs.sort(key=lambda item: item[0])
    return urllib.parse.urlencode(pairs, quote_via=urllib.parse.quote, safe="-_.~")


def sign(secret_key: str, date: str, region: str, string_to_sign: str) -> str:
    # Volcengine API V4 signing key:
    # HMAC(HMAC(HMAC(HMAC(secret, date), region), service), "request")
    k_date = hmac_sha256(secret_key.encode("utf-8"), date)
    k_region = hmac_sha256(k_date, region)
    k_service = hmac_sha256(k_region, SERVICE)
    k_signing = hmac_sha256(k_service, "request")
    return hmac.new(k_signing, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()


def request(action: str, extra_params: dict[str, object]) -> dict[str, object]:
    access_key = os.environ.get("VOLC_ACCESS_KEY")
    secret_key = os.environ.get("VOLC_SECRET_KEY")
    region = os.environ.get("VOLC_REGION", DEFAULT_REGION)

    if not access_key:
        die("VOLC_ACCESS_KEY is required")
    if not secret_key:
        die("VOLC_SECRET_KEY is required")

    now = dt.datetime.now(dt.timezone.utc)
    x_date = now.strftime("%Y%m%dT%H%M%SZ")
    short_date = now.strftime("%Y%m%d")

    params: dict[str, object] = {
        "Action": action,
        "Version": VERSION,
        **extra_params,
    }
    query = canonical_query(params)

    payload_hash = sha256_hex(b"")
    canonical_headers = (
        f"host:{HOST}\n"
        f"x-content-sha256:{payload_hash}\n"
        f"x-date:{x_date}\n"
    )
    signed_headers = "host;x-content-sha256;x-date"
    canonical_request = "\n".join(
        [
            "GET",
            "/",
            query,
            canonical_headers,
            signed_headers,
            payload_hash,
        ]
    )

    credential_scope = f"{short_date}/{region}/{SERVICE}/request"
    string_to_sign = "\n".join(
        [
            ALGORITHM,
            x_date,
            credential_scope,
            sha256_hex(canonical_request),
        ]
    )
    signature = sign(secret_key, short_date, region, string_to_sign)
    authorization = (
        f"{ALGORITHM} Credential={access_key}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )

    req = urllib.request.Request(
        f"{ENDPOINT}?{query}",
        method="GET",
        headers={
            "Authorization": authorization,
            "Host": HOST,
            "X-Date": x_date,
            "X-Content-Sha256": payload_hash,
            "Accept": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        print(body, file=sys.stderr)
        die(f"Volcengine Billing API failed with HTTP {exc.code}", 1)
    except urllib.error.URLError as exc:
        die(f"Volcengine Billing API request failed: {exc}", 1)

    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        print(raw)
        die("Volcengine Billing API returned non-JSON response", 1)


def main() -> None:
    if len(sys.argv) not in (2, 3):
        die(
            "Usage: python scripts/volc-billing.py <Action> [json_params]",
            2,
        )

    action = sys.argv[1]
    params: dict[str, object] = {}
    if len(sys.argv) == 3:
        try:
            loaded = json.loads(sys.argv[2])
        except json.JSONDecodeError as exc:
            die(f"invalid json_params: {exc}")
        if not isinstance(loaded, dict):
            die("json_params must be a JSON object")
        params = loaded

    result = request(action, params)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()

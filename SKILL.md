---
name: graylight-audit
description: Graylight NewAPI 账单查询 + 火山主账户余额监控，支持 daily report（cron）和交互查询。Use when querying Graylight NewAPI user balances, consumption logs, topups, channels, audit tokens, Volcengine Billing balances/bills, or preparing Feishu audit reports.
---

# Graylight Audit Skill

Graylight NewAPI 查账与火山主账户余额监控 skill。它不提供固定日报脚本；OpenClaw 读取本 skill 后，按需求调用通用请求脚本、聚合 JSON、生成交互答复或 cron 飞书日报。

## Principles

- 不写固定业务脚本：不要新增 `daily_report.py` / `audit.py` 这类固化报告逻辑的脚本。
- 只用通用请求脚本：`scripts/newapi-request.sh` 和 `scripts/volc-billing.py` 只负责发请求并返回 JSON。
- 报表聚合、低余额过滤、TOP 排名、飞书消息排版由 OpenClaw 运行时完成。
- 低余额阈值不要写进配置文件；写在 cron job description 文本里，运行时可直接改。
- Secrets 全部使用 OpenClaw secrets 系统。

## Required Secrets

| Key | 说明 |
| --- | --- |
| `NEWAPI_BASE_URL` | NewAPI 服务地址，如 `https://ai.graylight.cn` |
| `NEWAPI_ADMIN_ACCESS_TOKEN` | NewAPI admin 用户 access token，用于 mint audit token 和 admin endpoints |
| `NEWAPI_ADMIN_USER_ID` | NewAPI admin 用户 ID（数字）；查账时也建议带入 audit log |
| `NEWAPI_AUDIT_TOKEN` | skill 自己 mint 的 audit token；缺失时提示先 mint |
| `VOLC_ACCESS_KEY` | 火山只读 IAM 子账户 AK |
| `VOLC_SECRET_KEY` | 火山只读 IAM 子账户 SK |
| `VOLC_REGION` | 火山区域，默认 `cn-beijing` |
| `FEISHU_WEBHOOK_URL` | 飞书群机器人 webhook URL |

> 使用时先从 OpenClaw secrets 读取并导出到环境变量，再执行脚本。不要把 secret 写入仓库、cron 文件或日志。

## First Run: Mint Audit Token

首次使用前，确认 NewAPI audit token 是否已存在于 secrets：`NEWAPI_AUDIT_TOKEN`。

若缺失，用 admin token mint：

```bash
NEWAPI_BASE_URL=https://ai.graylight.cn \
NEWAPI_ADMIN_ACCESS_TOKEN=xxx \
NEWAPI_ADMIN_USER_ID=123 \
bash scripts/mint-audit-token.sh
```

脚本会把 audit token 明文输出到 stdout。手动存入 OpenClaw secrets：`NEWAPI_AUDIT_TOKEN`。不要在聊天、日志或仓库中长期保留明文 token。

如果 audit token 调查账 API 返回 401/403，也按同样方式重新 mint 并更新 `NEWAPI_AUDIT_TOKEN`。

## NewAPI Audit API

### Authentication

Audit endpoints use:

```http
Authorization: Bearer ***<audit_token_plaintext>
New-Api-User: <admin_user_id>
```

`New-Api-User` 在查账时也要带，用于 audit log。Admin endpoints use the admin access token directly:

```http
Authorization: <admin_access_token>
New-Api-User: <admin_user_id>
```

Use the generic helper:

```bash
NEWAPI_BASE_URL=https://ai.graylight.cn \
NEWAPI_AUDIT_TOKEN=xxx \
NEWAPI_ADMIN_USER_ID=123 \
bash scripts/newapi-request.sh GET '/api/user/?page_size=100'
```

Set `TOKEN_TYPE=admin` for admin endpoints.

### Quota Conversion

NewAPI 内部 quota 单位：

```text
500000 quota ≈ $1 ≈ ¥7.3
```

显示人民币余额：

```text
rmb = quota / 500000 * 7.3
quota = rmb / 7.3 * 500000
```

低余额阈值用人民币。例如“低于 ¥10”：

```text
quota < 10 / 7.3 * 500000 ≈ 684931
```

汇率可能变动；如果 Jay 更新汇率，运行时按新汇率计算。

### Whitelisted GET Endpoints

#### `GET /api/user/`

参数：

- `p=<页码 1-based>`
- `page_size=<每页数量，建议100>`

返回：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": 17,
        "username": "alice",
        "display_name": "Alice",
        "quota": 123456,
        "used_quota": 7890,
        "request_count": 42,
        "email": "alice@example.com"
      }
    ],
    "total": 1
  }
}
```

说明：所有用户列表，含余额 `quota`、已用 `used_quota`、请求次数 `request_count`。

#### `GET /api/user/:id`

返回：

```json
{
  "success": true,
  "data": {
    "id": 17,
    "username": "alice",
    "quota": 123456,
    "used_quota": 7890,
    "request_count": 42
  }
}
```

说明：单用户详情。

#### `GET /api/log/`

参数：

- `type=2`：消费日志
- `start_timestamp=<unix>`
- `end_timestamp=<unix>`
- `p=<page>`
- `page_size=<n>`
- `username=<可选>`

返回：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": 1,
        "user_id": 17,
        "username": "alice",
        "model_name": "doubao-pro",
        "quota": 5000,
        "prompt_tokens": 1000,
        "completion_tokens": 500,
        "created_at": 1778288400
      }
    ],
    "total": 1
  }
}
```

说明：消费日志，`type=2` 为消费类型；按 `quota` 汇总消费并换算人民币。

#### `GET /api/user/topup`

参数：

- `p=<page>`
- `page_size=<n>`

返回：

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": 1,
        "user_id": 17,
        "amount": 1000000,
        "created_at": 1778288400
      }
    ],
    "total": 1
  }
}
```

说明：充值历史。

#### `GET /api/channel/`

参数：

- `p=<page>`
- `page_size=<n>`

返回：

```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "name": "volc-main",
      "balance": 100.5
    }
  ]
}
```

说明：channel 列表，含各 channel 在火山的余额（字段以实际部署返回为准）。

#### `GET /api/audit-token/`

Headers：

```http
Authorization: <admin_access_token>
New-Api-User: <admin_user_id>
```

返回：

```json
{
  "success": true,
  "data": [
    {"id": 1, "name": "openclaw-graylight-audit", "created_at": 1778288400}
  ]
}
```

说明：列出所有 audit token，需要 admin access token，不是 audit token。

## Volcengine Billing API

Use `scripts/volc-billing.py`. It implements Volcengine V4 signing with Python standard library only.

Docs: https://www.volcengine.com/docs/6269

Environment:

- `VOLC_ACCESS_KEY` required
- `VOLC_SECRET_KEY` required
- `VOLC_REGION` optional, default `cn-beijing`

### `QueryBalanceAcct`

```text
Service: billing
Version: 2022-01-01
Action: QueryBalanceAcct
Method: GET
```

Usage:

```bash
VOLC_ACCESS_KEY=xxx VOLC_SECRET_KEY=xxx \
python scripts/volc-billing.py QueryBalanceAcct
```

Returns JSON like:

```json
{
  "Result": {
    "Balance": "1000.00",
    "CashBalance": "800.00",
    "CreditBalance": "200.00"
  }
}
```

说明：账户余额（现金 + 信用额度）。字段以火山实际返回为准。

### `ListBill`

```text
Action: ListBill
```

参数：

- `BillPeriod=2026-05` (`YYYY-MM`)
- `PageSize=20`
- `PageNum=1`

Usage:

```bash
VOLC_ACCESS_KEY=xxx VOLC_SECRET_KEY=xxx \
python scripts/volc-billing.py ListBill '{"BillPeriod":"2026-05","PageSize":20,"PageNum":1}'
```

说明：按月账单列表，可用于趋势分析。

## Daily Report via Cron

Daily report 不是固定脚本，而是 OpenClaw 根据本 skill 知识组装执行：拉取 JSON、聚合、换算、排版、推送飞书。

Recommended cron:

```yaml
name: graylight-daily-audit
schedule: cron 0 9,13,21 * * * (Asia/Shanghai)
description: |
  Graylight 查账日报。低余额告警阈值：¥10（修改此处即可调整）。
  执行步骤：
  1. 调 GET /api/user/?page_size=100 拉所有用户余额，翻页直到取完，换算人民币，找出低于阈值的用户
  2. 调 GET /api/log/?type=2&start_timestamp=<24h前>&end_timestamp=<now>&page_size=100 拉消费日志，翻页直到取完
  3. 调 volc-billing.py QueryBalanceAcct 拉火山账户余额
  4. 组装飞书消息推送到 FEISHU_WEBHOOK_URL

  消息格式参考：
  📊 Graylight 查账日报 [时间]
  🏦 火山账户余额：¥XXXX（若失败：标注错误原因）
  👥 用户总余额：¥XXXX | 24h消费：¥XXX（N次）
  🔝 24h消费TOP5：...
  ⚠️ 低余额用户（低于¥10）：...
```

Runtime notes:

- 低余额阈值从 cron description 读取，不从仓库配置读取。
- 飞书 webhook 推送是外部写操作；只在 cron 明确配置或用户明确要求时发送。
- 火山余额查询失败时，不中断 NewAPI 报表；在消息中标注错误原因。
- NewAPI 分页以 `total` 和 `items` 长度判断；不要默认只有第一页。

## Interactive Query Examples

### “user 17 上周用了多少”

1. `GET /api/user/17` 获取 username。
2. 计算上周一 00:00 到本周一 00:00 的 Unix timestamp。
3. `GET /api/log/?type=2&start_timestamp=<last_monday>&end_timestamp=<this_monday>&username=<username>&page_size=100`，翻页直到取完。
4. 汇总 `quota` 列，按 `quota / 500000 * 7.3` 换算人民币。

### “火山账户现在还有多少”

```bash
python scripts/volc-billing.py QueryBalanceAcct
```

解析 `Result.Balance` / `CashBalance` / `CreditBalance`。

### “余额低于5元的用户”

1. `GET /api/user/?page_size=100`，翻页直到取完。
2. 过滤：`quota < 5 / 7.3 * 500000`。
3. 输出用户 ID、username/display_name、quota、人民币余额。

### “本月消费最高的5个用户”

1. 计算本月 1 日 00:00 到 now 的 Unix timestamp。
2. `GET /api/log/?type=2&start_timestamp=<month_start>&end_timestamp=<now>&page_size=100`，翻页直到取完。
3. 按 `user_id` / `username` 聚合 `quota`。
4. 降序取 TOP5，换算人民币。

## Audit Token Expiry Recovery

If an audit request returns 401/403:

```bash
NEWAPI_BASE_URL=https://ai.graylight.cn \
NEWAPI_ADMIN_ACCESS_TOKEN=xxx \
NEWAPI_ADMIN_USER_ID=123 \
bash scripts/mint-audit-token.sh
```

Then update `NEWAPI_AUDIT_TOKEN` in OpenClaw secrets and retry. If mint fails, verify PR 27 is deployed and admin token is valid.

## Operational Prerequisites

Before production use, complete these manual steps:

1. NewAPI 合并 PR 27（`graylight-audit-readonly` 分支）并部署。
2. Admin 在 NewAPI 后台生成 access token。
3. 火山控制台创建只读子账户 `graylight-audit-readonly`，挂 `BillingReadOnlyAccess` 策略，生成 AK/SK。
4. 飞书建群机器人，拿 `FEISHU_WEBHOOK_URL`。
5. 首次运行 `scripts/mint-audit-token.sh`，将输出 token 存入 `NEWAPI_AUDIT_TOKEN` secret。

## Script Reference

### `scripts/newapi-request.sh`

Generic NewAPI request helper. Env-driven. It does no aggregation or formatting.

```bash
NEWAPI_BASE_URL=https://ai.graylight.cn \
NEWAPI_AUDIT_TOKEN=xxx \
NEWAPI_ADMIN_USER_ID=123 \
bash scripts/newapi-request.sh GET '/api/user/?page_size=100'
```

For admin endpoints:

```bash
TOKEN_TYPE=admin \
NEWAPI_BASE_URL=https://ai.graylight.cn \
NEWAPI_ADMIN_ACCESS_TOKEN=xxx \
NEWAPI_ADMIN_USER_ID=123 \
bash scripts/newapi-request.sh GET '/api/audit-token/'
```

### `scripts/volc-billing.py`

Generic Volcengine Billing API helper. Env-driven. It does no reporting.

```bash
python scripts/volc-billing.py QueryBalanceAcct
python scripts/volc-billing.py ListBill '{"BillPeriod":"2026-05"}'
```

### `scripts/mint-audit-token.sh`

Mints a new audit token using NewAPI admin access token. Outputs the token plaintext to stdout only.

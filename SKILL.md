---
name: graylight-audit
description: Graylight NewAPI 账单查询与火山主账户余额监控。当用户询问 NewAPI 用户余额、消费用量、充值记录、低余额用户、消费排名、channel 列表时使用；当询问火山账户余额或账单时使用；当需要生成查账日报、创建查账 cron job 时使用。
metadata: {"openclaw": {"requires": {"env": ["NEWAPI_BASE_URL", "NEWAPI_AUDIT_TOKEN", "VOLC_ACCESS_KEY", "VOLC_SECRET_KEY"]}, "primaryEnv": "NEWAPI_AUDIT_TOKEN"}}
---

# Graylight Audit Skill

Graylight 查账 skill。不提供固定日报脚本——OpenClaw 读取本文档后，按需调用通用请求脚本、聚合 JSON、生成交互答复或 cron 日报。

## Secrets（存入 OpenClaw secrets）

OpenClaw secrets 存储在 `openclaw.json` 的 `skills.entries.graylight-audit.env` 下。
安装后在 OpenClaw 设置 → Skills → graylight-audit 中填写各项，或通过 `gateway config.patch` 写入。

| Key | 说明 |
|-----|------|
| `NEWAPI_BASE_URL` | NewAPI 服务地址，如 `https://ai.graylight.cn` |
| `NEWAPI_AUDIT_TOKEN` | 查账 token；缺失时读 [references/admin-setup.md](references/admin-setup.md) 执行 mint |
| `VOLC_ACCESS_KEY` | 火山只读 IAM 子账户 AK |
| `VOLC_SECRET_KEY` | 火山只读 IAM 子账户 SK |
| `VOLC_REGION` | 火山区域，默认 `cn-beijing` |

> Admin token 仅初始化时需要 → 见 [references/admin-setup.md](references/admin-setup.md)

## Pricing

Graylight 计价：**$1 = ¥1**，**500000 quota = ¥1**，直接显示 ¥，无需汇率换算。

```
¥ = quota / 500000
quota = ¥ * 500000
```

低余额阈值用 ¥，例如"低于 ¥10" → `quota < 5000000`。

## NewAPI Audit API

**鉴权（所有查账请求）：**

```http
Authorization: Bearer <NEWAPI_AUDIT_TOKEN>
```

使用通用脚本：

```bash
NEWAPI_BASE_URL=https://ai.graylight.cn \
NEWAPI_AUDIT_TOKEN=<token> \
bash scripts/newapi-request.sh GET '/api/user/?page_size=100'
```

### `GET /api/user/`

参数：`p`（页码，1-based）、`page_size`（建议 100）

```json
{
  "success": true,
  "data": {
    "items": [{
      "id": 17,
      "username": "alice",
      "display_name": "Alice",
      "email": "alice@example.com",
      "role": 1,
      "status": 1,
      "quota": 5000000,
      "used_quota": 250000,
      "request_count": 42,
      "group": "default"
    }],
    "total": 100
  }
}
```

### `GET /api/user/:id`

返回单个用户，同上字段结构。

### `GET /api/log/`

参数：`type=2`（消费）、`start_timestamp`、`end_timestamp`、`p`、`page_size`、`username`（可选）

```json
{
  "success": true,
  "data": {
    "items": [{
      "id": 1,
      "user_id": 17,
      "username": "alice",
      "token_name": "default",
      "model_name": "doubao-pro-32k",
      "quota": 5000,
      "prompt_tokens": 1000,
      "completion_tokens": 500,
      "use_time": 1200,
      "is_stream": true,
      "channel": 3,
      "channel_name": "volc-main",
      "created_at": 1778288400,
      "type": 2
    }],
    "total": 500
  }
}
```

按 `quota` 字段汇总消费，换算 ¥。

### `GET /api/user/topup`

参数：`p`、`page_size`

```json
{
  "success": true,
  "data": {
    "items": [{
      "id": 1,
      "user_id": 17,
      "amount": 5000000,
      "money": 10.0,
      "trade_no": "PAY-xxx",
      "payment_method": "stripe",
      "status": "done",
      "create_time": 1778288400,
      "complete_time": 1778288500
    }],
    "total": 10
  }
}
```

`amount` 为 quota，`money` 为实际付款金额（¥）。

### `GET /api/channel/`

参数：`p`、`page_size`

```json
{
  "success": true,
  "data": [{
    "id": 1,
    "name": "volc-main",
    "type": 43,
    "status": 1,
    "balance": 100.5,
    "used_quota": 12345678
  }]
}
```

**分页：** 所有列表返回 `{success, data: {items, total}}`（channel 例外，data 直接是数组）；以 `total` 判断是否需要翻页。

## Volcengine Billing API

```bash
VOLC_ACCESS_KEY=<AK> VOLC_SECRET_KEY=<SK> \
python scripts/volc-billing.py QueryBalanceAcct

VOLC_ACCESS_KEY=<AK> VOLC_SECRET_KEY=<SK> \
python scripts/volc-billing.py ListBill '{"BillPeriod":"2026-05"}'
```

`QueryBalanceAcct` 返回示例：

```json
{
  "ResponseMetadata": {"Action": "QueryBalanceAcct"},
  "Result": {
    "Balance": "1000.00",
    "CashBalance": "800.00",
    "CreditBalance": "200.00",
    "AvailableBalance": "1000.00"
  }
}
```

失败时不中断 NewAPI 部分；在报告中标注错误原因。文档：https://www.volcengine.com/docs/6269

## Daily Report（Cron）

日报不是固定脚本，由 OpenClaw 按下方步骤组装执行。

**推荐 cron 配置：**

```yaml
name: graylight-daily-audit
schedule: "0 9,13,21 * * *"   # Asia/Shanghai
description: |
  Graylight 查账日报。低余额告警阈值：¥10（修改此处调整）。
  消息目标：<填写 channel/target，如 feishu 群 ID>
  1. GET /api/user/?page_size=100 拉所有用户余额，翻页取完，找出 quota < 5000000 的用户
  2. GET /api/log/?type=2&start_timestamp=<24h前>&end_timestamp=<now>&page_size=100 翻页取完
  3. python scripts/volc-billing.py QueryBalanceAcct 拉火山余额
  4. 组装消息发送到上方指定目标

  消息参考：
  📊 Graylight 查账日报 [时间]
  🏦 火山余额：¥XXXX（失败则标注原因）
  👥 用户总余额：¥XXXX | 24h消费：¥XXX（N次）
  🔝 24h消费TOP5：...
  ⚠️ 低余额用户（低于¥10）：...
```

## Interactive Query Examples

**"user 17 上周用了多少"**
1. `GET /api/user/17` 拿 username
2. `GET /api/log/?type=2&start_timestamp=<上周一>&end_timestamp=<本周一>&username=alice&page_size=100` 翻页取完
3. 汇总 `quota` → ¥（quota/500000）

**"火山账户还有多少"**
→ `python scripts/volc-billing.py QueryBalanceAcct`，显示 `Result.AvailableBalance`

**"余额低于5元的用户"**
→ `GET /api/user/?page_size=100` 翻页取完，过滤 `quota < 2500000`

**"本月消费最高的5个用户"**
→ 本月起始 timestamp 到 now，`GET /api/log/?type=2&...` 翻页取完，按 `username` 聚合 `quota`，降序 TOP5

## Scripts

| 脚本 | 说明 |
|------|------|
| `scripts/newapi-request.sh` | 通用 NewAPI 请求；`TOKEN_TYPE=admin` 切换 admin 鉴权 |
| `scripts/volc-billing.py` | 火山 Billing V4 签名请求；纯标准库无依赖 |
| `scripts/mint-audit-token.sh` | 初始化专用；见 [references/admin-setup.md](references/admin-setup.md) |

## Audit Token 失效恢复

查账返回 401/403 时，需要人工介入重新 mint（skill 不自动 re-mint，避免 pod 常驻 admin 全权）。

见 [references/admin-setup.md](references/admin-setup.md) 按

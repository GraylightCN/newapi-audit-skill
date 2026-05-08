# Admin Setup & Audit Token Management

仅在初始化或 audit token 失效时需要读本文件。日常查账无需加载。

## Required Secrets（仅初始化时）

| Key | 说明 |
|-----|------|
| `NEWAPI_ADMIN_ACCESS_TOKEN` | NewAPI admin 用户 access token，仅用于 mint / 吊销 audit token |
| `NEWAPI_ADMIN_USER_ID` | NewAPI admin 用户 ID（数字） |

## Mint Audit Token

首次使用前或 audit token 失效后执行：

```bash
NEWAPI_BASE_URL=https://ai.graylight.cn \
NEWAPI_ADMIN_ACCESS_TOKEN=<admin_token> \
NEWAPI_ADMIN_USER_ID=<user_id> \
bash scripts/mint-audit-token.sh
```

脚本输出 token 明文到 stdout。将其存入 OpenClaw secrets：`NEWAPI_AUDIT_TOKEN`。不要在聊天、日志或仓库中保留明文 token。

## Audit Token API（需要 admin token）

```http
Authorization: <admin_access_token>
New-Api-User: <admin_user_id>
```

### 列出所有 audit token
```
GET /api/audit-token/
```
返回：`{success, data: [{id, name, created_at}]}`

### 吊销 audit token
```
DELETE /api/audit-token/:id
```

### Mint 新 token
```
POST /api/audit-token/
Body: {"name": "openclaw-graylight-audit"}
Response: {id, name, token, created_at}   // token 字段仅此次返回明文
```

## Operational Prerequisites

部署前人工完成：
1. NewAPI 合并 PR 27（`graylight-audit-readonly` 分支）并部署
2. Admin 在 NewAPI 后台「个人设置 → 安全 → 系统访问令牌」生成 access token
3. 火山控制台创建只读子账户 `graylight-audit-readonly`，挂 `BillingReadOnlyAccess` 策略，生成 AK/SK
4. 首次运行 `scripts/mint-audit-token.sh`，将 token 存入 `NEWAPI_AUDIT_TOKEN` secret

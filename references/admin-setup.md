# Admin Setup & Audit Token Management

仅在首次初始化或显式 revoke/rotate 时才需要读本文件。日常查账无需加载。

## ⚠️ Admin Token 安全边界

**admin access token 不得常驻 K8s Secret 或 OpenClaw 长期 secrets。**

audit token 体系的目的是让 pod 不常驻 admin 全权。若 admin token 长期在 secret 里，pod 一旦被攻破，攻击者可用它修改用户、删 channel 等所有操作。

**正确做法：运维一次性注入，操作完立即丢弃。**

```bash
# 在运维终端临时注入，不持久化到任何配置文件或 Secret
kubectl exec -it <openclaw-pod> -n graylight-openclaw -- \
  env NEWAPI_BASE_URL=https://ai.graylight.cn \
      NEWAPI_ADMIN_ACCESS_TOKEN=$(read -s -p "admin token: " t && echo $t) \
      NEWAPI_ADMIN_USER_ID=<user_id> \
  bash /path/to/scripts/mint-audit-token.sh
```

操作完成后：
- admin token 不写入任何文件
- 将脚本输出的 audit token 存入 OpenClaw secrets：`NEWAPI_AUDIT_TOKEN`
- 不要在聊天、日志或仓库中保留明文 token

## Audit Token 失效处理

audit token 返回 401/403 时：

**skill 不会自动 re-mint**，需要人工介入：
1. 判断是 token 被 revoke（有人手动吊销）还是 NewAPI 重启清空（不常见）
2. 按下方流程重新 mint，更新 `NEWAPI_AUDIT_TOKEN` secret
3. skill 会在下次调用时使用新 token

自动 re-mint 意味着 pod 必须常驻 admin token，违反上方安全边界，故不实现。

## Mint Audit Token（运维一次性操作）

```bash
NEWAPI_BASE_URL=https://ai.graylight.cn \
NEWAPI_ADMIN_ACCESS_TOKEN=<admin_token> \
NEWAPI_ADMIN_USER_ID=<user_id> \
bash scripts/mint-audit-token.sh
```

脚本输出 audit token 明文到 stdout，固定格式 `aud_...`。将其更新到 OpenClaw secrets `NEWAPI_AUDIT_TOKEN`。

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

### Mint 新 token
```
POST /api/audit-token/
Body: {"name": "openclaw-graylight-audit"}
Response: {"success": true, "message": "", "data": {"id": 1, "name": "openclaw-graylight-audit", "token": "aud_...", "created_at": 1778288400}}
```

`data.token` 仅此次返回明文。`mint-audit-token.sh` 只读 `data.data.token`，schema 变化时显式失败。

### 吊销 audit token
```
DELETE /api/audit-token/:id
```

## Operational Prerequisites

部署前人工完成：
1. ~~NewAPI 合并 PR 27~~ ✅ 已合并
2. Admin 在 NewAPI 后台「个人设置 → 安全 → 系统访问令牌」生成 access token（一次性使用）
3. 火山控制台创建只读子账户 `graylight-audit-readonly`，挂 `BillingReadOnlyAccess` 策略，生成 AK/SK
4. 按上方"一次性注入"方式运行 `mint-audit-token.sh`，将输出 token 存入 `NEWAPI_AUDIT_TOKEN` secret

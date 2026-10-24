# Cloudflare Worker 部署说明（Telegram ↔ DeepSeek）

目标：Telegram 消息 → Cloudflare Worker（常驻云端）→ DeepSeek 思考 → 回复 Telegram。
部署后电脑关机也能正常回复（Worker 跑在 Cloudflare 上）。

## 一、准备工作

1. Cloudflare 账号：https://dash.cloudflare.com/sign-up （免费）
2. 本目录的 `worker.js`（已写好）
3. 已知的两个值：
   - Telegram bot token（@BotFather 获取）
   - DeepSeek API key（platform.deepseek.com 获取）

## 二、方式 A：Dashboard 网页部署（最简单，推荐）

1. 登录 https://dash.cloudflare.com → 左侧 **Workers & Pages** → **Create**
2. 选 **Create Worker** → 名字填 `telegram-bot`（或随意）→ **Deploy**
3. 点 **Edit code**，删掉默认代码，粘贴 `worker.js` 全部内容 → **Deploy**
4. 回到 Worker 页面 → **Settings → Variables and Secrets**，添加：

| 变量名 | 值 | 类型 |
|---|---|---|
| TELEGRAM_TOKEN | 你的 bot token | Secret（加密） |
| LLM_API_KEY | 你的 DeepSeek key | Secret（加密） |
| LLM_BASE_URL | https://api.deepseek.com | Text |
| LLM_MODEL | deepseek-chat | Text |
| TELEGRAM_WEBHOOK_SECRET | 自己编一个随机串（如 my_random_secret_2026） | Secret（加密） |
| ALLOWED_CHAT_IDS | 你的 chat_id（多个用逗号分隔） | Text |

5. 保存后拿到 Worker 地址：`https://<你的worker名>.<你的子域>.workers.dev`

## 三、方式 B：wrangler 命令行部署

```bash
cd cloudflare-worker
# 首次需要登录 Cloudflare（浏览器授权）
npx wrangler login
# 部署（在 wrangler.toml 里配置 name，见下）
npx wrangler deploy
```

wrangler.toml 示例：

```toml
name = "telegram-bot"
main = "worker.js"
compatibility_date = "2026-01-01"

[vars]
LLM_BASE_URL = "https://api.deepseek.com"
LLM_MODEL = "deepseek-chat"
ALLOWED_CHAT_IDS = "你的chat_id"
```

Secrets 用命令行设置：

```bash
npx wrangler secret put TELEGRAM_TOKEN
npx wrangler secret put LLM_API_KEY
npx wrangler secret put TELEGRAM_WEBHOOK_SECRET
```

## 四、绑定 webhook（关键一步）

拿到 Worker 地址后，用 Bash/curl 执行（把 `<TOKEN>`、`<WORKER_URL>`、`<SECRET>` 换成实际值）：

```bash
curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=<WORKER_URL>/webhook&secret_token=<SECRET>"
```

成功返回 `{"ok":true,"result":true,"description":"Webhook was set"}`。

> 注意：webhook 和本地 long polling 不能同时用。
> 设置 webhook 后，本地 `telegram_bot.py` 的轮询会收不到消息（Telegram 会拒绝 getUpdates）。
> 如果要切回本地模式，先删除 webhook：
> `curl "https://api.telegram.org/bot<TOKEN>/deleteWebhook"`

## 五、验证

```bash
# 查看 webhook 状态
curl "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
```

然后在 Telegram 给 bot 发消息，应能收到 AI 回复。

## 六、可选：多轮上下文（KV）

默认单轮问答。想要多轮记忆：

1. Dashboard → **Storage & Databases → KV** → Create namespace（名如 `telegram-history`）
2. 回到 Worker → **Settings → Bindings** → Add → KV namespace → 变量名填 `HISTORY` → 选刚建的 namespace
3. 重新部署后自动多轮（每个 chat 保留最近 20 条上下文）

## 七、排错

- `403 forbidden`：`TELEGRAM_WEBHOOK_SECRET` 不一致，检查 setWebhook 的 secret_token 和 Worker 变量
- 没回复：Dashboard → Worker → **Logs**（实时日志），看 LLM error / fetch failed
- `401`：DeepSeek key 无效或余额不足
- Worker 地址多余斜杠：确保 setWebhook 的 url 是 `https://xxx.workers.dev/webhook`

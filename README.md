# Telegram ↔ AI 桥（Telegram Bot + DeepSeek）

把 Telegram 变成一个随身 AI 助手：给 bot 发消息，AI 思考后回复。
支持两种运行方式：

| 模式 | 说明 | 电脑关机 |
|---|---|---|
| **本地模式**（Python long polling） | 脚本跑在你电脑上，电脑开着才在线 | ❌ 离线 |
| **云端模式**（Cloudflare Worker webhook） | 跑在 Cloudflare 云端，免费额度够个人用 | ✅ 照常在线 |

两种模式共用同一套「消息 → 模型 → 回复」逻辑，只是消息通道不同。**同一时间只能启用一种**（webhook 和 long polling 互斥）。

---

## 目录结构

```
telegram-bot-bridge/
├── README.md                     # 本文件
├── telegram_bot.py               # 本地模式脚本（纯标准库，无需 pip install）
├── start_telegram_bot.bat        # Windows 手动启动脚本
└── cloudflare-worker/            # 云端模式（Cloudflare Worker）
    ├── worker.js                 # Worker 代码：webhook → DeepSeek → 回复
    ├── wrangler.toml             # wrangler 部署配置（变量示例）
    └── README.md                 # Worker 部署详细步骤
```

---

## 前置条件

1. **Telegram Bot Token**
   - Telegram 里找 `@BotFather` → 发 `/newbot` 按提示创建 → 得到 `123456:ABC...`
   - 已有 bot 找回：`@BotFather` → `/mybots` → 选 bot → API Token

2. **LLM API Key**（默认 DeepSeek）
   - https://platform.deepseek.com → 登录 → API Keys → 创建
   - 模型默认 `deepseek-chat`；也支持任何 OpenAI 兼容接口（改 `base_url` + `model` 即可）

---

## 模式一：本地运行（long polling）

### 1. 配置

把 token 和 key 写到脚本同目录：

`telegram_token.txt`（一行）：
```
123456789:AAHxxxxxxxxxxxxxxxxxxxxxxxxxx
```

`llm_config.txt`：
```
api_key=sk-xxxxxxxxxxxxxxxx
base_url=https://api.deepseek.com
model=deepseek-chat
```

> 也可以不用文件，改用环境变量：`TELEGRAM_BOT_TOKEN`、`LLM_API_KEY`、`LLM_BASE_URL`、`LLM_MODEL`

### 2. 运行

```bash
# 验证 bot 在线
python telegram_bot.py --getme

# 只拉一轮消息（排查用）
python telegram_bot.py --once

# 只记录消息不回复
python telegram_bot.py

# 自动回显（测试收发链路）
python telegram_bot.py --reply

# AI 思考并回复（推荐）
python telegram_bot.py --ai
```

Windows 上直接双击 `start_telegram_bot.bat`，或用捆绑 Python 路径运行：

```bat
"C:\path\to\python.exe" -u telegram_bot.py --ai
```

### 3. 开机自启（Windows）

把启动命令写进 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`（用 `pythonw.exe` 可无窗口运行）：

```powershell
$run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Set-ItemProperty -Path $run -Name 'TelegramBotBridge' -Value '"C:\path\to\pythonw.exe" "C:\path\to\telegram_bot.py" --ai'
```

### 4. 消息与用量记录

- `telegram_messages.log`：所有收到的消息（时间、chat、发送者、内容）
- `telegram_usage.log`：每次 AI 回复的 token 用量（prompt / completion / total），方便算成本

---

## 模式二：云端运行（Cloudflare Worker，推荐长期使用）

详细步骤见 [`cloudflare-worker/README.md`](cloudflare-worker/README.md)，核心流程：

1. 注册 Cloudflare（免费）：https://dash.cloudflare.com/sign-up
2. `wrangler login` 登录（或 Dashboard 网页创建 Worker）
3. `wrangler deploy` 部署 `cloudflare-worker/worker.js`
4. 配置变量（Settings → Variables and Secrets）：
   - `TELEGRAM_TOKEN`（Secret）
   - `LLM_API_KEY`（Secret）
   - `LLM_BASE_URL` = `https://api.deepseek.com`
   - `LLM_MODEL` = `deepseek-chat`
   - `TELEGRAM_WEBHOOK_SECRET`（Secret，自己编随机串）
   - `ALLOWED_CHAT_IDS` = 你的 chat_id（多个用逗号分隔）
5. 绑定 webhook：
   ```bash
   curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://<worker>.workers.dev/webhook&secret_token=<SECRET>"
   ```
6. 可选：绑定 KV namespace 到 `HISTORY` 变量，获得多轮上下文

### 切换回本地模式

```bash
curl "https://api.telegram.org/bot<TOKEN>/deleteWebhook"
```

---

## 安全清单

- ⚠️ **token / key / secret 绝不提交到 git**（`.gitignore` 已排除）
- 云端模式务必设置 `TELEGRAM_WEBHOOK_SECRET`（防伪造请求）
- 用 `ALLOWED_CHAT_IDS` 白名单，避免公开 bot 被陌生人使用消耗你的 API 余额
- bot token 泄露后到 `@BotFather` → `/revoke` 重新生成

## 常见问题

| 现象 | 处理 |
|---|---|
| `getMe` 401 | token 错误或已 revoke |
| 本地模式收不到消息 | 检查是否有 webhook 占用（`getWebhookInfo`），有则 `deleteWebhook` |
| 云端模式 403 | `TELEGRAM_WEBHOOK_SECRET` 与 setWebhook 的 `secret_token` 不一致 |
| 部署报 `10034` | Cloudflare 账号邮箱未验证，去邮箱点验证链接 |
| 模型回复失败 | 检查 `LLM_API_KEY` 余额与 `LLM_BASE_URL` |

## 推荐搭配

- 仓库里的 `telegram_bot.py` 是「单文件、零依赖」版本，方便移植到任何装了 Python 3.8+ 的机器
- 需要 24/7 在线优先用云端模式；需要随时改逻辑用本地模式，改完重启即生效

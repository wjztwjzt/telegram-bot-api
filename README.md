# Telegram Bot API Server 一键部署

采用的官方api的文件，自行本地编译版本，并配置相应参数和service文件保活。

自建 [Telegram Bot API](https://github.com/tdlib/telegram-bot-api) 服务端，支持 Local Bot API 模式（突破官方 API 的 20MB 下载 / 50MB 上传限制）。

本仓库结构：

```
telegram-bot-api            # Linux x86_64 可执行文件
telegram-bot-api.service    # systemd 模板（敏感信息已用占位符替换）
install.sh                  # 一键安装 / 卸载脚本
```

## 前置条件

- Linux 系统，systemd（Debian/Ubuntu/CentOS 均可），root 权限
- 在 <https://my.telegram.org> → API development tools 申请 `api_id` / `api_hash`
- 开放端口，或在前面用 Nginx 反向代理 + HTTPS

## 一键安装

```bash
git clone https://github.com/wjztwjzt/telegram-bot-api.git
cd telegram-bot-api
chmod +x install.sh

sudo ./install.sh --api-id 12345678 --api-hash 0123456789abcdef0123456789abcdef
```

不传参数则交互式询问：

```bash
sudo ./install.sh
```

脚本会完成：

| 步骤 | 内容 |
|------|------|
| 1 | 创建数据目录 `/var/lib/telegram-bot-api`、日志目录 `/var/log` |
| 2 | 复制二进制到 `/usr/local/bin/telegram-bot-api`（权限 755） |
| 3 | 按模板生成 `/etc/systemd/system/telegram-bot-api.service` |
| 4 | `systemctl enable` + 启动，并做健康检查 |

### 常用参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--api-id` | 交互询问 | Telegram api_id |
| `--api-hash` | 交互询问 | Telegram api_hash |
| `--port` | `8082` | `--http-port` 监听端口 |
| `--dir` | `/var/lib/telegram-bot-api` | 数据目录 |
| `--log` | `/var/log/telegram-bot-api.log` | 日志文件 |
| `--verbosity` | `2` | 日志级别 |
| `--extra-args` | 空 | 追加到 ExecStart 的其他参数，如 `--max-webhook-connections=100` |
| `--binary` | 脚本同目录的 `telegram-bot-api` | 指定二进制路径 |
| `--uninstall` | — | 卸载（停服务、删 service 和二进制，保留数据目录） |

首次填写的参数会写入同目录 `install.conf`（权限 600，已在 `.gitignore` 中排除），下次运行直接回车复用。

## 常用命令

```bash
systemctl status  telegram-bot-api
systemctl restart telegram-bot-api
journalctl -u telegram-bot-api -f
tail -f /var/log/telegram-bot-api.log

# 验证
curl 'http://127.0.0.1:8082/bot<BOT_TOKEN>/getMe'
```

## 客户端接入 Local Bot API

以 Python `python-telegram-bot` v20+ 为例：

```python
from telegram.ext import ApplicationBuilder

app = (
    ApplicationBuilder()
    .token("BOT_TOKEN")
    .base_url("http://127.0.0.1:8082/bot")   # 末尾必须带 /bot，不要带 token
    .base_file_url("http://127.0.0.1:8082/file/bot")
    .local_mode(True)
    .build()
)
```

注意：

- Local 模式下 `getUpdates` 不可用，必须使用 webhook：
  `curl "http://127.0.0.1:8082/bot<TOKEN>/setWebhook?url=https://your.domain/webhook/<TOKEN>"`
- 上传文件大小由服务的 `--local` 模式决定，最大 2000MB

## 安全说明

- 仓库中的 `telegram-bot-api.service` 仅为模板，`YOUR_API_ID` / `YOUR_API_HASH` 为占位符。
- 真实的 api-id / api-hash 只存在于服务器上的 `install.conf` 和 `/etc/systemd/system/telegram-bot-api.service`，请勿提交。
- 8082 端口不要直接暴露公网，本地调用或经 Nginx 反代并加 TLS 与访问控制。
- 若 api_id/api_hash 曾泄露，请到 my.telegram.org 重置。

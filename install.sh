#!/usr/bin/env bash
#
# Telegram Bot API Server 一键安装脚本
#
# 用法:
#   sudo ./install.sh                          # 交互式填写 api-id / api-hash
#   sudo ./install.sh --api-id 123 --api-hash abcdef
#   sudo ./install.sh --port 8083 --dir /data/tg-bot-api
#   sudo ./install.sh --uninstall              # 卸载
#
# 安装内容:
#   1. 创建数据目录(默认 /var/lib/telegram-bot-api) 和日志目录
#   2. 复制二进制到 /usr/local/bin/telegram-bot-api
#   3. 根据 telegram-bot-api.service 模板生成 /etc/systemd/system/telegram-bot-api.service
#   4. 注册并启动 systemd 服务
#
# 首次填写过的参数会保存在脚本同目录的 install.conf，下次可直接回车复用。
#
set -euo pipefail

# ---------------- 默认配置 ----------------
BIN_NAME="telegram-bot-api"
INSTALL_BIN="/usr/local/bin/${BIN_NAME}"
SERVICE_NAME="telegram-bot-api.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
API_ID=""
API_HASH=""
HTTP_PORT="8082"
DATA_DIR="/var/lib/telegram-bot-api"
LOG_FILE="/var/log/telegram-bot-api.log"
VERBOSITY="2"
EXTRA_ARGS=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/install.conf"
SRC_BIN="${SCRIPT_DIR}/${BIN_NAME}"
TEMPLATE="${SCRIPT_DIR}/${SERVICE_NAME}"

C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'
info()  { echo "${C_GREEN}[OK]${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}[!]${C_RESET} $*"; }
die()   { echo "${C_RED}[ERR]${C_RESET} $*" >&2; exit 1; }
ask()   { echo "${C_CYAN}[?]${C_RESET} $*"; }

usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

# ---------------- 参数解析 ----------------
DO_UNINSTALL=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --api-id)     API_ID="${2:-}"; shift 2 ;;
        --api-hash)   API_HASH="${2:-}"; shift 2 ;;
        --port)       HTTP_PORT="${2:-}"; shift 2 ;;
        --dir)        DATA_DIR="${2:-}"; shift 2 ;;
        --log)        LOG_FILE="${2:-}"; shift 2 ;;
        --verbosity)  VERBOSITY="${2:-}"; shift 2 ;;
        --extra-args) EXTRA_ARGS="${2:-}"; shift 2 ;;
        --binary)     SRC_BIN="${2:-}"; shift 2 ;;
        --uninstall)  DO_UNINSTALL=1; shift ;;
        -h|--help)    usage ;;
        *) die "未知参数: $1（用 --help 查看用法）" ;;
    esac
done

[[ $EUID -eq 0 ]] || die "请用 root 运行：sudo $0"

# ---------------- 卸载 ----------------
if [[ $DO_UNINSTALL -eq 1 ]]; then
    warn "即将卸载 Telegram Bot API Server"
    if systemctl list-unit-files | grep -q "^${SERVICE_NAME}"; then
        systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
        systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
        info "服务已停止并取消开机自启"
    fi
    [[ -f $SERVICE_PATH ]] && rm -f "$SERVICE_PATH" && info "已删除 $SERVICE_PATH"
    systemctl daemon-reload
    [[ -f $INSTALL_BIN ]] && rm -f "$INSTALL_BIN" && info "已删除 $INSTALL_BIN"
    warn "数据目录保留未删除：$DATA_DIR（如需清理请手动 rm -rf）"
    warn "配置保留：$CONF_FILE"
    info "卸载完成"
    exit 0
fi

# ---------------- 读取上次配置 ----------------
if [[ -f $CONF_FILE ]]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
    info "已加载上次配置：$CONF_FILE"
fi

# ---------------- 校验源文件 ----------------
[[ -f $TEMPLATE ]] || die "找不到 service 模板：$TEMPLATE"
[[ -f $SRC_BIN ]]  || die "找不到二进制：$SRC_BIN
请把 ${BIN_NAME}（Linux amd64 版本）放到本脚本同目录，或用 --binary 指定路径。
官方预编译：https://github.com/tdlib/telegram-bot-api/releases"

# ---------------- 交互式补全 ----------------
if [[ -z $API_ID ]]; then
    ask "请输入 api-id（https://my.telegram.org 获取）:"
    read -r API_ID
fi
if [[ -z $API_HASH ]]; then
    ask "请输入 api-hash:"
    read -r API_HASH
fi
[[ -n $API_ID && -n $API_HASH ]] || die "api-id 和 api-hash 不能为空"

# ---------------- 保存配置 ----------------
umask 077
cat > "$CONF_FILE" <<EOF
# 由 install.sh 自动生成，含敏感信息，请勿提交到 git
API_ID="${API_ID}"
API_HASH="${API_HASH}"
HTTP_PORT="${HTTP_PORT}"
DATA_DIR="${DATA_DIR}"
LOG_FILE="${LOG_FILE}"
VERBOSITY="${VERBOSITY}"
EXTRA_ARGS="${EXTRA_ARGS}"
EOF
umask 022
info "配置已保存到 $CONF_FILE"

# ---------------- 创建目录 ----------------
mkdir -p "$DATA_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
info "已创建数据目录 $DATA_DIR"
info "已创建日志目录 $(dirname "$LOG_FILE")"

# ---------------- 安装二进制 ----------------
install -m 755 "$SRC_BIN" "$INSTALL_BIN"
info "二进制已安装到 $INSTALL_BIN"

# ---------------- 生成 service ----------------
EXEC_LINE="${INSTALL_BIN} --api-id=${API_ID} --api-hash=${API_HASH} --local --dir=${DATA_DIR} --http-port=${HTTP_PORT} --log=${LOG_FILE} --verbosity=${VERBOSITY}"
[[ -n $EXTRA_ARGS ]] && EXEC_LINE="${EXEC_LINE} ${EXTRA_ARGS}"

if ! grep -q '^ExecStart=' "$TEMPLATE"; then
    die "service 模板里没有 ExecStart= 行：$TEMPLATE"
fi
sed "0,/^ExecStart=.*/s|^ExecStart=.*|ExecStart=${EXEC_LINE}|" "$TEMPLATE" > "$SERVICE_PATH"
chmod 644 "$SERVICE_PATH"
info "已生成 $SERVICE_PATH"

# ---------------- 启动服务 ----------------
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1
systemctl restart "${SERVICE_NAME}"
sleep 2

if systemctl is-active --quiet "${SERVICE_NAME}"; then
    info "服务已启动"
else
    warn "服务启动失败，最近日志："
    journalctl -u "${SERVICE_NAME}" -n 20 --no-pager || true
    die "请检查日志：tail -f ${LOG_FILE}"
fi

# ---------------- 完成 ----------------
HOST="http://127.0.0.1:${HTTP_PORT}"
echo
echo "${C_GREEN}========== 安装完成 ==========${C_RESET}"
echo "  API 地址 : ${HOST}"
echo "  数据目录 : ${DATA_DIR}"
echo "  日志文件 : ${LOG_FILE}"
echo
echo "  systemctl status  ${SERVICE_NAME}"
echo "  systemctl restart ${SERVICE_NAME}"
echo "  journalctl -u ${SERVICE_NAME} -f"
echo
echo "  验证: curl '${HOST}/bot<TOKEN>/getMe'"
echo "${C_GREEN}==============================${C_RESET}"

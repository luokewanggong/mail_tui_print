#!/bin/bash
# MailTUI 远程内存运行版｜兼容 bash <(wget)
SCRIPT_VER="mailtui‑remote‑v2.3‑oldui"

BASE_DIR="/opt/mailtui"
mkdir -p "${BASE_DIR}"
cd "${BASE_DIR}" || exit 1

CONFIG_FILE="${BASE_DIR}/mail_config.conf"
LOG_FILE="${BASE_DIR}/mail_tui.log"
SAVE_DIR="${BASE_DIR}/mail_download"
ATTACH_DIR="${SAVE_DIR}/attachments"

mkdir -p "${SAVE_DIR}" "${ATTACH_DIR}"

log(){
    echo "[$(date '+%Y‑%m‑%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

pause(){
    echo ""
    read -n1 -p "按任意键返回菜单..."
}

clear_menu(){
    clear
}

check_printer(){
    log "ℹ️跳过打印机检测(未安装cups)"
    return 1
}

extract_attachments(){
    local eml_file="$1"
    if ! command -v munpack &>/dev/null;then
        log "⚠️未检测到munpack，跳过附件解析，请安装 mpack"
        return 1
    fi
    [ ! -f "${eml_file}" ] && return 1
    local tmp_out
    tmp_out=$(munpack -C "${ATTACH_DIR}" "${eml_file}" 2>&1)
    if echo "${tmp_out}" | grep -q "writing";then
        log "📎附件已提取: ${eml_file}"
    else
        log "ℹ️该邮件无附件: ${eml_file}"
    fi
}

download_mail_imap(){
    mkdir -p "${SAVE_DIR}" "${ATTACH_DIR}"
    log "开始执行IMAP邮件下载任务"
    if [ ! -f "${CONFIG_FILE}" ];then
        log "ERROR:配置文件不存在，请先配置邮箱"
        return 1
    fi
    source "${CONFIG_FILE}"
    UIDS=$(curl -s --ssl-reqd \
        "imap://${IMAP_SERVER}:${IMAP_PORT}/INBOX" \
        --user "${EMAIL_ACCOUNT}:${AUTH_CODE}" \
        -X "SEARCH UNSEEN")

    MAIL_UIDS=$(echo "$UIDS" | grep "^* SEARCH" | sed 's/\* SEARCH //')
    if [[ -z "${MAIL_UIDS}" ]]; then
        log "无未读邮件"
        return 0
    fi
    for uid in ${MAIL_UIDS}; do
        eml_file="${SAVE_DIR}/mail_${uid}.eml"
        curl -s --ssl-reqd \
            "imap://${IMAP_SERVER}:${IMAP_PORT}/INBOX;UID=${uid}" \
            --user "${EMAIL_ACCOUNT}:${AUTH_CODE}" > "${eml_file}"
        if [[ -s "${eml_file}" ]]; then
            log "✅邮件下载成功 ${eml_file}"
            extract_attachments "${eml_file}"
        else
            rm -f "${eml_file}"
            log "⚠️邮件${uid}下载为空，丢弃"
        fi
    done
}

save_config(){
cat > "${CONFIG_FILE}" <<CONF
MAIL_NAME="${MAIL_NAME}"
EMAIL_ACCOUNT="${EMAIL_ACCOUNT}"
IMAP_SERVER="${IMAP_SERVER}"
IMAP_PORT="${IMAP_PORT}"
SMTP_SERVER="${SMTP_SERVER}"
SMTP_PORT="${SMTP_PORT}"
AUTH_CODE="${AUTH_CODE}"
POLL_INTERVAL="${POLL_INTERVAL}"
SAVE_DIR="${SAVE_DIR}"
ATTACH_DIR="${ATTACH_DIR}"
CONF
log "配置已保存到${CONFIG_FILE}"
}

load_config(){
    if [ -f "${CONFIG_FILE}" ];then
        source "${CONFIG_FILE}"
    else
        MAIL_NAME=""
        EMAIL_ACCOUNT=""
        IMAP_SERVER=""
        IMAP_PORT=""
        SMTP_SERVER=""
        SMTP_PORT=""
        AUTH_CODE=""
        POLL_INTERVAL=60
    fi
    mkdir -p "${SAVE_DIR}" "${ATTACH_DIR}"
}

ui_config_mail(){
    clear_menu
    echo "================邮箱配置================"
    read -p "邮箱类型名称(如QQ邮箱): " MAIL_NAME
    read -p "完整邮箱账号: " EMAIL_ACCOUNT
    read -p "IMAP服务器: " IMAP_SERVER
    read -p "IMAP端口(一般993): " IMAP_PORT
    read -p "SMTP服务器: " SMTP_SERVER
    read -p "SMTP端口(一般465/587): " SMTP_PORT
    read -p "授权码: " AUTH_CODE
    read -p "轮询间隔(秒): " POLL_INTERVAL
    save_config
    echo "配置保存完成！"
    pause
}

ui_show_config(){
    clear_menu
    echo "================当前配置================"
    echo "邮箱类型:      ${MAIL_NAME}"
    echo "账号:          ${EMAIL_ACCOUNT}"
    echo "IMAP服务器:    ${IMAP_SERVER}"
    echo "IMAP端口:      ${IMAP_PORT}"
    echo "SMTP服务器:    ${SMTP_SERVER}"
    echo "SMTP端口:      ${SMTP_PORT}"
    echo "授权码:        ${AUTH_CODE:0:8}******"
    echo "轮询间隔(秒):  ${POLL_INTERVAL}"
    echo "邮件目录:      ${SAVE_DIR}"
    echo "附件目录:      ${ATTACH_DIR}"
    pause
}

ui_show_files(){
    clear_menu
    echo "============已下载邮件============"
    ls -lh "${SAVE_DIR}"
    echo ""
    echo "------------附件目录------------"
    ls -lh "${ATTACH_DIR}"
    pause
}

ui_view_log(){
    clear_menu
    echo "============运行日志============"
    if [ ! -f "${LOG_FILE}" ];then
        echo "暂无日志"
    else
        tail -n 80 "${LOG_FILE}"
    fi
    pause
}

daemon_pid="${BASE_DIR}/mail_daemon.pid"
start_daemon(){
    stop_daemon
    nohup bash -c "
    while true;do
        check_printer
        download_mail_imap
        sleep ${POLL_INTERVAL}
    done
    " >/dev/null 2>&1 &
    echo $! > "${daemon_pid}"
    log "后台轮询已启动 PID=$(cat ${daemon_pid})"
    echo "后台轮询已启动"
    pause
}

stop_daemon(){
    if [ -f "${daemon_pid}" ];then
        PID=$(cat "${daemon_pid}")
        kill "${PID}" 2>/dev/null
        rm -f "${daemon_pid}"
        log "后台轮询已停止"
        echo "后台轮询已停止"
    fi
}

is_daemon_run(){
    if [ -f "${daemon_pid}" ];then
        PID=$(cat "${daemon_pid}")
        if ps -p "${PID}" >/dev/null;then
            return 0
        fi
    fi
    return 1
}

main_menu(){
    while true;do
        clear_menu
        echo "==== MailTUI 邮件附件下载工具 ===="
        if is_daemon_run;then
            echo " 🟢后台轮询:运行中"
        else
            echo " 🔴后台轮询:已停止"
        fi
        echo " 1) 邮箱参数配置"
        echo " 2) 查看当前配置"
        echo " 3) 浏览邮件&附件文件"
        echo " 4) 查看运行日志"
        echo " 5) 手动执行一次邮件下载"
        echo " 6) 启动后台轮询"
        echo " 7) 停止后台轮询"
        echo " 0) 退出程序"
        echo "=================================="
        read -p "请输入选择 [0‑7]: " opt
        case ${opt} in
            1) ui_config_mail ;;
            2) ui_show_config ;;
            3) ui_show_files ;;
            4) ui_view_log ;;
            5) download_mail_imap;echo "手动下载执行完成";pause ;;
            6) start_daemon ;;
            7) stop_daemon ;;
            0) stop_daemon;echo "退出";exit 0 ;;
            *) echo "无效选项";pause;;
        esac
    done
}

load_config
main_menu

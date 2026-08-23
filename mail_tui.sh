#!/bin/bash
set -uo pipefail

# ================= 全局变量与文件路径 =================
CONFIG_FILE="./mail_config.conf"
LOG_FILE="./mail_tui.log"
SAVE_DIR="./mail_download"
ATTACH_DIR="${SAVE_DIR}/attachments"

# 内置邮箱预设 格式:"名称|imap服务器|imap端口|smtp服务器|smtp端口"
MAIL_PRESET=(
"QQ邮箱|imap.qq.com|993|smtp.qq.com|465"
"163网易个人邮箱|imap.163.com|993|smtp.163.com|465"
"126邮箱|imap.126.com|993|smtp.126.com|465"
"新浪邮箱|imap.sina.com|993|smtp.sina.com|465"
"腾讯企业邮箱(Exmail/企业微信邮)|imap.exmail.qq.com|993|smtp.exmail.qq.com|465"
"网易灵犀企业邮箱|imap.qiye.163.com|993|smtp.qiye.163.com|465"
"阿里云企业邮箱|imap.qiye.aliyun.com|993|smtp.qiye.aliyun.com|465"
"263企业邮箱|imap.263.net|993|smtp.263.net|465"
"Coremail盈世企业邮箱|imap.coremail.cn|993|smtp.coremail.cn|465"
"Outlook个人版|imap-mail.outlook.com|993|smtp.office365.com|587"
"Microsoft365企业版|imap-mail.outlook.com|993|smtp.office365.com|587"
"Gmail谷歌邮箱|imap.gmail.com|993|smtp.gmail.com|465"
"自定义额外企业内部邮箱|||"
)

# 运行时变量
MAIL_INDEX=""
MAIL_NAME=""
EMAIL_ACCOUNT=""
IMAP_SERVER=""
IMAP_PORT=""
SMTP_SERVER=""
SMTP_PORT=""
AUTH_CODE=""
POLL_INTERVAL=60

# =================工具函数=================
log(){
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

pause(){
    echo ""
    read -n1 -p "按任意键返回菜单..."
}

clear_menu(){
    clear
}

# 保存配置文件
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

# 加载配置
load_config(){
    if [ -f "${CONFIG_FILE}" ];then
        source "${CONFIG_FILE}"
    fi
    mkdir -p "${SAVE_DIR}"
    mkdir -p "${ATTACH_DIR}"
}

#检测打印机
check_printer(){
    if ! command -v lpstat &>/dev/null; then
        log "警告：未找到lpstat，请安装cups"
        return 1
    fi
    if lpstat -p 2>/dev/null | grep -qi "printer"; then
        log "🖨️检测到打印机(USB/网络打印机)已连接"
        return 0
    else
        log "ℹ️未检测到打印机设备"
        return 1
    fi
}

#自动提取邮件附件
extract_attachments(){
    local eml_file="$1"
    if ! command -v munpack &>/dev/null;then
        log "⚠️未检测到munpack，跳过附件解析，请安装 apt install mpack"
        return 1
    fi
    if [ ! -f "${eml_file}" ];then
        return 1
    fi
    local tmp_out
    tmp_out=$(munpack -C "${ATTACH_DIR}" "${eml_file}" 2>&1)
    if echo "${tmp_out}" | grep -q "writing";then
        log "📎附件已提取: ${eml_file}"
    else
        log "ℹ️该邮件无附件: ${eml_file}"
    fi
}

#IMAP下载未读邮件
download_mail_imap(){
    mkdir -p "${SAVE_DIR}"
    mkdir -p "${ATTACH_DIR}"
    log "开始执行IMAP邮件下载任务"
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
        [[ -z "${uid}" ]] && continue
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

#后台轮询进程
start_poll_daemon(){
    stop_poll_daemon
    nohup bash -c "
    while true;do
        check_printer
        download_mail_imap
        sleep ${POLL_INTERVAL}
    done
    " >/dev/null 2>&1 &
    echo $! > ./mail_daemon.pid
    log "后台轮询已启动，间隔${POLL_INTERVAL}秒,PID=$(cat ./mail_daemon.pid)"
}

stop_poll_daemon(){
    if [ -f ./mail_daemon.pid ];then
        PID=$(cat ./mail_daemon.pid)
        kill "${PID}" 2>/dev/null
        rm -f ./mail_daemon.pid
        log "后台轮询进程已停止"
    fi
}

is_daemon_running(){
    if [ -f ./mail_daemon.pid ];then
        PID=$(cat ./mail_daemon.pid)
        if ps -p "${PID}" >/dev/null;then
            return 0
        fi
    fi
    return 1
}

# =====================界面1：选择邮箱预设====================
ui_select_mail_preset(){
    clear_menu
    echo "====================[1.选择邮箱类型]===================="
    local i=1
    for item in "${MAIL_PRESET[@]}";do
        name=$(echo "${item}" | cut -d'|' -f1)
        echo " $i) ${name}"
        ((i++))
    done
    echo "========================================================"
    read -p "请输入序号选择邮箱类型：" sel
    MAIL_INDEX=$((sel-1))
    sel_line=${MAIL_PRESET[${MAIL_INDEX}]}
    MAIL_NAME=$(echo "${sel_line}" | cut -d'|' -f1)
    IMAP_SERVER=$(echo "${sel_line}" | cut -d'|' -f2)
    IMAP_PORT=$(echo "${sel_line}" | cut -d'|' -f3)
    SMTP_SERVER=$(echo "${sel_line}" | cut -d'|' -f4)
    SMTP_PORT=$(echo "${sel_line}" | cut -d'|' -f5)
}

# =====================界面2：输入邮箱账号====================
ui_input_email_account(){
    clear_menu
    echo "====================[2.输入邮箱地址]===================="
    read -p "邮箱地址[${EMAIL_ACCOUNT}]: " tmp
    if [[ -n "${tmp}" ]];then
        EMAIL_ACCOUNT="${tmp}"
    fi
}

# =====================界面3：IMAP服务器====================
ui_input_imap_server(){
    clear_menu
    echo "====================[3.输入IMAP服务器地址]===================="
    read -p "IMAP服务器 [${IMAP_SERVER}]: " tmp
    if [[ -n "${tmp}" ]];then
        IMAP_SERVER="${tmp}"
    fi
}

# =====================界面4：IMAP端口====================
ui_input_imap_port(){
    clear_menu
    echo "====================[4.输入IMAP端口]===================="
    read -p "IMAP端口 [${IMAP_PORT}]: " tmp
    if [[ -n "${tmp}" ]];then
        IMAP_PORT="${tmp}"
    fi
}

# =====================界面5：SMTP服务器====================
ui_input_smtp_server(){
    clear_menu
    echo "====================[5.输入SMTP服务器地址]===================="
    read -p "SMTP服务器 [${SMTP_SERVER}]: " tmp
    if [[ -n "${tmp}" ]];then
        SMTP_SERVER="${tmp}"
    fi
}

# =====================界面6：SMTP端口====================
ui_input_smtp_port(){
    clear_menu
    echo "====================[6.输入SMTP端口]===================="
    read -p "SMTP端口 [${SMTP_PORT}]: " tmp
    if [[ -n "${tmp}" ]];then
        SMTP_PORT="${tmp}"
    fi
}

# =====================界面7：授权码====================
ui_input_authcode(){
    clear_menu
    echo "====================[7.输入邮箱授权码]===================="
    read -p "授权码 [${AUTH_CODE:0:8}******]: " tmp
    if [[ -n "${tmp}" ]];then
        AUTH_CODE="${tmp}"
    fi
}

# =====================界面8：显示全部配置====================
ui_show_all_config(){
    clear_menu
    echo "====================[8.全部邮箱配置信息]===================="
    echo "邮箱类型:      ${MAIL_NAME}"
    echo "邮箱账号:      ${EMAIL_ACCOUNT}"
    echo "IMAP服务器:    ${IMAP_SERVER}"
    echo "IMAP端口:      ${IMAP_PORT}"
    echo "SMTP服务器:    ${SMTP_SERVER}"
    echo "SMTP端口:      ${SMTP_PORT}"
    echo "授权码:        ${AUTH_CODE:0:8}******"
    echo "轮询间隔(秒):  ${POLL_INTERVAL}"
    echo "邮件下载目录:  ${SAVE_DIR}"
    echo "附件保存目录:  ${ATTACH_DIR}"
    if is_daemon_running;then
        echo "后台轮询状态: ✅正在运行"
    else
        echo "后台轮询状态: ❌已停止"
    fi
    echo "============================================================"
    pause
}

# =====================界面9：设置查询间隔====================
ui_set_poll_interval(){
    clear_menu
    echo "====================[9.设置邮箱查询间隔(秒)]===================="
    opt_arr=(5 10 15 20 25 30 35 40 45 50 55 60 120 300 1800 3600 10000 30000 "自定义秒数")
    local i=1
    for v in "${opt_arr[@]}";do
        echo " $i) $v 秒"
        ((i++))
    done
    read -p "请选择序号: " sel
    idx=$((sel-1))
    sel_val=${opt_arr[${idx}]}
    if [[ "${sel_val}" == "自定义秒数" ]];then
        read -p "输入自定义轮询秒数: " custom_sec
        POLL_INTERVAL="${custom_sec}"
    else
        POLL_INTERVAL="${sel_val}"
    fi
    echo "已设置轮询间隔: ${POLL_INTERVAL} 秒"
    pause
}

# =====================界面10：浏览下载文件====================
ui_show_download_files(){
    clear_menu
    echo "====================[10.已下载邮件文件]===================="
    mkdir -p "${SAVE_DIR}"
    if [ -z "$(ls -A "${SAVE_DIR}" 2>/dev/null)" ];then
        echo "下载目录为空，暂无邮件"
    else
        ls -lh "${SAVE_DIR}"
    fi
    echo ""
    echo "----附件目录 ${ATTACH_DIR} ----"
    if [ -z "$(ls -A "${ATTACH_DIR}" 2>/dev/null)" ];then
        echo "暂无附件"
    else
        ls -lh "${ATTACH_DIR}"
    fi
    pause
}

# =====================界面11：配置下载目录====================
ui_set_save_dir(){
    clear_menu
    echo "====================[11.配置邮件下载地址]===================="
    read -p "下载目录 [${SAVE_DIR}]: " tmp
    if [[ -n "${tmp}" ]];then
        SAVE_DIR="${tmp}"
        ATTACH_DIR="${SAVE_DIR}/attachments"
    fi
    mkdir -p "${SAVE_DIR}"
    mkdir -p "${ATTACH_DIR}"
    echo "邮件目录: ${SAVE_DIR}"
    echo "附件目录: ${ATTACH_DIR}"
    pause
}

# =====================界面12：查看运行日志====================
ui_view_log(){
    clear_menu
    echo "====================[12.运行日志]===================="
    if [ ! -f "${LOG_FILE}" ];then
        echo "暂无日志"
    else
        tail -n 80 "${LOG_FILE}"
    fi
    pause
}

# ============完整向导，一次性走完1‑12配置界面============
ui_full_wizard(){
    ui_select_mail_preset
    ui_input_email_account
    ui_input_imap_server
    ui_input_imap_port
    ui_input_smtp_server
    ui_input_smtp_port
    ui_input_authcode
    ui_show_all_config
    ui_set_poll_interval
    ui_set_save_dir
    save_config
    echo "配置向导完成，已保存配置！"
    pause
}

# =================主菜单================
main_menu(){
while true;do
clear_menu
echo "=================Linux TUI邮件客户端(自动下载附件版)================="
if is_daemon_running;then
    echo " 🟢后台邮件轮询服务正在运行"
else
    echo " 🔴后台邮件轮询服务已停止"
fi
echo " 1) 完整配置向导(界面1‑11)"
echo " 2) 查看当前全部配置(界面8)"
echo " 3) 设置轮询查询间隔(界面9)"
echo " 4) 浏览已下载邮件&附件(界面10)"
echo " 5) 修改邮件下载目录(界面11)"
echo " 6) 查看运行日志(界面12)"
echo " 7) 立即手动执行一次邮件下载"
echo " 8) 启动后台自动轮询下载"
echo " 9) 停止后台自动轮询下载"
echo " 0) 退出程序"
echo "======================================================"
read -p "请选择操作[0‑9]: " op
case $op in
1) ui_full_wizard ;;
2) ui_show_all_config ;;
3) ui_set_poll_interval; save_config ;;
4) ui_show_download_files ;;
5) ui_set_save_dir; save_config ;;
6) ui_view_log ;;
7) check_printer;download_mail_imap;echo "手动下载执行完毕";pause ;;
8) start_poll_daemon ;;
9) stop_poll_daemon ;;
0) stop_poll_daemon;echo "退出程序";exit 0 ;;
*) echo "无效选项";pause;;
esac
done
}

#程序入口
load_config
main_menu

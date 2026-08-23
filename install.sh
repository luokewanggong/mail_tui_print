#!/bin/bash
SCRIPT_VER="mail_runner-v1.0"
args="$@"
BASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
cd "${BASE_DIR}"||exit 1

MAIN_SCRIPT="${BASE_DIR}/mail_tui.sh"

if [ ! -f "${MAIN_SCRIPT}" ];then
    echo "[ERROR] 主程序 mail_tui.sh 不存在"
    exit 1
fi

echo "==== MailTUI 一键启动器 ${SCRIPT_VER} ===="
echo "工作目录: ${BASE_DIR}"


# 启动主脚本
exec bash "${MAIN_SCRIPT}" ${args}

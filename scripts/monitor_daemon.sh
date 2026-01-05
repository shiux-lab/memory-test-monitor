#!/bin/bash

# ===============================================
# Reboot 专用监控脚本 (V2.1 - 适配新架构)
# ===============================================

BACKEND_URL="{{BACKEND_URL}}"
SERVER_ID="{{SERVER_ID}}"

# --- 1. 统一日志目录 (与 Memtest 保持一致) ---
WORK_DIR="/root/Reboot"
LOG_DIR="/root/Test_Logs/Reboot"
mkdir -p "$LOG_DIR"

FLAG_FILE="$WORK_DIR/.chain_monitor_status"
LOOP_FILE="$WORK_DIR/reboot_all_times"
LOCAL_LOG="$LOG_DIR/reboot_detail.log"
RUNNING_LOCK="$WORK_DIR/.is_reboot_running"
THIS_SCRIPT="$WORK_DIR/monitor_daemon.sh"
AUTO_SCRIPT="$WORK_DIR/auto_cold_warm_stress_chain.sh"
RC_LOC="/etc/rc.d/rc.local"

# --- 2. 日志轮转 ---
rotate_log() {
    local max_size=$((5 * 1024 * 1024)) # 5MB
    if [ -f "$LOCAL_LOG" ]; then
        local size=$(stat -c%s "$LOCAL_LOG")
        if [ $size -ge $max_size ]; then
            mv "$LOCAL_LOG" "$LOCAL_LOG.$(date +%Y%m%d_%H%M%S).bak"
            ls -t "$LOG_DIR"/*.bak | tail -n +6 | xargs -r rm
        fi
    fi
}

log_to_local() {
    local msg=$1
    local time_now=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$time_now] $msg" >> "$LOCAL_LOG"
    rotate_log
}

# --- 3. 开机自启 ---
ensure_startup() {
    local cmd="bash $THIS_SCRIPT > /dev/null 2>&1 &"
    chmod +x "$RC_LOC"
    if ! grep -q "$THIS_SCRIPT" "$RC_LOC"; then
        if grep -q "exit 0" "$RC_LOC"; then
            sed -i "/exit 0/i $cmd" "$RC_LOC"
        else
            echo "$cmd" >> "$RC_LOC"
        fi
    fi
}
ensure_startup

# --- 4. 看门狗 ---
check_and_revive() {
    if [ ! -f "$RUNNING_LOCK" ]; then return; fi
    if [ -f "$FLAG_FILE" ]; then
        STATUS=$(cat "$FLAG_FILE")
        if [[ "$STATUS" == *"完成"* ]]; then return; fi
    fi
    if ! pgrep -f "$AUTO_SCRIPT" > /dev/null; then
        log_to_local "检测到 Auto 脚本未运行，正在拉起..."
        chmod +x "$AUTO_SCRIPT"
        nohup bash "$AUTO_SCRIPT" > /dev/null 2>&1 &
    fi
}

# --- 5. 上报后端 (核心：带上 task_type) ---
report_backend() {
    local phase=$1
    local loop=$2
    local status=$3
    phase=$(echo "$phase" | tr -d '\n')
    loop=$(echo "$loop" | tr -d '\n')
    
    # 显式声明 task_type="reboot"
    JSON_DATA="{\"server_id\": \"$SERVER_ID\", \"task_type\": \"reboot\", \"phase\": \"$phase\", \"loop\": \"$loop\", \"status\": \"$status\"}"
    
    curl --noproxy "*" -s -X POST "$BACKEND_URL" \
         -H "Content-Type: application/json" \
         -d "$JSON_DATA" --connect-timeout 5 -m 10 > /dev/null 2>&1
}

echo "--- Reboot Monitor Started ---" >> "$LOCAL_LOG"
touch "$RUNNING_LOCK"

while true; do
    # 检查锁文件，如果没有了（说明被停止了），脚本退出
    if [ ! -f "$RUNNING_LOCK" ]; then
        log_to_local "检测到停止信号，退出。"
        exit 0
    fi

    check_and_revive

    curr_loop="0"
    if [ -f "$LOOP_FILE" ]; then 
        val=$(cat "$LOOP_FILE")
        if [[ "$val" =~ ^[0-9]+$ ]]; then curr_loop=$val; fi
    fi
    
    curr_phase="等待测试启动..."
    if [ -f "$FLAG_FILE" ]; then curr_phase=$(cat "$FLAG_FILE"); fi

    log_to_local "[Loop:$curr_loop] $curr_phase"
    report_backend "$curr_phase" "$curr_loop" "Running"

    sleep 30
done
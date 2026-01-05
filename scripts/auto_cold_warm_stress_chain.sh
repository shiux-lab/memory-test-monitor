#!/bin/bash

# ===============================================
# 自动化测试链 - 压力注入增强版
# ===============================================

BACKEND_URL="{{BACKEND_URL}}"
SERVER_ID="{{SERVER_ID}}"
SOURCE_SCRIPT_NAME="Cycle_OSReboot_V2.2.3.sh"
THIS_SCRIPT_NAME="auto_cold_warm_stress_chain.sh"

CMD_PHASE_1="-mlc -i 3"
CMD_PHASE_2="-mc -i 3"
CMD_PHASE_3="-m -c -i 12"

# 压力测试命令 (注意：增加了 cd WORK_DIR 确保日志生成在正确位置)
# -s 3600 代表跑 1 小时
RAW_STRESS_CMD="stressapptest -l stressapptest.log --remote_numa -W -C 128 -m 128 -s 3600 --reserve_memory"

WORK_DIR="/root/Reboot"
FLAG_FILE="$WORK_DIR/.chain_monitor_status"
MONITOR_SCRIPT="monitor_daemon.sh"
RC_LOC="/etc/rc.d/rc.local"

# 调试日志
DEBUG_LOG="$WORK_DIR/auto_debug.log"
CYCLE_CRASH_LOG="$WORK_DIR/cycle_crash.log"
exec 1>>"$DEBUG_LOG" 2>&1

echo "========================================"
echo "[$(date)] Auto Script 启动"
echo "========================================"

# ===============================================
# 1. 环境准备
# ===============================================
prepare_environment() {
    touch "$WORK_DIR/add_white_black.sh"
    chmod +x "$WORK_DIR/add_white_black.sh"
    touch "$WORK_DIR/check_server_zijie_h3c.sh"
    chmod +x "$WORK_DIR/check_server_zijie_h3c.sh"
    
    if ! pgrep -f "$WORK_DIR/$MONITOR_SCRIPT" > /dev/null; then
        echo "[Main] 启动监控守护进程..."
        chmod +x "$WORK_DIR/$MONITOR_SCRIPT"
        nohup bash "$WORK_DIR/$MONITOR_SCRIPT" > /dev/null 2>&1 &
        sleep 1
    fi
}

# ===============================================
# 【核心新增】rc.local 注入管理
# ===============================================

# 注入压力命令到 rc.local
inject_stress_to_rc() {
    echo "[Inject] 正在检查是否需要注入压力测试命令..."
    
    # 构造完整的命令行，确保先进入目录再跑压力
    # 这样 log 文件才会生成在 /root/Reboot 下
    local FULL_CMD="cd $WORK_DIR && $RAW_STRESS_CMD"
    
    # 检查 rc.local 里是否已经有了
    if grep -q "stressapptest" "$RC_LOC"; then
        echo "[Inject] 压力命令已存在，跳过。"
    else
        echo "[Inject] 正在将压力命令插入 rc.local..."
        # 备份一下
        cp "$RC_LOC" "${RC_LOC}.bak_before_stress"
        
        # 策略：插入到 monitor 之后，exit 0 之前
        # 也可以直接追加到文件末尾，但必须在 Cycle 脚本之前
        # Cycle 脚本通常是追加到最后的，所以我们用 sed 插到文件中间比较稳
        
        # 如果有 touch /var/lock... 这一行（CentOS/RedHat标准），插在它后面
        if grep -q "touch /var/lock/subsys/local" "$RC_LOC"; then
            sed -i "\|touch /var/lock/subsys/local|a $FULL_CMD" "$RC_LOC"
        else
            # 如果没有标准行，就插在第 2 行（#!/bin/bash 之后）
            sed -i "2i $FULL_CMD" "$RC_LOC"
        fi
        
        echo "[Inject] 注入完成。"
        chmod +x "$RC_LOC"
    fi
}

# 清洗压力命令
clean_stress_from_rc() {
    echo "[Clean] 正在清理 rc.local 中的压力命令..."
    if grep -q "stressapptest" "$RC_LOC"; then
        # 删除包含 stressapptest 的行
        sed -i '/stressapptest/d' "$RC_LOC"
        echo "[Clean] 清理完成。"
    else
        echo "[Clean] 未发现残留命令，无需清理。"
    fi
}

# ===============================================
# 2. 执行逻辑
# ===============================================
run_phase_logic() {
    local phase_name=$1
    local cmd_args=$2
    local is_stress_phase=$3 # 新增参数：是否是压力阶段
    
    echo "$phase_name" > "$FLAG_FILE"
    echo "[Auto] 准备执行: $phase_name"
    
    # --- 如果是压力阶段，先注入命令 ---
    if [ "$is_stress_phase" == "yes" ]; then
        inject_stress_to_rc
    fi

    CYCLE_PID=$(pgrep -f "$SOURCE_SCRIPT_NAME" | grep -v "grep")
    
    if [ -n "$CYCLE_PID" ]; then
        echo "[Auto] 发现 Cycle (PID $CYCLE_PID) 正在运行，附身监听..."
        tail --pid=$CYCLE_PID -f /dev/null
    else
        echo "[Auto] 启动新任务: $cmd_args"
        
        TARGET_SCRIPT="$WORK_DIR/$SOURCE_SCRIPT_NAME"
        
        if [ ! -f "$TARGET_SCRIPT" ]; then
            echo "[Auto] 致命错误: 找不到脚本文件: $TARGET_SCRIPT"
            exit 1
        fi
        
        # 使用绝对路径 + bash 启动
        yes | bash "$TARGET_SCRIPT" $cmd_args > "$CYCLE_CRASH_LOG" 2>&1
        
        EXIT_CODE=$?
        echo "[Auto] Cycle 脚本退出，返回码: $EXIT_CODE"
        
        if [ $EXIT_CODE -ne 0 ]; then
            echo "[Auto] 警告: Cycle 脚本非正常退出！"
            sleep 10
        fi
    fi
}

# ===============================================
# 3. 进度扫描
# ===============================================
get_real_stage_count() {
    TOTAL_STOPS=$(find "$WORK_DIR" -name "reboot_all_log" -not -path "*/Trash/*" -exec cat {} + 2>/dev/null | grep -c "stop reboot automaticly")
    return $TOTAL_STOPS
}

# ===============================================
# 主逻辑
# ===============================================

if [ ! -f "$WORK_DIR/$SOURCE_SCRIPT_NAME" ]; then
    echo "错误:测试脚本缺失"
    exit 1
fi

prepare_environment

while true; do
    get_real_stage_count
    CURRENT_STAGE=$?
    
    echo "[Auto] [$(date)] 扫描完成，当前完成阶段数: $CURRENT_STAGE"
    
    if [ $CURRENT_STAGE -eq 0 ]; then
        # 阶段1: 冷重启 (不注入压力)
        run_phase_logic "阶段1: 冷重启 (Cold)" "$CMD_PHASE_1" "no"
        
    elif [ $CURRENT_STAGE -eq 1 ]; then
        # 阶段2: 热重启 (不注入压力)
        run_phase_logic "阶段2: 热重启 (Warm)" "$CMD_PHASE_2" "no"
        
    elif [ $CURRENT_STAGE -eq 2 ]; then
        # 阶段3: 压力测试 (【注入压力】)
        # 注意：这里传了 "yes"
        run_phase_logic "阶段3: 压力测试 (Stress)" "$CMD_PHASE_3" "yes"
        
    elif [ $CURRENT_STAGE -ge 3 ]; then
        echo "全部完成" > "$FLAG_FILE"
        echo "[Auto] 所有测试完成。"
        
        # --- 完工时的清理工作 ---
        clean_stress_from_rc
        
        exit 0
    fi
    
    sleep 5
done
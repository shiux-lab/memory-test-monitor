import os
from config import *
from utils import get_ssh_client, run_ssh_command
from models import ServerSchema
from logger import logger

# --- 1. 部署逻辑 (保持 V2.0) ---
def deploy_memtest_env(server: ServerSchema):
    try:
        logger.info(f"[{server.server_id}] 开始部署 Memtest 环境...")
        script_src = os.path.join(LOCAL_SCRIPT_DIR, SCRIPT_MEMTEST_NAME)
        tar_src = os.path.join(LOCAL_SCRIPT_DIR, FILE_MEMTEST_TAR)
        
        if not os.path.exists(script_src) or not os.path.exists(tar_src):
            return False, "本地 Memtest 文件缺失"

        ssh = get_ssh_client(server.os_ip, server.ssh_user, server.ssh_password)
        
        # 预处理：创建目录 (包含统一日志目录)
        setup_cmd = f"""
            rm -rf {REMOTE_MEMTEST_DIR}
            mkdir -p {REMOTE_MEMTEST_DIR}
            mkdir -p /root/Test_Logs/Memtest
            dmesg -c >/dev/null
        """
        ssh.exec_command(setup_cmd)
        
        sftp = ssh.open_sftp()
        sftp.put(script_src, f"{REMOTE_MEMTEST_DIR}/{SCRIPT_MEMTEST_NAME}")
        sftp.put(tar_src, f"{REMOTE_MEMTEST_DIR}/{FILE_MEMTEST_TAR}")
        sftp.close()

        cmd_install = f"""
            cd {REMOTE_MEMTEST_DIR} || exit 1
            tar -zxvf {FILE_MEMTEST_TAR}
            DIR_NAME=$(tar -tf {FILE_MEMTEST_TAR} | head -1 | cut -f1 -d"/")
            if [ -d "$DIR_NAME" ]; then
                cd "$DIR_NAME"
                if [ ! -f "memtester" ]; then make && make install; fi
                cd ..
            fi
            chmod +x {SCRIPT_MEMTEST_NAME}
        """
        stdin, stdout, stderr = ssh.exec_command(cmd_install)
        if stdout.channel.recv_exit_status() != 0:
            ssh.close()
            return False, f"编译失败: {stderr.read().decode()}"
            
        ssh.close()
        return True, "Memtest 环境部署成功"
    except Exception as e:
        return False, f"部署异常: {str(e)}"

# --- 2. 启动逻辑 (V2.0 监控) ---
async def start_memtest(server: ServerSchema, runtime: str):
    logger.info(f"[{server.server_id}] 启动 Memtest (Runtime={runtime})")

    kill_old_cmd = f"""
        safe_kill() {{
            local name=$1
            PIDS=$(pgrep -f "$name" | grep -v "$$" | grep -v "grep")
            if [ -n "$PIDS" ]; then echo "$PIDS" | xargs -r kill -9; fi
        }}
        safe_kill "memtest_daemon.sh"
        safe_kill "{SCRIPT_MEMTEST_NAME}"
        killall -9 memtester 2>/dev/null || true
    """
    run_ssh_command(server.os_ip, server.ssh_user, server.ssh_password, kill_old_cmd)

    monitor_script = f"""#!/bin/bash
SERVER_ID="{server.server_id}"
URL="http://{BACKEND_IP_PORT}/report/webhook"

# 日志写到 Test_Logs (仅供排查，不上报)
LOG_DIR="/root/Test_Logs/Memtest"
mkdir -p "$LOG_DIR"
LOCAL_LOG="$LOG_DIR/memtest_detail.log"

rotate_log() {{
    local max_size=$((5 * 1024 * 1024))
    if [ -f "$LOCAL_LOG" ]; then
        local size=$(stat -c%s "$LOCAL_LOG")
        if [ $size -ge $max_size ]; then
            mv "$LOCAL_LOG" "$LOCAL_LOG.$(date +%Y%m%d_%H%M%S).bak"
            ls -t "$LOG_DIR"/*.bak | tail -n +4 | xargs -r rm
        fi
    fi
}}

log_to_local() {{
    local msg=$1
    local time_now=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$time_now] $msg" >> "$LOCAL_LOG"
    rotate_log
}}

report_backend() {{
    local status=$1
    local msg=$2
    JSON_DATA="{{\\"server_id\\": \\"$SERVER_ID\\", \\"task_type\\": \\"memtest\\", \\"phase\\": \\"$msg\\", \\"status\\": \\"$status\\"}}"
    curl --noproxy "*" -s -X POST "$URL" -H "Content-Type: application/json" -d "$JSON_DATA" >/dev/null 2>&1
}}

log_to_local "Daemon Started. Waiting 15s..."
sleep 15

while true; do
    RAW_PIDS=$(pgrep -f "memtester")
    VALID_PIDS=$(echo "$RAW_PIDS" | xargs -r ps -fp 2>/dev/null | grep -v "grep" | grep -v "memtest_daemon" | grep -v "bash -c" | grep -v "PID" | awk '{{print $2}}')
    COUNT=$(echo "$VALID_PIDS" | wc -w)

    if [ -n "$VALID_PIDS" ]; then
        MSG="压测中 ($COUNT 个核心运行中)"
        log_to_local "$MSG"
        report_backend "Running" "$MSG"
    else
        MSG="压测已结束"
        log_to_local "$MSG. Stopping Daemon."
        report_backend "Finished" "$MSG"
        exit 0
    fi
    sleep 5
done
"""
    
    cmd = f"""
        cd {REMOTE_MEMTEST_DIR} || exit 1
        cat > memtest_daemon.sh << 'EOF_MON'
{monitor_script}
EOF_MON
        chmod +x memtest_daemon.sh
        sed -i 's/^runtime=[0-9]*/runtime={runtime}/' {SCRIPT_MEMTEST_NAME}
        export DISPLAY=:0
        nohup gnome-terminal --title="System Monitor" -- gnome-system-monitor >/dev/null 2>&1 &
        sleep 1
        nohup gnome-terminal --working-directory="{REMOTE_MEMTEST_DIR}" --title="Memtest Run" -- bash -c "./{SCRIPT_MEMTEST_NAME}; echo 'Test Done. Press Enter.'; read" >/dev/null 2>&1 &
        nohup ./memtest_daemon.sh >/dev/null 2>&1 &
        echo "SUCCESS: Memtest Started"
    """
    return run_ssh_command(server.os_ip, server.ssh_user, server.ssh_password, cmd)

# --- 3. 停止与归档 (修正：分离归档) ---
async def stop_memtest(server: ServerSchema):
    logger.info(f"[{server.server_id}] 停止 Memtest 并归档...")
    
    # 1. 停止进程
    stop_cmd = f"""
        kill_target() {{ pgrep -f "$1" | grep -v grep | grep -v python | xargs -r kill -9 2>/dev/null || true; }}
        kill_target "memtest_daemon.sh"
        kill_target "{SCRIPT_MEMTEST_NAME}"
        killall -9 memtester 2>/dev/null || true
        pkill -f "bash -c .*memtester" || true
    """
    await run_ssh_command(server.os_ip, server.ssh_user, server.ssh_password, stop_cmd)

    # 2. 归档 (严格分离 result 和 dmesg)
    # 结果：mem_result.tar.gz (只包含 mem_result 文件夹)
    # 日志：dmesg.log (单独存在)
    archive_cmd = f"""
        cd {REMOTE_MEMTEST_DIR} || exit 1
        
        # 生成 dmesg (单独存放，不打包)
        dmesg > dmesg.log
        
        # 仅打包 mem_result 文件夹
        if [ -d "mem_result" ]; then
            tar -czvf mem_result.tar.gz mem_result
            echo "SUCCESS: Archived mem_result.tar.gz"
        else
            echo "SUCCESS: No mem_result found to archive"
        fi
    """
    return run_ssh_command(server.os_ip, server.ssh_user, server.ssh_password, archive_cmd)

async def archive_memtest(server: ServerSchema):
    return await stop_memtest(server)

async def get_runtime_val(server: ServerSchema):
    cmd = f"grep -E '^runtime=' {REMOTE_MEMTEST_DIR}/{SCRIPT_MEMTEST_NAME} | cut -d'=' -f2"
    success, output = run_ssh_command(server.os_ip, server.ssh_user, server.ssh_password, cmd)
    return (True, output.strip()) if success and output.strip().isdigit() else (False, "")
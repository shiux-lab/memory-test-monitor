import os
import shutil
from config import *
from utils import get_ssh_client, run_ssh_command, convert_to_unix_format
from models import ServerSchema
from logger import logger

# 定义标准的 rc.local 清理内容 (原版逻辑)
CLEAN_RC_LOCAL_CONTENT = r"""#!/bin/bash
# THIS FILE IS ADDED FOR COMPATIBILITY PURPOSES
touch /var/lock/subsys/local
exit 0
"""

# --- 部署逻辑 (融合版：带 Trash 和 Safe Kill) ---
def deploy_reboot_scripts(server: ServerSchema):
    try:
        logger.info(f"[{server.server_id}] 开始部署 Reboot 脚本 (V3.0 融合修复版)...")
        
        # 1. 本地文件准备
        if os.path.exists(TEMP_SCRIPT_DIR): shutil.rmtree(TEMP_SCRIPT_DIR)
        os.makedirs(TEMP_SCRIPT_DIR)

        files = [SCRIPT_CHAIN_NAME, SCRIPT_CYCLE_NAME, SCRIPT_MONITOR_NAME]
        for f in files:
            if not os.path.exists(os.path.join(LOCAL_SCRIPT_DIR, f)):
                return False, f"本地文件缺失: {f}"

        # 2. 变量注入 (Backend URL, Server ID)
        backend_url = f"http://{BACKEND_IP_PORT}/report/webhook"
        
        for fname in files:
            with open(os.path.join(LOCAL_SCRIPT_DIR, fname), 'r', encoding='utf-8') as f:
                content = f.read().replace("{{BACKEND_URL}}", backend_url).replace("{{SERVER_ID}}", server.server_id)
            with open(os.path.join(TEMP_SCRIPT_DIR, fname), 'w', encoding='utf-8', newline='\n') as f:
                f.write(convert_to_unix_format(content))

        # 3. SSH 连接与环境清理 (找回原版的 safe_kill 和 Trash 逻辑)
        ssh = get_ssh_client(server.os_ip, server.ssh_user, server.ssh_password)
        
        # 复杂的清理脚本
        cleanup_cmd = f"""
            set -x
            mkdir -p {REMOTE_WORK_DIR}
            mkdir -p /root/Test_Logs/Reboot
            
            # 1. 安全杀进程
            safe_kill() {{
                pgrep -f "$1" | grep -v $$ | xargs -r kill -9 2>/dev/null || true
            }}
            safe_kill "{SCRIPT_MONITOR_NAME}"
            safe_kill "{SCRIPT_CHAIN_NAME}"
            safe_kill "{SCRIPT_CYCLE_NAME}"
            rm -f {REMOTE_WORK_DIR}/.is_reboot_running

            # 2. 移动旧文件到 Trash (原版功能回归)
            cd {REMOTE_WORK_DIR} || exit 1
            mkdir -p Trash
            # 将除了 Trash 目录、log目录以外的所有文件移入 Trash
            find . -maxdepth 1 -mindepth 1 -name 'Trash' -prune -o -name 'Test_Logs' -prune -o -exec mv -f {{}} Trash/ \\;

            # 3. 重置 rc.local
            cat > /etc/rc.d/rc.local <<'EOF'
{CLEAN_RC_LOCAL_CONTENT}EOF
            chmod +x /etc/rc.d/rc.local
            chmod +x /etc/rc.local
        """
        
        stdin, stdout, stderr = ssh.exec_command(cleanup_cmd)
        exit_status = stdout.channel.recv_exit_status()
        if exit_status != 0:
            err = stderr.read().decode()
            logger.error(f"清理环境失败: {err}")
            ssh.close()
            return False, f"环境清理失败: {err}"

        # 4. 上传新文件
        sftp = ssh.open_sftp()
        for f in files:
            sftp.put(os.path.join(TEMP_SCRIPT_DIR, f), f"{REMOTE_WORK_DIR}/{f}")
        sftp.close()
        
        # 5. 赋予权限
        ssh.exec_command(f"chmod +x {REMOTE_WORK_DIR}/*.sh")
        ssh.close()
        shutil.rmtree(TEMP_SCRIPT_DIR)
        
        return True, "部署成功 (Trash归档/RC重置已执行)"
    except Exception as e:
        logger.exception(f"[{server.server_id}] Reboot 部署异常")
        return False, f"部署异常: {str(e)}"

# --- 启动逻辑 (融合版：找回 dos2unix 和 setsid) ---
async def start_reboot_test(server: ServerSchema):
    logger.info(f"[{server.server_id}] 启动 Reboot 测试...")
    
    # 【核心修复】加入 dos2unix 防止 Windows 格式报错
    # 【核心修复】使用 setsid 确保 SSH 断开后进程存活
    start_cmd = f"""
        cd {REMOTE_WORK_DIR} || exit 1
        
        # 1. 格式修复 (防止 command not found)
        if command -v dos2unix >/dev/null 2>&1; then
            dos2unix -q *.sh
        fi
        chmod +x *.sh
        
        # 2. 创建运行锁 (配合 monitor_daemon.sh)
        touch .is_reboot_running
        
        # 3. 启动监控 (使用 setsid + < /dev/null 彻底脱离终端)
        # 监控脚本启动后，会自己去拉起 Chain 脚本
        setsid nohup bash {SCRIPT_MONITOR_NAME} > monitor.out 2>&1 < /dev/null &
        
        sleep 1
        PID=$(pgrep -f "{SCRIPT_MONITOR_NAME}")
        if [ -n "$PID" ]; then
            echo "SUCCESS: Monitor Started (PID: $PID)"
        else
            echo "FAILED: Monitor failed to start"
        fi
    """
    return run_ssh_command(server.os_ip, server.ssh_user, server.ssh_password, start_cmd)

# --- 停止逻辑 (融合版：找回 -q 优雅退出) ---
async def stop_reboot_test(server: ServerSchema):
    logger.info(f"[{server.server_id}] 停止 Reboot 测试并归档...")
    
    # 【核心修复】先尝试 -q 优雅退出，再强杀
    stop_cmd = f"""
        cd {REMOTE_WORK_DIR} || exit 0
        
        # 1. 删除锁文件 (通知监控脚本停止)
        rm -f .is_reboot_running
        
        # 2. 【回归】发送 Quit 信号 (优雅停止)
        if [ -f "{SCRIPT_CYCLE_NAME}" ]; then
            bash {SCRIPT_CYCLE_NAME} -q || true
        fi
        
        # 3. 强杀 (兜底)
        kill_target() {{ pgrep -f "$1" | grep -v grep | xargs -r kill -9 2>/dev/null || true; }}
        kill_target "{SCRIPT_CHAIN_NAME}"
        kill_target "{SCRIPT_MONITOR_NAME}"
        kill_target "{SCRIPT_CYCLE_NAME}"
        pkill -f "stressapptest" || true
        
        # 4. 清理 rc.local (恢复原状)
        cat > /etc/rc.d/rc.local <<'EOF'
{CLEAN_RC_LOCAL_CONTENT}EOF
        chmod +x /etc/rc.d/rc.local
        
        # 5. 归档日志 (V2.1 逻辑)
        LOG_DIR="/root/Test_Logs/Reboot"
        if [ -d "$LOG_DIR" ]; then
            TIME_TAG=$(date +%Y%m%d_%H%M%S)
            TAR_NAME="reboot_logs_$TIME_TAG.tar.gz"
            tar -czvf $TAR_NAME -C /root/Test_Logs Reboot
            echo "SUCCESS: Logs archived to $TAR_NAME"
        else
            echo "SUCCESS: Stopped (No logs found)"
        fi
    """
    return run_ssh_command(server.os_ip, server.ssh_user, server.ssh_password, stop_cmd)

# --- 重置逻辑 (融合版：Trash 归档) ---
async def reset_reboot_files(server: ServerSchema):
    logger.info(f"[{server.server_id}] 重置环境...")
    
    reset_cmd = f"""
        cd {REMOTE_WORK_DIR} || exit 0
        
        # 1. 停止
        rm -f .is_reboot_running
        if [ -f "{SCRIPT_CYCLE_NAME}" ]; then bash {SCRIPT_CYCLE_NAME} -q || true; fi
        pkill -f "{SCRIPT_MONITOR_NAME}"
        pkill -f "{SCRIPT_CHAIN_NAME}"
        
        cat > /etc/rc.d/rc.local <<'EOF'
{CLEAN_RC_LOCAL_CONTENT}EOF
        chmod +x /etc/rc.d/rc.local

        # 2. 清理日志
        rm -rf /root/Test_Logs/Reboot
        
        # 3. 【回归】移动文件到 Trash
        mkdir -p Trash
        find . -maxdepth 1 -type f -not -name "*.sh" -exec mv {{}} Trash/ \\;
        
        echo "SUCCESS: Reset Done"
    """
    return run_ssh_command(server.os_ip, server.ssh_user, server.ssh_password, reset_cmd)
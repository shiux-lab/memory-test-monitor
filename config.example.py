# 本机后端地址 (开发/生产环境修改这里即可)
BACKEND_IP_PORT = "172.16.*.*:8080"  # 你的开发环境端口

# --- 内存检查测试配置 ---
SCRIPT_MEM_INFO_NAME = "get_memory_info.sh"
REMOTE_MEM_DIR = "/root/MemInfo"
LOCAL_DOWNLOAD_DIR = "data/downloads" # 本地存放下载文件的地方

# --- Memtest 压力测试配置 ---
SCRIPT_MEMTEST_NAME = "memtester.sh"
FILE_MEMTEST_TAR = "memtester-4.6.0.tar.gz"
REMOTE_MEMTEST_DIR = "/root/Memtest"

# 路径配置
LOCAL_SCRIPT_DIR = "scripts"
TEMP_SCRIPT_DIR = "temp_scripts"
REMOTE_WORK_DIR = "/root/Reboot"
DB_FILE = "data/servers_db.json"

# 脚本名称配置
SCRIPT_CYCLE_NAME = "Cycle_OSReboot_V2.2.3.sh"
SCRIPT_CHAIN_NAME = "auto_cold_warm_stress_chain.sh"
SCRIPT_MONITOR_NAME = "monitor_daemon.sh"

# RC.Local 恢复模板
CLEAN_RC_LOCAL_CONTENT = r"""#!/bin/bash
# THIS FILE IS ADDED FOR COMPATIBILITY PURPOSES
touch /var/lock/subsys/local
exit 0
"""
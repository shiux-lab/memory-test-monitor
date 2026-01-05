#!/bin/bash
# 
# 脚本名称: get_memory_info.sh
# 描述: 收集详细的内存信息并将其格式化输出到日志文件中，
#      包含命令提示符以匹配示例格式。

# --- 配置 ---
# 定义日志文件名，加入日期和时间戳避免被覆盖
LOG_FILE="memory_info_$(date +%Y-%m-%d_%H%M%S).txt"
# 定义要模拟的提示符
PROMPT='[root@localhost ~]#'

# --- 辅助函数 ---

# 定义一个函数，用于打印提示符、命令，然后执行该命令
# 这种方式可以确保日志文件的格式与您提供的一致
run_and_log() {
    local cmd_string="$1"
    
    # 1. 打印模拟的提示符和命令字符串
    echo "$PROMPT $cmd_string"
    
    # 2. 使用 'eval' 来执行完整的命令字符串
    #    'eval' 是必需的，因为它允许shell正确解析管道符(|)和引号
    eval "$cmd_string"
}

# --- 主程序 ---

echo "正在收集内存信息，请稍候..."

# 使用重定向将后续所有 'run_and_log' 函数的
# 标准输出 (stdout) 和 标准错误 (stderr) 
# 全部重定向到日志文件中。
{
    run_and_log 'dmidecode -t 17 | grep -i "part number"'
    run_and_log 'dmidecode -t 17 | grep -i "serial number"'
    run_and_log 'dmidecode -t 17 | grep -i "speed"'
    run_and_log 'cat /proc/meminfo'
    run_and_log 'dmidecode -t 17 memory'

} > "$LOG_FILE" 2>&1

echo "信息收集完毕。"
echo "日志文件已保存到: $LOG_FILE"

exit 0

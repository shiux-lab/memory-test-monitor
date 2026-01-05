import subprocess
import platform
import paramiko
import time

def ping_ip(ip: str) -> bool:
    if not ip or ip.lower() in ["string", "null", "none"]: return False
    param = '-n' if platform.system().lower() == 'windows' else '-c'
    timeout_param = '-w' if platform.system().lower() == 'windows' else '-W'
    timeout_val = '500' if platform.system().lower() == 'windows' else '1'
    try:
        return subprocess.call(['ping', param, '1', timeout_param, timeout_val, ip], 
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0
    except:
        return False

def get_ssh_client(ip, user, pwd):
    print(f"   [SSH-Debug] Connecting to {ip} as {user}...") # 调试打印
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(ip, username=user, password=pwd, timeout=10) # 延长超时到10秒
    print(f"   [SSH-Debug] Connected!") 
    return ssh

def run_ssh_command(ip, user, pwd, command):
    print(f"--- [SSH-CMD-START] Target: {ip} ---")
    # 只打印命令的前100个字符，防止刷屏，但也足够确认是否发送了
    print(f"Command Preview: {command.strip()[:100]}...") 
    
    try:
        ssh = get_ssh_client(ip, user, pwd)
        stdin, stdout, stderr = ssh.exec_command(command)
        
        # 实时获取退出状态，判定是否执行完毕
        exit_status = stdout.channel.recv_exit_status()
        
        result = stdout.read().decode().strip()
        error = stderr.read().decode().strip()
        
        ssh.close()
        
        print(f"   [SSH-Debug] Exit Code: {exit_status}")
        if result: print(f"   [SSH-Debug] STDOUT: {result[:200]}...") # 打印部分输出
        if error:  print(f"   [SSH-Debug] STDERR: {error}")
        print(f"--- [SSH-CMD-END] ---")
        
        # 只要没有严重的连接错误，我们都返回 True，让上层去判断 stdout 内容
        return True, result if result else (error if error else "Command executed (No output)")
        
    except Exception as e:
        print(f"!!! [SSH-ERROR] {str(e)}")
        return False, f"SSH Connection Error: {str(e)}"

def convert_to_unix_format(content: str) -> str:
    return content.replace('\r\n', '\n')
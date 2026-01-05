import os
from config import *
from utils import get_ssh_client, run_ssh_command
from models import ServerSchema

def deploy_meminfo(server: ServerSchema):
    try:
        src = os.path.join(LOCAL_SCRIPT_DIR, SCRIPT_MEM_INFO_NAME)
        if not os.path.exists(src): return False, "脚本缺失"
        
        ssh = get_ssh_client(server.os_ip, server.ssh_user, server.ssh_password)
        ssh.exec_command(f"rm -rf {REMOTE_MEM_DIR}; mkdir -p {REMOTE_MEM_DIR}")
        sftp = ssh.open_sftp()
        sftp.put(src, f"{REMOTE_MEM_DIR}/{SCRIPT_MEM_INFO_NAME}")
        sftp.close()
        ssh.exec_command(f"chmod +x {REMOTE_MEM_DIR}/{SCRIPT_MEM_INFO_NAME}")
        ssh.close()
        return True, "MemInfo 部署成功"
    except Exception as e:
        return False, str(e)

async def run_meminfo(server: ServerSchema):
    cmd = f"cd {REMOTE_MEM_DIR}; ./{SCRIPT_MEM_INFO_NAME}; ls -F"
    return run_ssh_command(server.os_ip, server.ssh_user, server.ssh_password, cmd)

async def download_meminfo_result(server: ServerSchema):
    try:
        ssh = get_ssh_client(server.os_ip, server.ssh_user, server.ssh_password)
        stdin, stdout, stderr = ssh.exec_command(f"find {REMOTE_MEM_DIR} -name '*.txt' | head -1")
        remote_path = stdout.read().decode().strip()
        
        if not remote_path: return False, "未找到结果文件", None
        
        if not os.path.exists(LOCAL_DOWNLOAD_DIR): os.makedirs(LOCAL_DOWNLOAD_DIR)
        local_path = os.path.join(LOCAL_DOWNLOAD_DIR, f"{server.server_id}_{os.path.basename(remote_path)}")
        
        sftp = ssh.open_sftp()
        sftp.get(remote_path, local_path)
        sftp.close()
        ssh.close()
        return True, "下载成功", local_path
    except Exception as e:
        return False, str(e), None
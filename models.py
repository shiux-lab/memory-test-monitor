from pydantic import BaseModel
from typing import Optional

class ServerSchema(BaseModel):
    server_id: str
    bmc_ip: str
    os_ip: Optional[str] = None
    
    # SSH 凭证
    ssh_user: str = "root"
    ssh_password: str = "1"
    
    # 基础连接状态
    os_online: bool = False
    bmc_online: bool = False
    last_report_time: str = "-"

    # --- 1. 重启压力测试 专用状态 ---
    reboot_status: str = "Idle"
    reboot_phase: str = "未部署"
    reboot_loop: str = "-"

    # --- 2. Memtest 压测 专用状态 ---
    memtest_status: str = "Idle"
    memtest_phase: str = "未部署"
    memtest_runtime_configured: str = "-" 

    # --- 3. 信息检查 专用状态 ---
    meminfo_status: str = "Idle"

class WebhookSchema(BaseModel):
    server_id: str
    
    # 【核心修正】
    # 允许为空 (Optional)，为了兼容正在运行的旧脚本
    # 但去掉了 default="reboot"，避免未来新加入的测试项被误判
    task_type: Optional[str] = None 
    
    status: str
    phase: str
    loop: Optional[str] = "-"
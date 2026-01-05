from fastapi import APIRouter, HTTPException, Request
from fastapi.templating import Jinja2Templates
from fastapi.responses import FileResponse
from pydantic import BaseModel
import datetime
import os

from models import ServerSchema, WebhookSchema
from database import servers_db, save_db
from utils import ping_ip
from logger import logger

# --- 核心修复：从新的 services 包导入 ---
# 注意：这里使用了 as 别名，保持和旧代码兼容
from services import reboot as service_reboot
from services import memtest as service_memtest
from services import meminfo as service_meminfo

router = APIRouter()
templates = Jinja2Templates(directory="templates")

class MemtestStartSchema(BaseModel):
    runtime: str

# --- 首页 ---
@router.get("/")
async def dashboard(request: Request):
    return templates.TemplateResponse("index.html", {
        "request": request, 
        "servers_json": [s.model_dump() for s in servers_db.values()]
    })

# --- 监控刷新 ---
@router.post("/monitor/refresh")
async def refresh_status():
    changed = False
    results = []
    
    for s_id, server in servers_db.items():
        old_os = server.os_online
        
        # 1. 执行物理 Ping
        server.bmc_online = ping_ip(server.bmc_ip)
        current_os_online = ping_ip(server.os_ip) if server.os_ip else False
        
        # 2. 【核心修复】智能状态判定
        if current_os_online:
            # A. 如果 Ping 通了
            server.os_online = True
            
            # 如果之前标记为 "重启中"，现在通了，说明重启完成，正在恢复
            # 这里不需要做太多，因为 Monitor 脚本很快会上报新的 Phase
            pass
            
        else:
            # B. 如果 Ping 不通
            # 关键判断：是在“测试中”断连，还是“闲置”断连？
            
            if server.reboot_status == "Running":
                # 这是一个正在跑重启测试的机器 -> 视为 "预期内离线"
                server.os_online = False # 物理确实离线
                
                # 但不报错，甚至可以更新一下 Phase 提示用户
                # 注意：不要频繁覆盖 Phase，只在 Phase 不是 "重启中..." 时改一下，避免覆盖了脚本上报的详细信息
                # 这里我们选择不做任何 Phase 修改，保留最后一次脚本上报的状态（比如 "Going for Reboot..."）
                # 这样用户就能看到 "Running" + "Loop 5" + "OS 离线(预期)"
                pass
                
            else:
                # 这是一个闲置机器 -> 视为 "故障离线"
                server.os_online = False

        if server.os_online != old_os:
            changed = True
            
        results.append(server)
    
    if changed: save_db()
    return {"results": [s.model_dump() for s in results]}

# --- Webhook ---
@router.post("/report/webhook")
async def receive_report(data: WebhookSchema):
    if data.server_id not in servers_db:
        return {"status": "ignored"}

    srv = servers_db[data.server_id]
    
    if data.task_type == "memtest":
        srv.memtest_status = data.status
        srv.memtest_phase = data.phase
    elif data.task_type == "reboot":
        srv.reboot_status = data.status
        srv.reboot_phase = data.phase
        srv.reboot_loop = data.loop
    elif data.task_type is None:
        # 兼容旧逻辑
        srv.reboot_status = data.status
        srv.reboot_phase = data.phase
        srv.reboot_loop = data.loop

    srv.last_report_time = datetime.datetime.now().strftime("%H:%M:%S")
    save_db()
    return {"status": "ok"}

# ================= REBOOT 路由 (调试增强版) =================

@router.post("/servers/{server_id}/deploy")
async def reboot_deploy(server_id: str):
    print(f"\n>>> DEBUG: 收到 Reboot 部署请求: {server_id}") # 调试点
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    
    # 暂时跳过 ping 检查，强制尝试连接，方便调试 SSH
    # if not ping_ip(server.os_ip): return {"success": False, "message": "OS Ping 不通"}
    
    # 调用 services/reboot.py 里的函数
    success, msg = service_reboot.deploy_reboot_scripts(server)
    
    print(f">>> DEBUG: 部署结果: {success}, {msg}") # 调试点
    if success:
        server.reboot_status = "Deployed"
        server.reboot_phase = "已部署"
        save_db()
    return {"success": success, "message": msg}

@router.post("/servers/{server_id}/start_test")
async def reboot_start(server_id: str):
    print(f"\n>>> DEBUG: 收到 Reboot 启动请求: {server_id}")
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    
    success, msg = await service_reboot.start_reboot_test(server)
    
    print(f">>> DEBUG: 启动结果: {success}, {msg}")
    if success:
        server.reboot_status = "Running"
        server.reboot_phase = "正在启动..."
        save_db()
    return {"success": success, "message": msg}

@router.post("/servers/{server_id}/stop_test")
async def reboot_stop(server_id: str):
    print(f"\n>>> DEBUG: 收到 Reboot 停止请求: {server_id}")
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    
    # 这里会调用 services/reboot.py 里的 stop_reboot_test
    # 里面包含了 kill -9, rm .is_reboot_running, 和归档逻辑
    success, msg = await service_reboot.stop_reboot_test(server)
    
    print(f">>> DEBUG: 停止结果: {success}, {msg}")
    if success:
        server.reboot_status = "Stopped"
        server.reboot_phase = "用户已停止"
        save_db()
    return {"success": success, "message": msg}

@router.post("/servers/{server_id}/reset_files")
async def reboot_reset(server_id: str):
    print(f"\n>>> DEBUG: 收到 Reboot 重置请求: {server_id}")
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    
    # 这里会调用 services/reboot.py 里的 reset_reboot_files
    # 里面包含了 mkdir Trash 的逻辑
    success, msg = await service_reboot.reset_reboot_files(server)
    
    if success:
        server.reboot_status = "Idle"
        server.reboot_phase = "环境已重置"
        server.reboot_loop = "-"
        save_db()
    return {"success": success, "message": msg}

# ================= MEMTEST 路由 =================
@router.post("/servers/{server_id}/memtest/deploy")
async def memtest_deploy(server_id: str):
    print(f"\n>>> DEBUG: 收到 Memtest 部署请求: {server_id}")
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    success, msg = service_memtest.deploy_memtest_env(server)
    if success:
        server.memtest_status = "Deployed"
        server.memtest_phase = "环境就绪"
        save_db()
    return {"success": success, "message": msg}

@router.post("/servers/{server_id}/memtest/start")
async def memtest_start(server_id: str, payload: MemtestStartSchema):
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    success, msg = await service_memtest.start_memtest(server, payload.runtime)
    if success:
        server.memtest_status = "Running"
        server.memtest_phase = "启动指令已发"
        server.memtest_runtime_configured = payload.runtime
        save_db()
    return {"success": success, "message": msg}

@router.post("/servers/{server_id}/memtest/archive")
async def memtest_archive(server_id: str):
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    success, msg = await service_memtest.archive_memtest(server)
    if success:
        server.memtest_status = "Finished"
        server.memtest_phase = "已归档"
        save_db()
    return {"success": success, "message": msg}

@router.get("/servers/{server_id}/memtest/runtime")
async def memtest_runtime(server_id: str):
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    return {"success": True, "runtime": server.memtest_runtime_configured}

# ================= MEMINFO 路由 =================
@router.post("/servers/{server_id}/meminfo/deploy")
async def meminfo_deploy(server_id: str):
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    success, msg = service_meminfo.deploy_meminfo(server)
    return {"success": success, "message": msg}

@router.post("/servers/{server_id}/meminfo/run")
async def meminfo_run(server_id: str):
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    success, msg = await service_meminfo.run_meminfo(server)
    return {"success": success, "message": msg}

@router.get("/servers/{server_id}/meminfo/download")
async def meminfo_download(server_id: str):
    server = servers_db.get(server_id)
    if not server: raise HTTPException(404)
    success, msg, path = await service_meminfo.download_meminfo_result(server)
    if success and path:
        return FileResponse(path=path, filename=os.path.basename(path), media_type='text/plain')
    return {"success": False, "message": msg}

# --- 服务器管理 ---
@router.post("/servers/add")
async def add_server(server: ServerSchema):
    if server.server_id in servers_db:
        pass 
    servers_db[server.server_id] = server
    save_db()
    return {"message": "OK"}

@router.delete("/servers/delete/{server_id}")
async def delete_server(server_id: str):
    if server_id in servers_db:
        del servers_db[server_id]
        save_db()
        return {"status": "success"}
    raise HTTPException(404)
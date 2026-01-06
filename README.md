# memory-test-monitor
服务器自动化测试监控平台（FastAPI + Vue 单页）

本项目用于集中管理服务器的重启压力测试、内存压测（memtester）以及内存信息采集，提供 Web 控制台和 API 接口，支持一键部署脚本、启动/停止测试、归档结果。

## 功能概览
- 服务器列表管理（BMC/OS IP）
- 重启压力测试：部署、启动、停止、重置
- Memtest 压测：部署、配置运行时长、启动、归档
- MemInfo 信息采集：执行脚本、下载结果
- 实时状态刷新（OS/BMC 连通性、任务状态、阶段/轮次）

## 技术栈
- 后端：FastAPI + Uvicorn
- 前端：Vue 3（模板 `templates/index.html`，Jinja2 渲染）
- 远程执行：Paramiko SSH

## 目录结构
- `main.py`：应用入口
- `routes.py`：HTTP API + 页面路由
- `services/`：重启、memtest、meminfo 业务逻辑
- `scripts/`：部署到远端的脚本与工具包
- `templates/`：Web 控制台
- `data/`：持久化数据与下载文件（需要创建）
- `logs/`：后端日志（自动创建）

## 环境要求
- 本地（运行后端）：
  - Python 3.8+
  - 依赖：`fastapi`、`uvicorn`、`paramiko`、`jinja2`、`pydantic`
- 远端（被测服务器）：
  - Linux，支持 SSH 登录（默认使用 `root`）
  - 常用工具：`bash`、`curl`、`tar`、`make`、`gcc`、`pgrep`、`dmesg`
  - 可选：`dos2unix`（用于脚本格式修复）
  - Memtest 默认会尝试启动 `gnome-terminal` 和 `gnome-system-monitor`，若为纯命令行环境请按「常见问题」处理

## 快速开始
1. 安装依赖（建议使用虚拟环境）：
   ```bash
   python -m venv .venv
   .\.venv\Scripts\activate
   pip install fastapi uvicorn paramiko jinja2 pydantic
   ```

2. 创建数据目录：
   ```bash
   mkdir data
   mkdir data\downloads
   ```

3. 修改配置 `config.py`：
   - `BACKEND_IP_PORT`：对外可访问的后端地址与端口（用于脚本回调）
   - `DB_FILE`：本地数据文件路径（默认 `data/servers_db.json`）

4. 启动服务：
   ```bash
   python main.py
   ```
   或：
   ```bash
   uvicorn main:app --host 0.0.0.0 --port 8080
   ```

5. 打开浏览器访问：
   - `http://<你的主机IP>:8080/`

## 配置说明（config.py）
关键配置项：
- `BACKEND_IP_PORT`：脚本向后端上报状态的地址，务必能被远端服务器访问
- `LOCAL_SCRIPT_DIR`：本地脚本目录（默认 `scripts`）
- `REMOTE_WORK_DIR` / `REMOTE_MEMTEST_DIR` / `REMOTE_MEM_DIR`：远端部署目录
- `DB_FILE`：服务器列表持久化文件
- `LOCAL_DOWNLOAD_DIR`：MemInfo 下载存放目录

## 使用流程
1. 在 Web 控制台添加服务器（Server ID + BMC IP + OS IP）
2. 确保 OS IP 可 SSH 访问（默认用户/密码为 `root/1`，可在添加时扩展或修改）
3. 选择测试模式：
   - **重启压力测试**：部署 → 启动 → 停止 → 重置
   - **Memtest 压测**：部署 → 配置时长 → 启动 → 归档
   - **MemInfo 检查**：执行 → 下载结果

## 常用 API（摘选）
- `POST /monitor/refresh`：刷新所有服务器状态
- `POST /servers/add`：添加服务器
- `DELETE /servers/delete/{server_id}`：删除服务器
- `POST /servers/{server_id}/deploy`：部署重启测试
- `POST /servers/{server_id}/start_test`：启动重启测试
- `POST /servers/{server_id}/stop_test`：停止重启测试
- `POST /servers/{server_id}/reset_files`：重置重启测试环境
- `POST /servers/{server_id}/memtest/deploy`：部署 Memtest 环境
- `POST /servers/{server_id}/memtest/start`：启动 Memtest（JSON: `{"runtime": "43200"}`）
- `POST /servers/{server_id}/memtest/archive`：归档 Memtest 结果
- `POST /servers/{server_id}/meminfo/deploy`：部署 MemInfo
- `POST /servers/{server_id}/meminfo/run`：运行 MemInfo
- `GET  /servers/{server_id}/meminfo/download`：下载 MemInfo 结果
- `POST /report/webhook`：远端脚本回调入口

## 常见问题
1. **脚本回调不上报**  
   检查 `config.py` 中 `BACKEND_IP_PORT` 是否为远端可访问地址；确保防火墙放通端口。

2. **Memtest 启动失败（无 GUI）**  
   `services/memtest.py` 默认会拉起 `gnome-terminal`。若远端没有 GUI，可移除相关行（`gnome-terminal` 与 `gnome-system-monitor`）后重启后端。

3. **保存数据时报错**  
   请确认 `data/` 目录存在且可写。

## 安全提示
当前默认使用明文密码（`root/1`）进行 SSH 登录，仅适合内网测试环境。生产环境建议改为密钥登录并完善权限控制。

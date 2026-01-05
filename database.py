import json
import os
from typing import Dict
from models import ServerSchema
from config import DB_FILE

# 全局内存数据库
servers_db: Dict[str, ServerSchema] = {}

def save_db():
    """将内存数据写入硬盘"""
    try:
        data = {k: v.model_dump() for k, v in servers_db.items()}
        with open(DB_FILE, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
    except Exception as e:
        print(f"[DB Error] Save failed: {e}")

def load_db():
    """启动时从硬盘读取数据"""
    global servers_db
    if not os.path.exists(DB_FILE):
        return
    try:
        with open(DB_FILE, 'r', encoding='utf-8') as f:
            data = json.load(f)
            for k, v in data.items():
                servers_db[k] = ServerSchema(**v)
        print(f"[DB System] 数据已恢复，加载 {len(servers_db)} 台服务器。")
    except Exception as e:
        print(f"[DB Error] Load failed: {e}")
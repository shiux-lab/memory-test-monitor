import uvicorn
from fastapi import FastAPI
from database import load_db
from routes import router

# 初始化 App
app = FastAPI(title="服务器自动化测试监控平台 (Modular)")

# 加载数据
load_db()

# 注册路由
app.include_router(router)

if __name__ == "__main__":
    # 注意：这里使用 config.py 里的端口可能更好，但为了简单直接写死也行
    uvicorn.run(app, host="0.0.0.0", port=8080)
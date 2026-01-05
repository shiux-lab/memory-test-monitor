# logger.py
import logging
import os
from logging.handlers import RotatingFileHandler

# 1. 自动创建日志目录
if not os.path.exists("logs"):
    os.makedirs("logs")

# 2. 定义日志格式
log_formatter = logging.Formatter('%(asctime)s - %(levelname)s - [%(filename)s:%(lineno)d] - %(message)s')

# 3. 文件输出 (logs/backend.log)
file_handler = RotatingFileHandler('logs/backend.log', maxBytes=10*1024*1024, backupCount=5, encoding='utf-8')
file_handler.setFormatter(log_formatter)
file_handler.setLevel(logging.INFO)

# 4. 控制台输出 (黑窗口也能看)
console_handler = logging.StreamHandler()
console_handler.setFormatter(log_formatter)
console_handler.setLevel(logging.INFO)

# 5. 初始化 Logger
logger = logging.getLogger("MonitorLogger")
logger.setLevel(logging.INFO)
logger.addHandler(file_handler)
logger.addHandler(console_handler)

# 防止重复打印
logger.propagate = False
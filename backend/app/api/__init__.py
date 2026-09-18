"""
API 路由层（Agent-D 装配）。

模块划分（对齐 docs/spec.md §7 接口表，统一挂载到 /api 前缀）：
- router.py         : 聚合所有子路由 + /api/health
- ocr_routes.py     : POST /api/ocr/recognize
- question_routes.py: analyze / CRUD / 批量删除 / 批量移动
- retrieval_routes.py: POST /api/retrieval/match
- knowledge_routes.py: GET /api/knowledge-points
- import_routes.py  : POST /api/import/paper（骨架 501）
- export_routes.py  : GET /api/export/pdf|worksheet
- settings_routes.py: GET/PUT /api/settings
- deps.py           : 路由层共享工具（ServiceError 转换 / OCR 归一化 /
                      匹配结果归一化 / 向量库同步 / LLM 客户端同步）

路由层职责：
1. 捕获业务层 ServiceError -> HTTPException(status_code=e.status_code, detail=e.message)；
2. 用 FastAPI get_db() 注入 Session；
3. 题目入库 / 更新 / 删除后同步 ChromaDB 向量库（DATA_MODEL.md §4.2）；
4. 只做编排，不写业务逻辑（全部委托给 services / ocr / retrieval / llm 层）。
"""

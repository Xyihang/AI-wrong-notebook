# 用户注册与认证功能 — 实施计划（PLAN-AUTH）

> 状态：**后端已实施（本地验证通过，待用户确认后上传服务器）**　对应需求：用户注册 + 认证，多用户数据隔离
> 存储方案：**方案① 复用现有 SQLite**（不建独立 SQL 服务 / 不装 MySQL / 不用 SQLPub 实例）
> 目标：**为「商用 / 多用户」打基础**：用户注册登录 + JWT 鉴权 + 按用户隔离错题数据
> 说明：本计划仅后端。前端登录页 / token 存储 / 请求头带 token 为后续工作。

---

## 1. 背景与目标

当前系统是「单用户、无登录」：任何人访问后端都能读写全部错题。商用需要：
1. 用户可**注册 / 登录**；
2. 每个用户**只能看到 / 编辑自己的错题**；
3. 认证采用**无独立数据库**的方式——复用后端已有的 **SQLite**（`backend/data/wrongbook.db`），**不引入任何独立数据库服务**。

> 说明：后端本来就是 SQLite（单个文件，零部署）。加认证只是往现有 SQLite 文件里**新增一张 users 表**，不违反「不建 SQL 服务」的约束。

---

## 2. 技术方案

| 项 | 选择 | 理由 |
|---|---|---|
| 存储 | **SQLite**（现有 `wrongbook.db` 加 `users` 表）| 零部署，复用现有 |
| 密码 | **加盐哈希**（`pbkdf2_hmac` 或 `bcrypt`）| 不存明文，防拖库泄露 |
| Token | **JWT**（无状态，`python-jose` 或 `PyJWT`）| 服务端无需存会话，天然适配多后端/多端 |
| 鉴权 | FastAPI **依赖注入**（`Depends(get_current_user)`）| 与现有 `Depends(get_db)` 风格一致 |
| 用户隔离 | 所有题目查询 / 写入按 `user_id` 过滤 | 数据不串用户 |

---

## 3. 功能范围（Must / Should）

### Must（必做）
- [x] 用户注册：`POST /api/auth/register`（用户名 + 密码 → 创建用户）
- [x] 用户登录：`POST /api/auth/login`（校验 → 返回 JWT + 用户信息）
- [x] 当前用户：`GET /api/auth/me`（token → 用户信息）
- [x] 修改密码：`POST /api/auth/change-password`（旧密码校验 → 更新新密码）
- [x] 鉴权：`/api/auth/me`、`/change-password` 强制登录；`/api/questions/*` 采用**可选鉴权**（见下方设计决策）
- [x] 用户数据隔离：错题的增删改查均带 `user_id`，只返回当前用户的

### Should（应有）
- [x] 用户名唯一校验 + 密码强度（≥6 位）校验
- [x] 密码哈希使用**慢哈希**（pbkdf2_sha256，26 万次迭代）
- [x] Token 过期时间（默认 7 天）可配置（.env `JWT_EXPIRE_DAYS`）
- [x] 401 统一返回格式，前端据此跳登录

### Won't（暂不做）
- [x] 手机号 / 邮箱 / 微信第三方登录（后续扩展）
- [x] 验证码、找回密码、邮件通知
- [x] 角色 / 权限（RBAC）
- [x] 把错题数据迁到独立 MySQL（保持 SQLite）

> **向后兼容设计决策**：`/api/questions/*` 未强制登录（用 `get_optional_user`）。
> 已登录用户按自己的 `user_id` 隔离 + 可见历史共享数据（`user_id=0`）；
> 匿名 / 未接入登录的旧客户端仍可访问（落到 `user_id=0` 档）。
> 待前端登录页接入后，可将这些路由改为强制登录（`get_current_user`）。

---

## 4. 数据模型（新增）

### 4.1 users 表
```text
users
  id            INTEGER PRIMARY KEY AUTOINCREMENT
  uuid          VARCHAR(36)  UNIQUE        # 对外用户标识
  username      VARCHAR(64)  UNIQUE NOT NULL
  password_hash VARCHAR(255) NOT NULL       # 加盐哈希（bcrypt/pbkdf2）
  display_name  VARCHAR(64)  DEFAULT ''
  created_at    DATETIME     NOT NULL
  updated_at    DATETIME     NOT NULL
  sync_version  INTEGER      DEFAULT 0
```

### 4.2 questions 表（改：加 user_id）
```text
questions
  ... (现有字段不变)
  user_id       INTEGER  (新增, 默认 0=系统/单用户)
  # 建议：加 user_id 索引，建外键 users.id（ondelete CASCADE）
```
> **兼容性**：为兼容现有单用户数据（user_id 缺失/为 0），查询时 `user_id = 当前用户 OR user_id = 0`，避免历史数据丢失。

---

## 5. 接口设计

统一前缀 `/api/auth`：

| 方法 | 路径 | 说明 | 请求 | 响应 |
|---|---|---|---|---|
| GET | `/api/auth/captcha` | 获取算术验证码 | — | `{captcha_id, image_base64, image_mime, ttl}` |
| POST | `/api/auth/register` | 注册（需验证码） | `{username, password, display_name?, captcha_id, captcha_answer}` | `{id, username, display_name, created_at}` |
| POST | `/api/auth/login` | 登录（失败限流） | `{username, password}` | `{access_token, token_type:"bearer", user:{...}}` |
| GET | `/api/auth/me` | 当前用户 | Header `Authorization: Bearer <token>` | `{id, username, display_name, created_at}` |
| POST | `/api/auth/change-password` | 修改密码（需登录） | `{old_password, new_password}` | `{ok: true}` |

**人机验证 / 防滥用**：
- **注册需算术验证码**：`GET /api/auth/captcha` 返回一张含算术题（PIL 渲染 + 干扰线/噪点）的 PNG 图片（base64）与 `captcha_id`；注册时提交答案，**单次有效、5 分钟过期**，防批量注册。
- **登录失败限流**：同一「用户名」或「IP」连续错误达 5 次，锁定 10 分钟，期间返回 429；成功后清除记录，防暴力破解。

**鉴权**：
- `/api/auth/me`、`/api/auth/change-password` 通过 `Depends(get_current_user)` 强制登录，缺失/非法 token 返回 401 `{"detail": "未认证或登录已过期"}`。
- `/api/questions/*` 通过 `Depends(get_optional_user)` 可选鉴权（向后兼容，见 §3 决策说明）。

### 已接入 user_id 过滤的现有接口
- `POST /api/questions`（创建时写 user_id）
- `GET /api/questions`（按 user_id 过滤：`user_id=当前 OR user_id=0`）
- `PATCH /api/questions/{id}`（校验归属，非本人/非共享 -> 404）
- `DELETE /api/questions`（校验归属）
- `POST /api/questions/batch-move`（校验归属）
- `GET /api/questions/{id}`（校验归属）

---

## 6. 目录 / 文件改动

```
backend/app/
├── core/
│   ├── config.py            # 已加 JWT_SECRET / JWT_EXPIRE_DAYS / TOKEN_ALG
│   ├── errors.py            # (新增) ServiceError 公共异常（question/auth 共用）
│   └── security.py          # (新增) pbkdf2 密码哈希 + 纯标准库 HS256 JWT
├── db/
│   ├── models.py            # 已加 User 模型 + Question.user_id 列
│   └── init_db.py           # 建表 + 轻量迁移（给已存在库补 user_id 列）
├── schemas/
│   └── auth.py              # (新增) RegisterIn/LoginIn/ChangePasswordIn/UserOut/TokenOut
├── services/
│   ├── question_service.py  # 各方法加 user_id 归属过滤（改）
│   └── auth_service.py      # (新增) 注册/登录/me/改密业务逻辑
├── api/
│   ├── auth_routes.py       # (新增) /api/auth/* 路由
│   ├── deps.py              # 已加 get_current_user / get_optional_user / current_user_id
│   └── question_routes.py   # 各接口接入可选鉴权 + user_id 过滤（改）
```

> **依赖**：零新增。密码哈希用标准库 `hashlib.pbkdf2_hmac`，JWT 用标准库 `hmac` + `base64` 自实现 HS256，**不需要** PyJWT / bcrypt。
> JWT 密钥：`.env` 未配置 `JWT_SECRET` 时，首次启动自动生成并持久化到 `data/.jwt_secret`（重启不失效）；生产可在 `.env` 显式配置强随机值。

---

## 7. 实施顺序

1. [x] 抽 `core/errors.py`（ServiceError 公共化，question_service 复用）
2. [x] 配置：`config.py` 加 `JWT_SECRET` / `JWT_EXPIRE_DAYS` / `TOKEN_ALG`
3. [x] 数据层：`models.py` 加 `User` 模型 + `Question.user_id` 列；`init_db` 建表 + 轻量迁移补列
4. [x] 安全工具：`core/security.py`（pbkdf2 哈希 + 标准库 HS256 JWT）
5. [x] 业务 + schema：`auth_service.py` + `schemas/auth.py`
6. [x] 路由：`auth_routes.py`（register/login/me/change-password）
7. [x] 鉴权依赖：`deps.py` 加 `get_current_user` / `get_optional_user`
8. [x] 接入现有接口：`question_routes.py` + `question_service.py` 加 user_id 过滤
9. [x] 测试：本地启动 → 注册/登录 → 用 token 增删改查 → 验证用户隔离（全部通过）

---

## 8. 验收标准
- [x] `POST /api/auth/register` 创建用户成功，密码以哈希存储（非明文）
- [x] 重复用户名注册返回 409
- [x] `POST /api/auth/login` 正确密码返回 JWT；错误密码返回 401
- [x] `/api/auth/me` 无 token / 非法 token 返回 401
- [x] 用户 A 登录看不到用户 B 的错题，且无法修改/删除 B 的题（数据隔离）
- [x] 密码长度 / 强度校验生效
- [x] 修改密码后旧密码失效、新密码可登录

---

## 9. 风险与注意
- **数据迁移**：历史单用户数据 `user_id` 为空 → 查询用 `user_id = 当前 OR user_id = 0` 兼容；`init_db` 对已存在库自动补 `user_id` 列（幂等）。
- **JWT_SECRET**：.env 未配置时自动生成并持久化到 `data/.jwt_secret`（重启不失效）；生产建议在 `.env` 显式配置强随机值。
- **依赖**：验证码用 Pillow 渲染图片（requirements 已有，无新增包）；密码哈希/JWT 用标准库（pbkdf2 / HS256）。
- **性能**：SQLite + JWT 单机足够小规模用户；pbkdf2 26 万次迭代在轻量 CPU 上每次登录约几十毫秒，可接受。
- **检索隔离**：同类题匹配（`/api/retrieval/match`、analyze 的 similar_matches）已按 `user_id` 隔离——登录用户只匹配本人 + 共享题，匿名只匹配共享题；向量库 metadata 携带 `user_id`，启动时自动重索引历史数据补齐归属。ChromaDB 用 `$or` 过滤、内存索引用等值过滤，两路径语义一致。
- **内存态限制**：验证码答案与登录限流计数存**进程内内存**——单进程 uvicorn 有效；若改多 worker 需换共享存储（如 Redis）。
- **手机端**：前端需加登录页 / 存 token / 请求头带 token / 展示验证码（本计划仅规划后端，前端为后续工作）。

---

## 10. 后续扩展（本计划之外）
- 手机号 / 微信 / 邮箱第三方登录
- 验证码、找回密码
- RBAC 角色权限
- 多设备同步（已预留 sync_version）
- 用户量大时迁移到独立 MySQL / PostgreSQL

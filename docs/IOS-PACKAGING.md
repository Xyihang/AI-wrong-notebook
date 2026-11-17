# iOS / Android 打包教程（AI 错题本）

> 目的：把这个项目交给一台 **Mac** 电脑（或让你朋友电脑上的 AI 照着做）完成 **iOS 打包**。
> 说明：Android 的 release APK 已经能构建；本项目主要补齐 iOS。
> 安全：本 ZIP 已剔除 `.env`、签名密钥、SSH 私钥、数据库等敏感文件，**不含任何密钥**。

---

## 0. 先决条件（必须在 macOS 上）

| 需要 | 说明 |
|---|---|
| **macOS** | iOS 只能由 macOS + Xcode 构建；Windows 无法 `flutter build ios` |
| **Xcode** | App Store 下载，首次启动同意协议并装 Command Line Tools（`xcode-select --install`） |
| **CocoaPods** | `sudo gem install cocoapods` 或 `brew install cocoapods` |
| **Flutter SDK** | 建议 3.4x；`flutter --version` 确认可用 |
| **Apple ID** | 只装自己手机：免费 Apple ID 即可（证书 7 天）；TestFlight/上架需 **付费 Apple Developer 账号** |

检查：
```bash
flutter doctor -v
# 确认 iOS toolchain / CocoaPods / Xcode 均打勾
```

---

## 1. 解压与依赖

```bash
cd frontend
flutter pub get
cd ios && pod install --repo-update && cd ..
```

> 若 `pod install` 报错，多半是 Xcode 版本太旧或 `platform :ios` 不匹配；本项目已在 `ios/Podfile` 固定 **iOS 13.0**。

---

## 2. 配置签名（Xcode）

1. 打开 **`frontend/ios/Runner.xcworkspace`**（注意是 `.xcworkspace`，不是 `.xcodeproj`）。
2. 左侧选中 **Runner** target → **Signing & Capabilities**：
   - 勾选 **Automatically manage signing**
   - **Team** 选你自己的 Apple 账号团队
   - **Bundle Identifier** 当前是 `com.xyihang.aiwrongnotebook`；若与你的团队/账号冲突，改成你自己的（如 `com.你的名字.aiwrongnotebook`）并同步到 `project.pbxproj`。
3. 连接 iPhone（需在手机上「信任」此电脑）。

---

## 3. 后端地址（App 启动时自动获取）

App 每次启动会从**远程配置仓库**读取后端地址（换服务器不用重新打包）：

- 仓库：`https://github.com/Xyihang/ai-wrong-backend-config`
- 文件：`backend-config.json`，内容形如 `{ "apiBaseUrl": "http://8.213.136.134/api" }`
- 拉取顺序：GitHub API → Gitee raw → GitHub raw；失败时用本地缓存/打包默认值。

**当前线上后端**：`http://8.213.136.134/api`
（腾讯云轻量·韩国，Caddy 80 端口反代到本机 8000；原 HTTPS 方案因国内网络对该 IP 的
TLS 握手会被重置而暂时改为 HTTP。）

> 构建时仍可用 `--dart-define=API_BASE_URL=...` 指定兜底地址（远程配置失败时使用）。

### iOS 走 HTTP 必须加 ATS 例外（否则所有请求失败）

在 `frontend/ios/Runner/Info.plist` 的 `<dict>` 中加入：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

> 仅内测可用；上架前建议买域名改回 HTTPS，并删除该例外。

### 真机调试运行
```bash
flutter run --release \
  --dart-define=API_BASE_URL=http://8.213.136.134/api
```

### 生成 ipa（推荐）
```bash
flutter build ipa --release \
  --dart-define=API_BASE_URL=http://8.213.136.134/api
# 产物在 build/ios/ipa/*.ipa
```
也可以：Xcode 打开 workspace → 顶部选 **Any iOS Device** → **Product > Archive** → 分发（Development / TestFlight）。

---

## 4. 后端 HTTPS 部署（可选，推荐后续启用）

> **当前线上状态**：服务器为「腾讯云轻量·韩国」，后端 uvicorn 监听 `127.0.0.1:8000`，
> Caddy 在 **80 端口做纯 HTTP 反代**（`http://8.213.136.134/api`）。
> 由于国内网络对这台机器的 TLS 握手会被重置，暂用 HTTP；等买到域名后按下述方式切回 HTTPS，
> 只需修改远程配置仓库里的 `apiBaseUrl`，**App 不用重新打包**。

后端是 FastAPI（`uvicorn app.main:app --host 0.0.0.0 --port 8000`），**不要直接把 8000 暴露公网**，在它前面加一层 HTTPS 反代。

### 方案 A：Caddy（最省事，自动申请证书）
`/etc/caddy/Caddyfile`：
```
你的后端域名 {
    encode gzip
    reverse_proxy 127.0.0.1:8000
}
```
```bash
sudo systemctl reload caddy
```
浏览器访问 `https://你的后端域名/api/health` 应返回 `{"status":"ok",...}`。

### 方案 B：Nginx + certbot
```nginx
server {
    listen 443 ssl;
    server_name 你的后端域名;
    # ssl_certificate / ssl_certificate_key 由 certbot 生成
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
```bash
sudo certbot --nginx -d 你的后端域名
```

### 后端环境变量
```bash
cp backend/.env.example backend/.env
# 编辑 backend/.env：填 LLM_API_KEY / LLM_BASE_URL / LLM_MODEL / VISION_MODEL
# REGISTER_ENABLED / DEFAULT_ACCOUNTS 按需
```
> ⚠️ `.env` **不要提交到任何仓库**。

---

## 5. 常见问题

| 现象 | 处理 |
|---|---|
| `pod install` 失败 | `sudo gem install cocoapods` 后重试；或在 `ios/` 执行 `pod repo update` |
| 签名报错 "requires a development team" | Xcode → Signing 里选 Team |
| iOS 上网络请求全失败 | 后端地址不是 HTTPS，或域名证书无效 |
| 通知不弹 | 已加 `UNUserNotificationCenter` delegate；仍不行检查系统通知权限 |
| 相机/相册无权限弹窗 | 已在 Info.plist 配 `NSCameraUsageDescription` / `NSPhotoLibraryUsageDescription` / `NSPhotoLibraryAddUsageDescription` |
| App 图标不对 | `cd frontend && dart run flutter_launcher_icons`（配置已在 pubspec：android/ios 均 true） |

---

## 6. Android（顺带）

```bash
cd frontend
flutter build apk --release \
  --dart-define=API_BASE_URL=https://你的后端域名/api
```
> Android 原签名方案依赖 `android/key.properties` + `upload-keystore.jks`，这两者**不在本 ZIP 内**（已剔除）。
> 若只是想装到手机测试，可直接用默认 debug 签名：`flutter build apk --debug`。
> 若要正式 release 签名，需自行生成 keystore 并配置 `key.properties`。

---

## 7. 交付说明
- 本 ZIP 包含：`backend/`、`frontend/`、`docs/`、`README.md`、`LICENSE`。
- 已剔除：`backend/.env`、`backend/data/`、`frontend/android/key.properties`、`*.jks`、`*.pem`、构建产物（`build/`、`.dart_tool/`、`.gradle/`）、SDK（`android-sdk/`、`platform-tools/`）与大文件（APK/模型权重）。
- 若朋友电脑上的 AI 需要自动化：可直接让它执行本文件第 1–3 节的命令，并把 `API_BASE_URL` 换成实际 HTTPS 域名。

---

## 8. 许可证
本项目采用 **PolyForm Noncommercial License 1.0.0**（禁止商用），详见 `LICENSE`。

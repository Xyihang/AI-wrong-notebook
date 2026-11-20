# Release Checklist

> 用于每次发版：先在本地跑通，再打 tag、发 GitHub Release、更新配置仓库。

## 1. 版本号
- 语义化：`0.x.y`（当前 pre-1.0）
- 同步修改：`frontend/pubspec.yaml` 的 `version:`、`CHANGELOG.md` 顶部

## 2. 构建
```bash
cd frontend
flutter clean && flutter pub get
flutter analyze                 # 要求 0 error
flutter test                    # 关键测试全绿
flutter build apk --release --split-per-abi   # 或单包 --release
```
产物：`frontend/build/app/outputs/flutter-apk/app-release.apk`

## 3. 打 tag
```bash
git tag -a v0.9.0 -m "v0.9.0 — design tokens + liquid glass"
git push origin v0.9.0
```

## 4. GitHub Release（网页操作）
- Tag: `v0.9.0`
- Title: `AI 错题本 Pro v0.9.0 · Design Tokens & Liquid Glass`
- 附件：`app-release.apk`（改名 `ai-wrong-notebook-v0.9.0.apk`）
- 正文模板：
```markdown
### Highlights
- 全新设计 Token 体系 + 5 个核心页面重做
- 液态玻璃导航层（顶栏随滚动渐变模糊、底部浮动 Dock）
- 深色模式调校；6 套页面背景

### Install
下载底部 APK，安装后首次启动完成 3 步配置（或选择游客模式）。

### Notes
- 需要 Android 10+；iOS 需自行签名构建
- 非商业许可：见 LICENSE
```

## 5. 发布后
- [ ] 更新 `Xyihang/ai-wrong-backend-config`（若换服务器）
- [ ] README 顶部截图/GIF 是否需要更新
- [ ] 发帖：V2EX「分享创造」/ 少数派 / 即刻 / B 站 / 掘金
- [ ] 收集反馈 → 建 Issue 模板（bug / feature）

## 6. 回滚
```bash
git revert <bad-commit>
# 或重新发一个 patch 版本（推荐，不删已有 Release）
```

# GitHub 多端构建说明

仓库通过 [`.github/workflows/release.yml`](../.github/workflows/release.yml) 构建多端发布资源，并在发布标签时推送后端 Docker 镜像。

## 触发方式

### 手动构建

1. 打开 GitHub 仓库的 `Actions` 页面。
2. 选择“多端构建与发布”。
3. 点击 `Run workflow`。
4. 填写客户端默认连接的后端地址，例如 `https://reader.example.com`。

手动构建完成后，在本次工作流运行页面的 `Artifacts` 区域下载产物。产物默认保留 14 天。

### 创建 Release

推送以 `v` 开头的标签会执行完整构建，并在所有平台成功后自动创建 GitHub Release：

```powershell
git tag v1.0.0
git push origin v1.0.0
```

标签构建默认使用 `http://localhost:8080` 作为客户端后端地址。如需指定线上地址，建议先手动构建验证，或按部署环境修改工作流默认值。

## 构建产物

| 产物 | 内容 |
| --- | --- |
| `qingyue-backend.jar` | JDK 21 后端程序 |
| `private-reader-web.tar.gz` | Flutter Web 静态资源 |
| `private-reader-android-universal.apk` | Android 通用 APK |
| `private-reader-android-arm64-v8a.apk` | Android ARM64 APK |
| `private-reader-android-armeabi-v7a.apk` | Android ARMv7 APK |
| `private-reader-android-x86_64.apk` | Android x86_64 APK，主要用于模拟器 |
| `private-reader-android.aab` | Android App Bundle |
| `private-reader-windows-x64.zip` | Windows x64 客户端 |
| `private-reader-linux-x64.tar.gz` | Linux x64 客户端 |
| `private-reader-macos.zip` | macOS Universal App，兼容 Apple Silicon 与 Intel |
| `private-reader-macos-arm64.zip` | macOS Apple Silicon App |
| `private-reader-macos-x86_64.zip` | macOS Intel App |

## Docker Hub 镜像

推送以 `v` 开头的标签时，工作流会构建并推送后端和 Flutter Web 前端的 `linux/amd64`（x86_64）和 `linux/arm64` 两个版本到 Docker Hub，并分别合并为多架构标签：

```text
chen584991126/qingyue-backend:<Git 标签>
chen584991126/qingyue-backend:latest
chen584991126/qingyue-web:<Git 标签>
chen584991126/qingyue-web:latest
```

例如推送 `v0.0.1-beta3` 后，可直接拉取：

```powershell
docker pull chen584991126/qingyue-backend:v0.0.1-beta4
docker pull chen584991126/qingyue-web:v0.0.1-beta4
```

部署机只需要 Docker；Docker 会自动选择与当前 CPU 匹配的镜像。前端镜像包含 Nginx，并会将 `/api/` 请求代理到 Compose 网络中的 `backend:8080`，因此浏览器只需访问前端端口。为了让工作流能够推送镜像，需要在 GitHub 仓库的 `Settings → Secrets and variables → Actions` 新增以下 Secrets：

- `DOCKERHUB_USERNAME`：`chen584991126`。
- `DOCKERHUB_TOKEN`：Docker Hub 创建的 Access Token；不要填写账户密码。

创建 Token 的入口：登录 Docker Hub 后，点击右上角头像 → `My Account` → `Personal access tokens` → `Generate new token`，权限选择 `Read & Write`。Token 只会完整显示一次，请立即复制。

保存到 GitHub 的入口：仓库页面 → `Settings` → `Secrets and variables` → `Actions` → `New repository secret`。分别创建 `DOCKERHUB_USERNAME`（值为 `chen584991126`）和 `DOCKERHUB_TOKEN`（粘贴刚复制的 Token）。

生产环境建议固定使用版本标签，验证无误后再选择跟随 `latest`。

## 签名说明

- 当前 Android 工程在没有正式密钥时使用调试密钥签署 Release 构建，适合内部安装验证，不适合提交应用商店。
- macOS 构建未配置 Apple Developer 签名和公证，适合内部验证；对外分发前需配置证书、公证和应用标识。
- iOS 必须配置 Apple 签名证书和描述文件，因此未加入默认公开构建矩阵。
- Windows 当前生成免安装 ZIP；如需 MSIX 或代码签名，可在此工作流基础上增加证书 Secret 和打包步骤。

## 平台架构

- Windows 使用 GitHub 托管的 x64 Runner。Flutter 不支持 Windows 32 位 x86；Windows ARM64 需要单独的 ARM64 Runner。
- Linux 默认构建 x64。Linux ARM64 可通过 ARM64 Runner 增加独立任务。
- macOS Release 默认构建 Universal App，并额外拆分 ARM64 与 x86_64 两个独立安装包。
- Web 产物与处理器架构无关。

## API 地址

`API_BASE_URL` 会在 Flutter 编译时写入客户端。浏览器和客户端运行后不会自动改用新的地址，因此正式发布前应填写可公开访问的 HTTPS 后端地址。

# Private Reader Mobile

Flutter 重建后的移动端工程，首期目标：

- Android 手机与平板优先
- 统一正文阅读器仅支持 `TXT / EPUB`
- 登录、书架、阅读器、目录、批注、书签、阅读设置、账号页
- `PDF` 与未生成统一正文的书在 APP 内提示回到桌面 Web 阅读

## 工程结构

- `lib/app`：应用入口、路由、壳层导航
- `lib/data`：DTO、HTTP 客户端、会话存储、离线队列、同步协调器
- `lib/features/auth`：登录与会话恢复
- `lib/features/bookshelf`：书架与封面入口
- `lib/features/reader`：统一正文阅读器、目录、笔记、设置
- `lib/features/profile`：账号页与全局设置入口
- `lib/shared`：主题 token、配置与响应式常量

## 依赖说明

当前固定依赖：

- `flutter_riverpod`
- `go_router`
- `dio`
- `flutter_secure_storage`
- `shared_preferences`
- `sqflite`
- `connectivity_plus`

## 本地运行

1. 先启动后端 `http://localhost:8080`
2. 准备 Flutter / Android 环境
3. 进入 `mobile/`
4. 拉依赖并运行

```powershell
$env:JAVA_HOME='C:\Users\mini2436\Tools\temurin21\jdk-21.0.10+7'
$env:PATH='C:\Users\mini2436\Tools\flutter-sdk\flutter\bin;' + $env:JAVA_HOME + '\bin;' + $env:PATH

# 仅在需要下载 Flutter / Gradle 依赖时设置代理
$env:HTTP_PROXY='http://127.0.0.1:10808'
$env:HTTPS_PROXY='http://127.0.0.1:10808'
$env:GRADLE_OPTS='-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=10808 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=10808'

flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

说明：

- Android 模拟器默认使用 `http://10.0.2.2:8080`
- 真机调试时请改成宿主机局域网地址，例如 `http://192.168.1.10:8080`
- 代理配置不要写进仓库，只在本机终端里临时设置

## 校验命令

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

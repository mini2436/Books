# Private Reader Mobile

Flutter 重建后的移动端工程，首期目标：

- Android 手机与平板优先
- 统一正文阅读器支持 `TXT / EPUB / FB2 / MOBI`，CBZ 使用统一图片分页，PDF 使用内置 PDF 阅读器
- 登录、书架、阅读器、目录、批注、书签、阅读设置、账号页
- 支持整本下载、断网冷启动和离线阅读；离线期间的进度、书签与批注会在联网后自动同步
- 未生成统一正文且非 PDF 的书在 APP 内提示回到桌面 Web 阅读

## 工程结构

- `lib/app`：应用入口、路由、壳层导航
- `lib/data`：DTO、HTTP 客户端、会话存储、离线队列、同步协调器
- `lib/data/services/offline_book_cache_service.dart`：按用户隔离的离线书库、章节、图片资源和 PDF 文件缓存
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

## 离线阅读

联网时点击书籍封面上的下载按钮，客户端会缓存书籍元数据、封面、正文或 PDF 原文件、章节图片、批注、书签和当前进度。已下载的书籍支持断网启动并直接进入阅读器；离线期间产生的阅读记录会先写入本地数据库，再进入同步队列，恢复网络后自动推送到服务器。

离线书库按当前登录用户隔离。删除单本离线下载只清理本地文件，不会删除服务器书架中的书籍。

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

## Web 端

Web 端复用 Pad 的响应式布局。书架、批注、后台、个人设置、PDF 阅读均使用同一套界面；TXT / EPUB / FB2 / MOBI / CBZ 在浏览器中使用纯 Flutter 统一阅读视图，保留点击翻页、目录、书签、批注和阅读设置，双栏排版暂时降级为居中的单栏阅读。

本地运行：

```powershell
flutter run -d edge --dart-define=API_BASE_URL=http://localhost:8080
```

构建静态产物：

```powershell
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://reader-server:8080
```

产物位于 `build/web/`，可由任意静态 Web 服务器托管。浏览器访问地址与 API 地址不同时，后端需要允许对应来源；HTTPS 页面必须使用 HTTPS API。

Web 构建包含自定义 PWA Service Worker。用户成功打开一次页面后，首页、Flutter 运行时、字体和图标会保存为应用壳缓存；服务器不可访问时，刷新或重新打开页面仍可进入离线书库。API 响应和图书数据不会进入应用壳缓存，图书、进度和批注仍由 IndexedDB 按服务器与用户隔离保存。Service Worker 仅能在 HTTPS 或 `localhost`/`127.0.0.1` 安全上下文中启用，局域网 IP 的 HTTP 地址需要先配置 HTTPS。

Web 端离线同步队列存放在浏览器本地存储中。图书和头像上传会在浏览器中读取文件内容，因此上传大文件时会占用相应的浏览器内存。

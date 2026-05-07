# 移动端 Flutter 依赖清单

## 1. 适用范围

本文对应仓库中的 `mobile/` Flutter 工程，基于当前代码与锁定依赖生成。

- 当前主交付目标是 Android 手机与平板
- 仓库内目前存在 `android/`，但尚未创建 `ios/`
- 因此“移动端”现阶段可视为 Android-first

生成依据：

- `mobile/pubspec.yaml`
- `mobile/pubspec.lock`
- `mobile/.flutter-plugins-dependencies`
- `mobile/lib/**`

## 2. 运行时基线

| 项 | 当前值 |
| --- | --- |
| Dart SDK 约束 | `^3.11.4` |
| Flutter 解析版本 | `3.41.6` |
| App 包名 | `private_reader_mobile` |
| 版本号 | `1.0.0+1` |

## 3. 直接依赖

| 依赖 | `pubspec.yaml` 约束 | `pubspec.lock` 锁定版本 | 作用 | 主要落点 |
| --- | --- | --- | --- | --- |
| `flutter` | SDK | SDK | Flutter 应用基础运行时 | `mobile/lib/**` |
| `cupertino_icons` | `^1.0.8` | `1.0.9` | iOS 风格图标基础包 | 全局 UI 可用，当前非核心依赖 |
| `flutter_riverpod` | `^2.6.1` | `2.6.1` | 状态管理、Provider 注入 | `mobile/lib/app/app.dart`、`mobile/lib/app/app_shell.dart`、各 `features/**` |
| `go_router` | `^16.2.1` | `16.3.0` | 路由与导航壳层 | `mobile/lib/app/router.dart` |
| `dio` | `^5.9.0` | `5.9.2` | HTTP 请求、鉴权、上传 | `mobile/lib/data/services/api_client.dart` |
| `path` | `^1.9.1` | `1.9.1` | 路径拼接、文件名提取 | `mobile/lib/data/services/api_client.dart`、`mobile/lib/data/services/offline_queue_service.dart` |
| `flutter_secure_storage` | `^9.2.4` | `9.2.4` | 安全存储会话、令牌 | `mobile/lib/data/services/session_storage.dart` |
| `shared_preferences` | `^2.5.3` | `2.5.5` | 保存阅读偏好、服务器配置 | `mobile/lib/data/services/settings_storage.dart`、`mobile/lib/data/services/server_config_storage.dart` |
| `sqflite` | `^2.4.2` | `2.4.2` | 离线同步队列、本地数据库 | `mobile/lib/data/services/offline_queue_service.dart` |
| `connectivity_plus` | `^7.0.0` | `7.1.1` | 网络状态探测，辅助离线同步 | `mobile/lib/data/services/sync_coordinator.dart` |
| `file_picker` | `^10.3.2` | `10.3.10` | 选择本地书籍文件上传 | `mobile/lib/features/admin/admin_center_screen.dart` |
| `webview_flutter` | `^4.13.1` | `4.13.1` | 阅读器 HTML 渲染与交互桥接 | `mobile/lib/features/reader/widgets/reader_html_view.dart` |

## 4. 开发依赖

| 依赖 | 约束 | 锁定版本 | 作用 |
| --- | --- | --- | --- |
| `flutter_test` | SDK | SDK | Widget / 单元测试 |
| `flutter_lints` | `^6.0.0` | `6.0.0` | Flutter 官方静态检查规则 |

当前仓库可见测试文件：

- `mobile/test/reader_palette_test.dart`

## 5. Android 平台子插件

以下插件并非都直接写在 `pubspec.yaml` 中，但会在 Android 构建期被实际解析和注册：

| Android 子插件 | 锁定版本 | 来源 | 说明 |
| --- | --- | --- | --- |
| `connectivity_plus` | `7.1.1` | 直接依赖 | Android 网络状态能力 |
| `file_picker` | `10.3.10` | 直接依赖 | Android 文件选择 |
| `flutter_plugin_android_lifecycle` | `2.0.34` | `file_picker` 间接依赖 | Android 生命周期桥接 |
| `flutter_secure_storage` | `9.2.4` | 直接依赖 | Android 安全存储封装 |
| `shared_preferences_android` | `2.4.23` | `shared_preferences` 间接依赖 | Android 偏好存储实现 |
| `sqflite_android` | `2.4.2+3` | `sqflite` 间接依赖 | Android SQLite 实现 |
| `webview_flutter_android` | `4.11.0` | `webview_flutter` 间接依赖 | Android WebView 实现 |
| `path_provider_android` | `2.3.1` | 间接依赖 | Android 本地路径解析 |
| `jni` | `1.0.0` | `path_provider_android` 间接依赖 | JNI 基础桥接 |
| `jni_flutter` | `1.0.1` | `path_provider_android` 间接依赖 | Flutter/JNI 集成桥接 |

## 6. 与当前业务能力的对应关系

| 业务能力 | 依赖组合 |
| --- | --- |
| 登录、刷新令牌、后台管理接口 | `dio` |
| 会话安全保存 | `flutter_secure_storage` |
| 阅读主题、字号、行高、服务器地址配置 | `shared_preferences` |
| 离线待同步操作队列 | `sqflite` + `path` |
| 网络恢复后同步补偿 | `connectivity_plus` |
| 管理端上传本地图书 | `file_picker` + `dio` + `path` |
| HTML 阅读器、批注桥接、分页交互 | `webview_flutter` |
| 全局状态与页面共享数据 | `flutter_riverpod` |
| 登录页 / 书架 / 阅读器 / 后台路由切换 | `go_router` |

## 7. 当前结论

这套依赖已经覆盖了当前移动端的核心能力：

- 认证与会话持久化
- 阅读偏好设置
- 离线优先同步基础设施
- 管理端文件上传
- WebView 阅读器
- Android 手机与平板导航壳层

按当前代码状态看，暂时没有发现“必须立刻补充”的 Flutter 基础依赖缺口。

## 8. 后续维护建议

- 若仅升级功能包，优先同步更新 `mobile/pubspec.yaml` 与 `mobile/pubspec.lock`
- 若新增移动端原生能力，例如权限申请、推送、下载管理，再单独补充依赖评估
- 若后续补齐 `ios/` 工程，建议基于 `mobile/.flutter-plugins-dependencies` 再整理一版 iOS 子插件清单
- 建议把本文作为移动端依赖变更时的同步文档

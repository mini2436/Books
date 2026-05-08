# Private Reader

[English README](README.md)

Private Reader 是一个可自托管的多用户电子书平台，当前包括：

- 面向 JVM 与 GraalVM Native Image 的 Kotlin + Spring Boot 后端
- 采用编译期集成方式的图书格式扫描与插件体系
- 以 Flutter 为核心的 App 客户端，当前优先支持 Android 手机与平板，后续将向 Web/Desktop 多端收敛
- 一个已停止主线投入、仅保留作迁移参考的旧版 Next.js Web 客户端
- 支持批注、书签、阅读进度的离线优先同步基础能力

## 仓库结构

- `backend/`：Spring Boot 多模块后端工程
- `mobile/`：Flutter 应用主工程
- `web/`：已停用的旧版 Next.js 前端，仅保留作为迁移参考
- `infra/`：基础设施说明、SQL 脚本与辅助脚本
- `docs/`：功能、架构、运行与迁移相关文档
- `docker-compose.yml`：本地开发所需中间件栈

## 当前产品方向

- 第一阶段主交付基线是 `backend/ + mobile/`
- 原 `web/` 端不再承接新功能开发
- 下一阶段会以 Flutter 为统一前端基座，逐步覆盖 Mobile、Web、Desktop

## 快速开始

1. 先通过 Docker Compose 启动本地中间件。
2. 在 `backend/` 中使用 Gradle Wrapper 启动后端服务。
3. 在 `mobile/` 中通过 Flutter 运行 App，并传入 `API_BASE_URL`。
4. 将 `web/` 视为只读参考目录，不再作为主交付端。

## 文档入口

- [运行文档](docs/运行文档.md)
- [接口文档](docs/接口文档.md)
- [第一阶段功能总览](docs/第一阶段功能总览.md)
- [第一阶段详细功能文档](docs/第一阶段详细功能文档.md)
- [后端架构文档](docs/后端架构文档.md)
- [Flutter应用架构文档](docs/Flutter应用架构文档.md)
- [Web端停用与Flutter多端迁移计划](docs/Web端停用与Flutter多端迁移计划.md)
- [基础设施说明](infra/README.md)

## 中间件与数据库

本地开发默认使用 [docker-compose.yml](docker-compose.yml) 提供 PostgreSQL、Redis、RabbitMQ，因此通常不需要额外手工安装这些中间件。

数据库相关脚本位于：

- [infra/database/001_schema.sql](infra/database/001_schema.sql)
- [infra/database/010_seed_dev.sql](infra/database/010_seed_dev.sql)

## 后端构建说明

后端基于 Spring Boot 3，并遵循较明确的 AOT / Native 友好约束：

- 不依赖运行时动态插件发现
- 使用编译期模块注册来接入图书格式插件
- DTO、SQL 与模块边界显式维护
- 同时保留 JVM 与 Native Image 两条构建路径

## 补充说明

- 当前核心功能、详细功能与架构信息以 `docs/` 下文档为准。
- 若要继续推进浏览器端或桌面端，请优先沿 Flutter 多端路线演进，而不是继续扩展旧版 `web/` 工程。

# Private Reader

[中文说明](/C:/Users/MINI2436/PROJRCT/AI/Books/README.zh-CN.md)

Private Reader is a self-hosted multi-user ebook platform with:

- A Kotlin + Spring Boot backend designed for JVM and GraalVM native image builds
- A plugin-based book format scanner with compile-time integrated plugins
- A Flutter app client for Android-first phone and tablet reading, with planned Web/Desktop convergence
- A deprecated legacy Next.js web client kept only as migration reference
- Offline-first sync for annotations, bookmarks, and reading progress

## Workspace layout

- `backend/` Spring Boot multi-module project
- `web/` deprecated legacy Next.js client, no longer the primary delivery target
- `mobile/` Flutter app
- `infra/` infrastructure notes, SQL scripts, and helper scripts
- `docker-compose.yml` local development stack

## Quick start

1. Start infrastructure with Docker Compose.
2. Build and run the backend using the Gradle wrapper in `backend/`.
3. Run the Flutter app against the backend using `--dart-define=API_BASE_URL=...`.
4. Treat `web/` as read-only reference code during the Flutter Web/Desktop migration period.

## Documentation

- [运行文档](/C:/Users/mini2436/Project/Ai/Books/docs/运行文档.md)
- [接口文档](/C:/Users/mini2436/Project/Ai/Books/docs/接口文档.md)
- [第一阶段功能总览](/C:/Users/MINI2436/PROJRCT/AI/Books/docs/第一阶段功能总览.md)
- [第一阶段详细功能文档](/C:/Users/MINI2436/PROJRCT/AI/Books/docs/第一阶段详细功能文档.md)
- [后端架构文档](/C:/Users/MINI2436/PROJRCT/AI/Books/docs/后端架构文档.md)
- [Flutter应用架构文档](/C:/Users/MINI2436/PROJRCT/AI/Books/docs/Flutter应用架构文档.md)
- [Web端停用与Flutter多端迁移计划](/C:/Users/MINI2436/PROJRCT/AI/Books/docs/Web端停用与Flutter多端迁移计划.md)
- [基础设施说明](/C:/Users/mini2436/Project/Ai/Books/infra/README.md)

## Middleware and database setup

Local development middleware is already defined in [docker-compose.yml](/C:/Users/mini2436/Project/Ai/Books/docker-compose.yml), so PostgreSQL, Redis, and RabbitMQ do not need separate manual installation if Docker is available.

Operator-facing SQL scripts live in:

- [infra/database/001_schema.sql](/C:/Users/mini2436/Project/Ai/Books/infra/database/001_schema.sql)
- [infra/database/010_seed_dev.sql](/C:/Users/mini2436/Project/Ai/Books/infra/database/010_seed_dev.sql)

## Native-ready backend notes

The backend is built with Spring Boot 3 and follows AOT-friendly constraints:

- No runtime plugin loading
- Compile-time module registration for format plugins
- Explicit DTOs and SQL-backed repositories
- Dual build pipeline for JVM and native image outputs

## Current product direction

- Phase 1 delivery is centered on `backend/ + mobile/`.
- New feature development on the legacy `web/` client is stopped.
- The next cross-platform target is to evolve the Flutter app into shared mobile, web, and desktop clients.

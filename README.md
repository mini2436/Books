# Private Reader

Private Reader is a self-hosted multi-user ebook platform with:

- A Kotlin + Spring Boot backend designed for JVM and GraalVM native image builds
- A plugin-based book format scanner with compile-time integrated plugins
- A Next.js web client for reading and administration
- A Capacitor mobile shell that reuses the web reading experience
- Offline-first sync for annotations, bookmarks, and reading progress

## Workspace layout

- `backend/` Spring Boot multi-module project
- `web/` Next.js app shell
- `mobile/` Capacitor shell
- `infra/` infrastructure notes, SQL scripts, and helper scripts
- `docker-compose.yml` local development stack

## Quick start

1. Start infrastructure with Docker Compose.
2. Build and run the backend using the Gradle wrapper in `backend/`.
3. Start the web client with Node.js 20+.
4. Point the mobile shell at the web build or a hosted frontend.

## Documentation

- [运行文档](/C:/Users/mini2436/Project/Ai/Private/docs/运行文档.md)
- [接口文档](/C:/Users/mini2436/Project/Ai/Private/docs/接口文档.md)
- [基础设施说明](/C:/Users/mini2436/Project/Ai/Private/infra/README.md)

Frontend helper script:

- [infra/scripts/build-web.ps1](/C:/Users/mini2436/Project/Ai/Private/infra/scripts/build-web.ps1)

## Middleware and database setup

Local development middleware is already defined in [docker-compose.yml](/C:/Users/mini2436/Project/Ai/Private/docker-compose.yml), so PostgreSQL, Redis, and RabbitMQ do not need separate manual installation if Docker is available.

Operator-facing SQL scripts live in:

- [infra/database/001_schema.sql](/C:/Users/mini2436/Project/Ai/Private/infra/database/001_schema.sql)
- [infra/database/010_seed_dev.sql](/C:/Users/mini2436/Project/Ai/Private/infra/database/010_seed_dev.sql)

## Native-ready backend notes

The backend is built with Spring Boot 3 and follows AOT-friendly constraints:

- No runtime plugin loading
- Compile-time module registration for format plugins
- Explicit DTOs and SQL-backed repositories
- Dual build pipeline for JVM and native image outputs

# Private Reader

> A lightweight, self-hosted reading manager for families.

[中文](README.md) · [Runbook](docs/运行文档.md) · [API documentation](docs/接口文档.md)

Private Reader turns ebooks scattered across computers, NAS storage, and family devices into one private library. An administrator imports and organizes books, while each family member reads with an individual account. Book access, progress, bookmarks, and annotations stay synchronized without handing the household's reading data to a public service.

![Private Reader family bookshelf](docs/screenshots/bookshelf-web.png)

## Highlights

- Shared family library with individual accounts and per-book access control
- EPUB, TXT, and PDF import through compile-time format plugins
- Flutter clients for Web, Windows, and Android/tablets
- Progress, bookmarks, highlights, annotations, and an offline operation queue
- Upload and NAS/directory scanning workflows
- Responsive reader with themes, typography controls, and bundled Chinese fonts
- Administration for books, users, grants, library sources, and scan jobs
- Self-hosted Kotlin/Spring Boot backend backed by PostgreSQL, Redis, and RabbitMQ

## Screenshots

### Reader

![Private Reader web reader](docs/screenshots/reader-web.png)

### Typography and themes

![Private Reader reading settings](docs/screenshots/reader-settings-web.png)

### Annotation center

![Private Reader annotation center](docs/screenshots/annotations-web.png)

## Architecture

```text
Flutter Web / Windows / Android
                │
                ▼
       Kotlin + Spring Boot
         │      │       │
         ▼      ▼       ▼
   PostgreSQL  Redis  RabbitMQ
                │
                ▼
        Local storage / NAS
```

The backend is a Kotlin 2.1 and Spring Boot 3.5 multi-module project. EPUB, TXT, and PDF support is integrated through compile-time plugins. The frontend is a shared Flutter application using Riverpod, GoRouter, and Dio.

## Quick start

Requirements: JDK 21, Flutter, Docker Compose, and the Windows C++ desktop toolchain when building the Windows client.

```powershell
# Infrastructure
docker compose up -d postgres redis rabbitmq

# Backend
cd backend
.\gradlew.bat bootRun

# In another terminal: Web client
cd mobile
flutter pub get
flutter run -d edge --dart-define=API_BASE_URL=http://localhost:8080
```

The API is available at `http://localhost:8080`. On an empty development database, the bootstrap login is `admin` / `admin12345`. Override `APP_BOOTSTRAP_ADMIN_USERNAME` and `APP_BOOTSTRAP_ADMIN_PASSWORD` before deploying the service.

Other clients:

```powershell
# Windows
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8080

# Android emulator
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

For a physical Android device, point `API_BASE_URL` at the host's LAN address.

## Repository layout

- `backend/` — Kotlin/Spring Boot backend
- `mobile/` — shared Flutter client
- `infra/` — database and infrastructure helpers
- `docs/` — design, API, architecture, and runbooks

## Project status

Private Reader is under active development. It is already suitable for small household deployments, but is best kept on a private network with regular backups of both PostgreSQL and the book storage directory.

Bundled font licenses are stored under [`mobile/assets/fonts/`](mobile/assets/fonts/).

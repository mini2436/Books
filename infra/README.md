# Infrastructure Notes

The project keeps its local infrastructure definition and database bootstrap files in this directory.

## Middleware

Development middleware is provided by the root [docker-compose.yml](../docker-compose.yml):

- PostgreSQL 16
- Redis 7
- RabbitMQ 3 with management UI

For local development, you do not need to install these services separately if you use Docker Compose.

## Database scripts

- [001_schema.sql](database/001_schema.sql): operator-facing schema script
- [010_seed_dev.sql](database/010_seed_dev.sql): optional local development seed data

The backend also keeps a runtime copy of the schema in `backend/app/src/main/resources/schema.sql` so Spring Boot can initialize a fresh database automatically in local environments.

## PowerShell helpers

- [start-infra.ps1](scripts/start-infra.ps1): starts PostgreSQL, Redis, and RabbitMQ
- [init-db.ps1](scripts/init-db.ps1): prints commands for applying SQL scripts to PostgreSQL
- [backfill-book-covers.ps1](backfill-book-covers.ps1): builds the backend, starts the required Docker middleware, and uses a temporary Docker backend process to extract missing covers into PostgreSQL.
- [backfill-book-resources.ps1](backfill-book-resources.ps1): extracts EPUB body images referenced by structured content and stores them in PostgreSQL.

Run the cover backfill from the repository root:

```powershell
.\infra\backfill-book-covers.ps1
```

The script is idempotent and skips books that already have a database cover. Use `-Overwrite` to extract every cover again, or `-SkipBuild` when `backend/app/build/libs/app-0.1.0.jar` is already current.

Backfill EPUB body images with:

```powershell
.\infra\backfill-book-resources.ps1
```

This script is also idempotent and supports `-Overwrite` and `-SkipBuild`.

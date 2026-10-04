# Lumenote

Lumenote is a Flutter app for capturing classes and meetings, organizing material into topics, and turning recordings and documents into searchable notes and study activities. The repository includes a Flutter client, a Node.js API, PostgreSQL, and a local Whisper transcription service.

This project is under active development. Self-hosting requires configuring your own Supabase project and service credentials. The included Compose setup does not bundle Supabase. Membership tables and quota enforcement are being prepared, but checkout, payment webhooks, and a production operator console are not implemented. Do not treat the listed plans or limits as an offer for sale.

## What is included

- Flutter clients for Android, iOS, web, Windows, macOS, and Linux.
- Topics and named notes for audio, documents, images, links, and text.
- Audio playback, transcription jobs, timestamped transcripts, summaries, and note chat.
- Study cards and quizzes generated from note content.
- A Node API for authentication checks, content operations, AI/Codex integration, and membership-related endpoints.
- PostgreSQL for API-side records and an optional local Whisper service for transcription.
- Supabase Auth, PostgREST, and Storage integration, configured separately by each operator.

## Repository layout

| Path | Purpose |
| --- | --- |
| `lib/`, `assets/` | Flutter application and visual resources |
| `android/`, `ios/`, `web/`, `windows/`, `macos/`, `linux/` | Flutter platform runners |
| `backend/` | Node.js API and Codex runtime adapter |
| `transcriber/` | Optional local Whisper HTTP service |
| `supabase/migrations/` | SQL migrations for Supabase |
| `docker-compose.yml`, `Dockerfile.web`, `docker/` | Local container deployment |
| `docs/` | Deployment, integration, membership, and distribution notes |

## Requirements

- Flutter SDK compatible with the constraints in [`pubspec.yaml`](pubspec.yaml).
- Node.js 22 for the API container (or a compatible Node.js runtime for local development).
- Docker Compose v2 for the complete local web/API/Whisper stack.
- A Supabase project for Auth, PostgREST, and Storage. Apply the required migrations to your project before use.

## Run the Flutter client

Install dependencies and configure your own Supabase project and API URL using compile-time defines:

```powershell
flutter pub get
flutter run -d chrome `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY `
  --dart-define=LUMENOTE_AI_URL=http://localhost:8787
```

For a mobile or desktop build, use the relevant Flutter device/target and provide the same `--dart-define` values. The Supabase anon/publishable key is intended for client use only with correctly configured Row Level Security (RLS). Never put a service-role key, Codex token, OpenAI key, database password, or webhook secret in Flutter defines, source code, or a client build.

Without Supabase configuration, authentication and server-backed features are unavailable. Set `LUMENOTE_AI_URL` to an address reachable by the user's browser/device; Docker's internal service names such as `lumenote-ai` are not reachable from an external browser.

## Run the local container stack

Create local environment files from the templates, then edit them with your own values:

```powershell
Copy-Item .env.example .env
Copy-Item backend/.env.example backend/.env
```

Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and a unique strong `POSTGRES_PASSWORD` in the root `.env`. Configure the backend's Supabase values and whichever AI/Codex integration you intend to use in `backend/.env`. Keep both local files private; `.env` files are ignored by Git.

```powershell
docker compose up --build
```

The web client is served at `http://localhost:8765` and the API at `http://localhost:8787`. The first Whisper start downloads the selected model and can take time and disk space. CPU transcription resource requirements depend on the model and audio length. For a remote deployment, change `LUMENOTE_AI_URL` to the public HTTPS URL of the API and configure CORS, TLS, storage, backups, and secrets appropriately.

Compose provides PostgreSQL for API-side records; it does **not** provision Supabase Auth, PostgREST, or Storage. See [`docs/deployment-modes.md`](docs/deployment-modes.md) for the deployment boundary and current limitations.

## Database migrations

Review and apply migrations in [`supabase/migrations/`](supabase/migrations/) to your own Supabase project using the Supabase CLI or dashboard. Back up the database first and verify the target project before applying migrations. Compose does not automatically apply these migrations.

## Development checks

```powershell
flutter analyze
flutter test
node --check backend/server.mjs
node --check backend/codex_runtime.mjs
python scripts/check_utf8.py
docker compose config
```

The Flutter analyzer currently reports existing lints in the large application file; review command output rather than assuming a clean analysis. Do not use production accounts, user recordings, or production secrets in tests.

## Security and privacy

- Copy the example environment files and use unique local secrets. Never commit `.env`, credentials, OAuth sessions, signing keys, personal recordings, or user exports.
- Keep `SUPABASE_SERVICE_ROLE_KEY`, `CODEX_TOKEN_ENCRYPTION_KEY`, `OPENAI_API_KEY`, Codex OAuth secrets, database credentials, and payment secrets exclusively on the server/secret manager.
- Configure Supabase RLS and storage policies for your deployment; a client anon key is not a substitute for access policies.
- Use HTTPS outside localhost. The app does not make a private deployment safe merely by obscuring its API URL.
- This repository has not yet had a complete historical secret scan. If any credential was ever committed, revoke/rotate it; deleting it from the latest tree is not enough.

## Branding and redistribution

The app contains both Lumenote and Kuromi-themed branding assets. The Kuromi character/name and related artwork are third-party intellectual property; this repository does not claim ownership or grant redistribution rights for them. Before making a public or commercial release, obtain the required permissions or replace those assets and related branding with material you own or are licensed to redistribute. The application currently references some Kuromi assets directly, so removing the files alone would break builds.

## License status

No `LICENSE` file has been selected or added. Until the project owner chooses and adds a license, public visibility does not grant permission to use, modify, or redistribute this source or its assets. Review code provenance and third-party asset/dependency licenses before selecting a license or publishing.

## Project notes

- [`docs/deployment-modes.md`](docs/deployment-modes.md) explains self-hosted versus hosted operation and the container boundaries.
- [`docs/membership-commerce-plan.md`](docs/membership-commerce-plan.md) is a proposal; it documents that checkout and verified payment webhooks remain future work.
- [`docs/distribution-control-plane.md`](docs/distribution-control-plane.md) describes a future distributor/operator console; it is not an implemented feature set.
- [`docs/openclaw-codex-integration.md`](docs/openclaw-codex-integration.md) describes the Codex runtime approach and its separation from local transcription.

## Contributing

Contributions should include a concise description of the change and relevant test results. Do not include personal data, credentials, copyrighted assets without redistribution rights, or generated build output in pull requests. A contribution guide and project license remain to be chosen.

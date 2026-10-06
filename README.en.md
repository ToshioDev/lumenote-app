<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/branding/lumenote_isotype_dark.png" />
    <source media="(prefers-color-scheme: light)" srcset="assets/branding/lumenote_isotype_light.png" />
    <img src="assets/branding/lumenote_isotype_light.png" width="72" alt="Lumenote mark: an L formed by a folded ribbon with two colored faces" />
  </picture>
  <h1>Lumenote</h1>
  <p><strong>Turn your classes into knowledge you can return to.</strong></p>
  <p>Record once. Keep the context. Learn from your own materials.</p>
  <p>
    <a href="https://lumenote-7ko.pages.dev"><strong>Explore Lumenote ↗</strong></a> ·
    <a href="#quick-start">Self-host the app</a> ·
    <a href="https://github.com/ToshioDev/lumenote-app/issues">Report or suggest</a> ·
    <a href="README.md">Español</a>
  </p>
</div>

<p align="center">
  <img src="assets/readme/lumenote-workflow-en.svg" width="100%" alt="Lumenote workflow: record a class, connect notes and resources to a topic, then study with summaries, an AI tutor, and active practice" />
</p>

## Audio is just the beginning

Lumenote brings recordings, timestamped transcripts, notes, and resources together under one topic. Return to the moment that matters, make sense of a session, and turn its content into study practice.

- **Capture:** record and replay sessions; follow transcripts along the timeline.
- **Organize:** group notes, documents, images, and links by topic, including links to a specific moment.
- **Learn:** create summaries and use the AI tutor, flashcards, and questions to review. AI features require a provider configured on the backend.

## Quick start

You need Docker Compose v2 and your own Supabase project. Supabase is not included in this Compose setup: authentication and storage connect to your own instance.

**1. Create local configuration files.**

```bash
cp .env.example .env
cp backend/.env.example backend/.env
```

**2. Configure the variables.** Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and a strong PostgreSQL password in the root `.env`. Configure `backend/.env` for the API and any providers you want to enable. Never publish `service_role` keys, AI tokens, or other secrets.

**3. Start the services.**

```bash
docker compose up --build
```

| Service | Local address |
| --- | --- |
| Web app | <http://localhost:8765> |
| API | <http://localhost:8787> |

Review and apply the migrations in [`supabase/migrations/`](supabase/migrations/) before using your instance. Whisper downloads its model on first launch, which can take a while. For remote deployments, `LUMENOTE_AI_URL` must point to an HTTPS URL reachable from the browser; internal Docker names are not reachable from users' devices. See [deployment modes](docs/deployment-modes.md) for dependencies and limitations.

## How the pieces connect

```mermaid
flowchart LR
    C[Flutter app: mobile, web, desktop] -->|Auth, data, files| S[Your Supabase project]
    C -->|Processing| A[Node.js API]
    A --> D[(PostgreSQL)]
    A --> W[Local Whisper]
    A --> M[Configured AI provider]
```

PostgreSQL stores API-specific data; Supabase is external and must be configured separately. Whisper runs locally as a Docker service. AI feature availability and cost depend on the provider you configure.

## Development and stack

To run Flutter in Chrome, install Flutter, run `flutter pub get`, and set the addresses for your Supabase project and backend:

```bash
flutter run -d chrome --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY --dart-define=LUMENOTE_AI_URL=http://localhost:8787
```

The Supabase publishable key needs correct RLS policies. Do not include private secrets in `--dart-define` or the client app.

<p>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-app-6C4CE3?logo=flutter&logoColor=white" />
  <img alt="Dart" src="https://img.shields.io/badge/Dart-language-0175C2?logo=dart&logoColor=white" />
  <img alt="Node.js" src="https://img.shields.io/badge/Node.js-API-5FA04E?logo=nodedotjs&logoColor=white" />
  <img alt="PostgreSQL" src="https://img.shields.io/badge/PostgreSQL-data-4169E1?logo=postgresql&logoColor=white" />
  <img alt="Supabase" src="https://img.shields.io/badge/Supabase-auth%20%26%20storage-3FCF8E?logo=supabase&logoColor=white" />
  <img alt="Docker Compose" src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white" />
</p>

## Project status

Lumenote is under active development. Before proposing a change, run the relevant checks: `flutter analyze`, `flutter test`, `node --check backend/server.mjs`, and `python scripts/check_utf8.py`. Share bugs and ideas in [GitHub Issues](https://github.com/ToshioDev/lumenote-app/issues).

Memberships, billing, and the distribution dashboard are not advertised as production-ready commercial services yet. Their status is documented in [`docs/membership-commerce-plan.md`](docs/membership-commerce-plan.md) and [`docs/distribution-control-plane.md`](docs/distribution-control-plane.md).

## License and assets

This repository does not yet include a `LICENSE` file; public visibility alone does not grant permission to reuse or redistribute the code. The Kuromi character and illustrations belong to their respective rights holders and are not covered by a Lumenote license. Check the rights for each asset before redistributing a build.

<p align="center"><sub>© 2026 Lumenote · Keep important ideas from disappearing when class ends.</sub></p>

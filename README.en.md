<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/branding/lumenote_isotype_dark.png" />
    <source media="(prefers-color-scheme: light)" srcset="assets/branding/lumenote_isotype_light.png" />
    <img src="assets/branding/lumenote_isotype_light.png" width="76" alt="Lumenote mark: an L formed by a folded ribbon with two colored faces" />
  </picture>
  <h1>Lumenote</h1>
  <p><strong>Turn recorded classes into ideas that stay with you.</strong></p>
  <p>Record a session, connect its materials, and turn each topic into a chance to learn.</p>
  <p>
    <a href="https://lumenote-7ko.pages.dev"><strong>Discover Lumenote</strong></a> ·
    <a href="https://github.com/ToshioDev/lumenote-app/issues">Suggest an improvement</a> ·
    <a href="README.md">Español</a>
  </p>
  <p>
    <img alt="Flutter" src="https://img.shields.io/badge/Flutter-app-6C4CE3?logo=flutter&logoColor=white" />
    <img alt="Dart" src="https://img.shields.io/badge/Dart-language-0175C2?logo=dart&logoColor=white" />
    <img alt="Node.js" src="https://img.shields.io/badge/Node.js-API-5FA04E?logo=nodedotjs&logoColor=white" />
    <img alt="PostgreSQL" src="https://img.shields.io/badge/PostgreSQL-data-4169E1?logo=postgresql&logoColor=white" />
    <img alt="Supabase" src="https://img.shields.io/badge/Supabase-auth%20%26%20storage-3FCF8E?logo=supabase&logoColor=white" />
    <img alt="Docker Compose" src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white" />
  </p>
</div>

## From class audio to active learning

A class does not end when you stop recording. Lumenote keeps the session and its resources together by topic, so you can return to what matters and practice it later.

<table>
  <tr>
    <td align="center" width="33%">
      <img src="assets/readme/lumenote-audio-to-notes.png" width="100%" alt="Concept illustration: a class recording connected to a timestamped transcript and notes" />
      <strong>01 · Capture</strong><br />Record and revisit moments through timestamps.
    </td>
    <td align="center" width="33%">
      <img src="assets/readme/lumenote-topic-materials.png" width="100%" alt="Concept illustration: audio, a document, an image, and a link connected to a topic and timeline" />
      <strong>02 · Connect</strong><br />Bring notes, documents, images, and links into one topic.
    </td>
    <td align="center" width="33%">
      <img src="assets/readme/lumenote-active-study.png" width="100%" alt="Concept illustration: flashcards, multiple-choice questions, and study progress" />
      <strong>03 · Practice</strong><br />Review with cards and questions based on your materials.
    </td>
  </tr>
</table>

<p align="center"><sub>Concept illustrations of the workflow; these are not screenshots of the application.</sub></p>

## What is in the project

- **Cross-platform Flutter app:** Android, iOS, web, and desktop.
- **Node.js API** and PostgreSQL for API data and processing jobs.
- **Optional local Whisper transcription**, running as a separate service with a persistent model cache.
- **Configurable Supabase** for authentication, data access, and storage; you provide your own Supabase project.
- Topic organization, recording and playback, timestamped transcripts, summaries, an AI tutor, and study tools. AI features depend on backend configuration and the provider you enable.

## Run the web app with Docker

Requirements: Docker Compose v2 and a Supabase project. This Compose setup **does not install Supabase**; it runs the web app, API, PostgreSQL for API data, and local Whisper service.

Create configuration files from the templates:

```bash
cp .env.example .env
cp backend/.env.example backend/.env
```

Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in the root `.env`, then configure `backend/.env`. Use a strong PostgreSQL password. Do not put `service_role` keys, AI credentials, or provider secrets in the root `.env` or client app.

```bash
docker compose up --build
```

When the services start:

- Web app: `http://localhost:8765`
- API: `http://localhost:8787`

Review and apply the migrations in [`supabase/migrations/`](supabase/migrations/) and read the [deployment modes guide](docs/deployment-modes.md) before using your instance. Whisper's first launch may take a while as it downloads the model. For a remote deployment, set `LUMENOTE_AI_URL` to an HTTPS address reachable from the user's browser; an internal Docker service name is not reachable from their device.

### Run Flutter in development

Install Flutter, run `flutter pub get`, and configure your Supabase and API values for your environment:

```bash
flutter run -d chrome --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY --dart-define=LUMENOTE_AI_URL=http://localhost:8787
```

The Supabase publishable key requires correctly configured RLS policies. Never include private keys in `--dart-define` or a client build.

## Architecture

```mermaid
flowchart LR
    U[Flutter app: mobile, web, desktop] --> S[Supabase: Auth, REST, Storage]
    U --> A[Node.js API]
    A --> D[(PostgreSQL)]
    A --> W[Optional local Whisper]
    A --> M[Configured AI provider]
```

Supabase Auth and storage are external services configured by the operator. PostgreSQL and Whisper in Compose are private supporting services for the API; they are not a complete Supabase installation.

## Contributing

The project is under active development. Share bugs or ideas through [GitHub Issues](https://github.com/ToshioDev/lumenote-app/issues). Before submitting a change, run the relevant checks, such as `flutter analyze`, `flutter test`, `node --check backend/server.mjs`, and `python scripts/check_utf8.py`.

Memberships, billing, and the distribution dashboard are not presented here as production-ready commercial services. See [`docs/membership-commerce-plan.md`](docs/membership-commerce-plan.md) and [`docs/distribution-control-plane.md`](docs/distribution-control-plane.md) for their status.

## License and assets

The repository currently has no `LICENSE` file. Publicly visible code is not, by itself, permission to reuse or redistribute it. The Kuromi character and illustrations belong to their respective rights holders and are not covered by a Lumenote license; check the rights for each asset before redistributing a build.

<p align="center"><sub>© 2026 Lumenote · Keep the context of class, not only the audio file.</sub></p>

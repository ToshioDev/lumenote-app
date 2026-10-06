<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/branding/lumenote_isotype_white.png" />
    <source media="(prefers-color-scheme: light)" srcset="assets/branding/lumenote_isotype_black.png" />
    <img src="assets/branding/lumenote_isotype_black.png" width="92" alt="Official Lumenote mark: a folded black-and-lilac ribbon forming an L" />
  </picture>
  <h1>Lumenote</h1>
  <p><strong>From recorded class to knowledge that sticks.</strong></p>
  <p>Capture once. Find the idea. Learn your way.</p>
  <p>
    <a href="https://lumenote-7ko.pages.dev"><strong>Visit Lumenote</strong></a> ·
    <a href="https://github.com/ToshioDev/lumenote-app">Source and project</a> ·
    <a href="https://github.com/ToshioDev/lumenote-app/issues">Share an idea</a> ·
    <a href="README.md">Español</a>
  </p>
  <p>
    <a href="https://flutter.dev"><img alt="Flutter" src="https://img.shields.io/badge/Flutter-apps-6C4CE3?logo=flutter&logoColor=white" /></a>
    <a href="https://dart.dev"><img alt="Dart" src="https://img.shields.io/badge/Dart-language-0175C2?logo=dart&logoColor=white" /></a>
    <a href="https://react.dev"><img alt="React" src="https://img.shields.io/badge/React-UI-149ECA?logo=react&logoColor=white" /></a>
    <a href="https://vite.dev"><img alt="Vite" src="https://img.shields.io/badge/Vite-web-646CFF?logo=vite&logoColor=white" /></a>
    <a href="https://www.typescriptlang.org"><img alt="TypeScript" src="https://img.shields.io/badge/TypeScript-types-3178C6?logo=typescript&logoColor=white" /></a>
    <a href="https://nodejs.org"><img alt="Node.js" src="https://img.shields.io/badge/Node.js-API-5FA04E?logo=nodedotjs&logoColor=white" /></a>
    <a href="https://www.postgresql.org"><img alt="PostgreSQL" src="https://img.shields.io/badge/PostgreSQL-data-4169E1?logo=postgresql&logoColor=white" /></a>
    <a href="https://supabase.com"><img alt="Supabase" src="https://img.shields.io/badge/Supabase-auth%20%26%20storage-3FCF8E?logo=supabase&logoColor=white" /></a>
    <a href="https://www.docker.com"><img alt="Docker" src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white" /></a>
    <a href="https://pages.cloudflare.com"><img alt="Cloudflare Pages" src="https://img.shields.io/badge/Cloudflare-Pages-F38020?logo=cloudflare&logoColor=white" /></a>
  </p>
</div>

## Learn from every class—not just store its audio

Lumenote brings recordings, notes, and learning materials together by topic. Jump to an idea from its timestamp, understand the main points, and turn your notes into active study.

### Listen, then return to the exact moment

Record a class, follow its timestamped transcript, and find the important ideas without replaying the whole session.

<p align="center"><img src="assets/readme/lumenote-audio-to-notes.png" width="100%" alt="A class recording becomes a timeline of transcript segments and related notes" /></p>

### Connect every resource to its topic

Gather audio, documents, images, and links. Associate each resource with the moment it appears in class so its context stays with it.

<p align="center"><img src="assets/readme/lumenote-topic-materials.png" width="100%" alt="A learning topic connects audio, a document, a slide, and a link to class timestamps" /></p>

### Study actively

Review with flashcards and multiple-choice questions based on your topics, then use progress feedback to spot what to practice again.

<p align="center"><img src="assets/readme/lumenote-active-study.png" width="100%" alt="A multiple-choice question, review cards, and a study progress indicator" /></p>

## What is in the project

- Flutter apps for Android, iOS, web, Windows, macOS, and Linux.
- Responsive offering site built with React, TypeScript, and Vite.
- Node.js backend, PostgreSQL, and optional local Whisper transcription services.
- Configurable Supabase integration for authentication, REST, and storage.
- Topic organization, timestamped transcripts, summaries, an AI tutor, and study tools. AI features depend on the provider and backend configuration.

## Run Lumenote on your own setup

You need Docker Compose v2 and your own Supabase project for Auth, PostgREST, and Storage; Supabase itself is not bundled with Compose.

```powershell
Copy-Item .env.example .env
Copy-Item backend/.env.example backend/.env
```

Configure your Supabase values, a strong PostgreSQL password, and any providers you choose to enable. Keep `.env` files private: service-role keys, AI tokens, and provider credentials belong on the backend only.

```powershell
docker compose up --build
```

Open the offering at `http://localhost:8080`, the app at `http://localhost:8765`, and the API at `http://localhost:8787`. Review and apply the migrations in [`supabase/migrations/`](supabase/migrations/) to your own project before using it. The local transcriber may take a few minutes to download its model on first launch.

### Offering development

```powershell
Set-Location offering
npm ci
npm run dev
```

Vite starts with hot reload at `http://localhost:5173`.

### Flutter app development

```powershell
flutter pub get
flutter run -d chrome `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY `
  --dart-define=LUMENOTE_AI_URL=http://localhost:8787
```

For remote deployments, `LUMENOTE_AI_URL` must be HTTPS and reachable from every device. A Supabase publishable key requires correctly configured RLS policies. See [deployment modes](docs/deployment-modes.md) for the components and hosting options.

## How it connects

```mermaid
flowchart LR
    U[Flutter: mobile, web, desktop] --> S[Supabase Auth, REST, Storage]
    U --> A[Node.js API]
    A --> D[(PostgreSQL)]
    A --> W[Optional local Whisper]
    A --> M[Configured AI provider]
```

## Build it with the community

Lumenote is under active development. Open an [issue](https://github.com/ToshioDev/lumenote-app/issues), suggest an improvement, or help with accessibility, Spanish transcription, mobile experience, and documentation. Run the relevant checks before contributing, such as `flutter analyze`, `flutter test`, `node --check backend/server.mjs`, and `python scripts/check_utf8.py`.

Memberships, billing, and the distribution console are not advertised as production-ready services yet. Their status is tracked in [`docs/membership-commerce-plan.md`](docs/membership-commerce-plan.md) and [`docs/distribution-control-plane.md`](docs/distribution-control-plane.md).

## License and asset rights

This repository does not yet include a `LICENSE` file. Public visibility by itself does not grant permission to reuse or redistribute the code. Kuromi branding and illustrations are third-party intellectual property and are not covered by a Lumenote license. Check asset rights before redistributing a build.

<p align="center"><sub>© 2026 Lumenote · Built so important ideas do not disappear when class ends.</sub></p>

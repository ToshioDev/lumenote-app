# Lumenote: self-hosted and hosted deployment

## One product, two operators

The repository should remain the single source of truth. A self-hosted operator runs the same Flutter client and API with their own Supabase Auth/Storage project, PostgreSQL, Whisper model and any chosen AI/Codex credentials. They pay their own infrastructure/provider bills; use of the source carries no Lumenote subscription.

Lumenote Cloud runs the same code and charges for managed capacity and convenience: reliable queueing, hosted transcription, storage/retention, backups, higher monthly minutes, account support and team workflows as those features become production-ready. Do not make self-hosted functionality depend on our billing server or keys. Free/Plus/Pro limits apply to the hosted service; the operator chooses the limits for a private install.

## Unified backend boundary

`backend/server.mjs` is the only public API boundary. Keep feature areas as modules/adapters behind the existing `/api` routes: authentication validation, account/membership, notes/topics, asynchronous media jobs, transcription, Codex/AI, billing, webhook handling, and observability. Internal services such as Whisper are private implementation adapters, not alternate public APIs. Avoid making a second “commercial backend” fork.

The current runtime still has separate storage responsibilities: PostgreSQL stores API-side notes/media/jobs; Supabase Auth, PostgREST and Storage remain external dependencies. This compose file does not yet bundle the Supabase stack. Treat this as a known limitation before advertising “one-command all-in-one self-host”; a complete local install must either add a supported self-hosted Supabase stack or consolidate identity/data behind the API in a separately tested migration.

## Compose services

- `lumenote-web`: compiles Flutter Web using the Flutter SDK image, then serves it via Nginx on port 8765.
- `lumenote-ai`: unified Node API on port 8787; requires `backend/.env`.
- `postgres`: private PostgreSQL for the API's application data.
- `lumenote-whisper`: private CPU transcription adapter; model cache persists in a named volume.

Create the root `.env` from `.env.example` and `backend/.env` from `backend/.env.example`, provide a strong unique PostgreSQL password and real Supabase URL/anon key, then run `docker compose up --build`. Set `LUMENOTE_AI_URL` to the browser-reachable API URL when deploying remotely; Compose service DNS names are not reachable from a user's browser. Never put a Supabase service-role key, Codex token, or billing/webhook secret in the root build `.env`.

Mobile and desktop applications are compiled as Flutter platform builds, not served as containers. Docker packages their shared backend and web client; it does not replace Android/iOS signing, platform SDKs, or store distribution.

## Public repository checklist

1. Choose an explicit license before public release; do not publish without knowing the grant. MIT favors broad adoption/reuse; AGPLv3 is a copyleft option for network service modifications. Obtain legal review for the intended hosted-service model.
2. Keep private environment files, audio, user exports and OAuth sessions out of Git. Rotate any credential ever committed.
3. Publish `.env.example` files with placeholders only, pin dependency/tool versions and add CI for Flutter analysis/tests, Node checks/tests, SQL migration lint, and Docker build.
4. Document resource expectations for local Whisper (`small` model, CPU/RAM, first-download time) and storage/backup/restore procedures.
5. Keep commercial-only secrets and billing webhook endpoints in Lumenote Cloud's deployment configuration, never in a public image or Flutter binary.

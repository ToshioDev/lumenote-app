import 'dotenv/config';
import crypto from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import cors from 'cors';
import express from 'express';
import multer from 'multer';
import OpenAI, { toFile } from 'openai';
import pg from 'pg';
import { buildAuthorizationUrl, createPkceState, exchangeCode, refreshAccessToken, accountIdFromToken, runCodexTurn, requestDeviceCode, pollDeviceCode, exchangeDeviceCode } from './codex_runtime.mjs';

const { Pool } = pg;
const execFileAsync = promisify(execFile);

const app = express();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 200 * 1024 * 1024 } });
const port = Number(process.env.PORT || 8787);
const client = process.env.OPENAI_API_KEY ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY }) : null;
const pool = process.env.DATABASE_URL ? new Pool({ connectionString: process.env.DATABASE_URL, max: 10, ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : undefined }) : null;
const encryptionKey = process.env.CODEX_TOKEN_ENCRYPTION_KEY ? Buffer.from(process.env.CODEX_TOKEN_ENCRYPTION_KEY, 'base64') : null;
const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || '';
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

const MEMBERSHIP_PLANS = Object.freeze({
  free: { name: 'Gratis', minutes_limit: 60 },
  plus: { name: 'Plus', minutes_limit: 600 },
  pro: { name: 'Pro', minutes_limit: 2400 },
});

app.use(cors({ origin: process.env.CORS_ORIGIN || true }));
app.use(express.json({ limit: '2mb' }));

async function requireUser(req, res, next) {
  const header = String(req.headers.authorization || '');
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!supabaseUrl || !supabaseAnonKey || !token) return res.status(401).json({ error: 'Autenticación requerida.' });
  try {
    const response = await fetch(`${supabaseUrl}/auth/v1/user`, { headers: { apikey: supabaseAnonKey, authorization: `Bearer ${token}` } });
    if (!response.ok) return res.status(401).json({ error: 'Sesión inválida o expirada.' });
    const user = await response.json();
    req.userId = user.id;
    req.authToken = token;
    next();
  } catch (_) { res.status(503).json({ error: 'No se pudo validar la sesión.' }); }
}

async function requireFounder(req, res, next) {
  await requireUser(req, res, async () => {
    const configured = String(process.env.FOUNDER_USER_IDS || '').split(',').map((value) => value.trim()).filter(Boolean);
    if (configured.includes(req.userId)) return next();
    try {
      const response = await fetch(`${supabaseUrl}/rest/v1/profiles?id=eq.${encodeURIComponent(req.userId)}&select=role`, { headers: { apikey: supabaseAnonKey, authorization: `Bearer ${req.authToken}` } });
      const rows = response.ok ? await response.json() : [];
      if (rows[0]?.role !== 'founder') return res.status(403).json({ error: 'Esta sección es exclusiva para cuentas founder.' });
      next();
    } catch (_) { res.status(503).json({ error: 'No se pudo validar el rol founder.' }); }
  });
}

function serviceHeaders(extra = {}) { return { apikey: supabaseServiceRoleKey, authorization: `Bearer ${supabaseServiceRoleKey}`, ...extra }; }
async function serviceRequest(pathname, options = {}) { return fetch(`${supabaseUrl}${pathname}`, { ...options, headers: serviceHeaders({ 'content-type': 'application/json', ...(options.headers || {}) }) }); }

class MembershipQuotaError extends Error {
  constructor(message, status = 429) { super(message); this.status = status; }
}

function isAudioMedia(file) {
  return /^(audio|video)\//.test(String(file.mimetype || '')) ||
    /\.(m4a|mp3|wav|aac|ogg|webm|mp4|mov|mkv)$/i.test(String(file.originalname || '')) ||
    /^(audio|video)\//.test(String(file.mediaType || ''));
}

async function estimateAudioMinutes(file) {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'lumenote-quota-'));
  const tempFile = path.join(tempDir, path.basename(file.originalname || 'recording.m4a'));
  try {
    await fs.writeFile(tempFile, file.buffer);
    const { stdout } = await execFileAsync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', tempFile], { timeout: 30000, maxBuffer: 1024 * 1024 });
    const duration = Number(stdout.trim());
    if (!Number.isFinite(duration) || duration <= 0) throw new Error('No se pudo medir la duración del audio.');
    return Math.max(1, Math.ceil(duration / 60));
  } catch (error) {
    if (error.code === 'ENOENT') throw new Error('El servidor no tiene ffprobe para medir la cuota de audio.');
    throw error;
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
}

async function reserveAudioQuota({ ownerId, noteId, file, reservationId = crypto.randomUUID() }) {
  if (!supabaseServiceRoleKey) throw new MembershipQuotaError('El servicio de cuotas no está configurado; contacta al administrador.', 503);
  const minutes = await estimateAudioMinutes(file);
  const response = await serviceRequest('/rest/v1/rpc/reserve_transcription_minutes', {
    method: 'POST', body: JSON.stringify({ p_user_id: ownerId, p_reservation_id: reservationId, p_note_id: noteId || null, p_minutes: minutes }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new MembershipQuotaError(data.message || 'No se pudo verificar la cuota de la membresía.', 503);
  if (!data.allowed) {
    const messages = {
      quota_exceeded: `Esta grabación requiere ${minutes} min y supera tu cuota disponible (${data.used}/${data.limit} min). Elige otro plan o espera al reinicio mensual.`,
      membership_inactive: 'Tu membresía está pausada o vencida. Revisa tu cuenta para continuar.',
      membership_missing: 'No encontramos una membresía para tu cuenta. Vuelve a iniciar sesión o contacta al administrador.',
    };
    throw new MembershipQuotaError(messages[data.reason] || 'No se pudo reservar el uso de transcripción.');
  }
  return { reservationId, minutes };
}

async function completeAudioQuota(reservationId) {
  if (!reservationId) return;
  const response = await serviceRequest('/rest/v1/rpc/complete_transcription_minutes', { method: 'POST', body: JSON.stringify({ p_reservation_id: reservationId }) });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.completed) throw new Error(data.message || 'No se pudo confirmar el consumo de minutos.');
}

async function releaseAudioQuota(reservationId) {
  if (!reservationId) return;
  try {
    await serviceRequest('/rest/v1/rpc/release_transcription_minutes', { method: 'POST', body: JSON.stringify({ p_reservation_id: reservationId }) });
  } catch (_) { /* A stale reservation is reclaimed by the period boundary. */ }
}

app.get('/api/membership/plans', requireUser, async (_req, res) => {
  if (!supabaseServiceRoleKey) return res.status(503).json({ error: 'Membership service is not configured.' });
  try {
    const response = await serviceRequest('/rest/v1/membership_plans?select=code,name,description,minutes_limit,features,monthly_price_minor,annual_price_minor,currency&enabled=eq.true&order=display_order.asc');
    if (!response.ok) throw new Error('Could not load membership plans.');
    // Credentials alone do not mean payments are safe to accept: enable only
    // after checkout, signed webhooks, portal and sandbox tests are implemented.
    res.json({ plans: await response.json(), checkout_enabled: false, billing_provider: null });
  } catch (error) { res.status(502).json({ error: error.message || 'Could not load membership plans.' }); }
});

app.get('/api/founder/users', requireFounder, async (req, res) => {
  if (!supabaseServiceRoleKey) return res.status(503).json({ error: 'SUPABASE_SERVICE_ROLE_KEY no está configurada.' });
  try {
    const [profilesResponse, subscriptionsResponse] = await Promise.all([
      serviceRequest('/rest/v1/profiles?select=id,display_name,nickname,avatar_url,role,created_at&order=created_at.desc'),
      serviceRequest('/rest/v1/subscriptions?select=user_id,plan,status,minutes_used,minutes_limit,current_period_end'),
    ]);
    if (!profilesResponse.ok || !subscriptionsResponse.ok) throw new Error('No se pudieron cargar los perfiles.');
    const profiles = await profilesResponse.json();
    const subscriptions = await subscriptionsResponse.json();
    const byUser = Object.fromEntries(subscriptions.map((item) => [item.user_id, item]));
    res.json({ users: profiles.map((profile) => ({ ...profile, subscription: byUser[profile.id] || null })) });
  } catch (error) { res.status(502).json({ error: error.message || 'No se pudieron cargar los perfiles.' }); }
});

app.post('/api/founder/users', requireFounder, async (req, res) => {
  if (!supabaseServiceRoleKey) return res.status(503).json({ error: 'SUPABASE_SERVICE_ROLE_KEY no está configurada.' });
  const email = String(req.body?.email || '').trim().toLowerCase();
  const password = String(req.body?.password || '');
  const displayName = String(req.body?.display_name || '').trim();
  const nickname = String(req.body?.nickname || '').trim();
  const role = ['user', 'founder'].includes(String(req.body?.role || 'user')) ? String(req.body?.role || 'user') : 'user';
  const plan = ['free', 'plus', 'pro'].includes(String(req.body?.plan || 'free')) ? String(req.body?.plan || 'free') : 'free';
  if (!email || password.length < 6 || !displayName) return res.status(400).json({ error: 'Nombre, correo y contraseña de al menos 6 caracteres son obligatorios.' });
  try {
    const created = await serviceRequest('/auth/v1/admin/users', { method: 'POST', body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { display_name: displayName, full_name: displayName, nickname } }) });
    const user = await created.json();
    if (!created.ok) return res.status(created.status).json({ error: user.msg || user.message || 'No se pudo crear el usuario.' });
    const profileResponse = await serviceRequest('/rest/v1/profiles?on_conflict=id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify({ id: user.id, display_name: displayName, nickname, role }) });
    if (!profileResponse.ok) throw new Error('La cuenta fue creada, pero no se pudo guardar su perfil.');
    const subscriptionResponse = await serviceRequest('/rest/v1/subscriptions?on_conflict=user_id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify({ user_id: user.id, plan, status: 'active', minutes_limit: MEMBERSHIP_PLANS[plan].minutes_limit, billing_provider: 'manual', updated_at: new Date().toISOString() }) });
    if (!subscriptionResponse.ok) throw new Error('La cuenta fue creada, pero no se pudo guardar su membresía.');
    res.status(201).json({ user: { id: user.id, email, display_name: displayName, nickname, role, plan } });
  } catch (error) { res.status(502).json({ error: error.message || 'No se pudo crear el perfil.' }); }
});

app.patch('/api/founder/users/:id/membership', requireFounder, async (req, res) => {
  if (!supabaseServiceRoleKey) return res.status(503).json({ error: 'SUPABASE_SERVICE_ROLE_KEY no está configurada.' });
  const plan = String(req.body?.plan || 'free');
  const status = String(req.body?.status || 'active');
  if (!['free', 'plus', 'pro'].includes(plan) || !['active', 'paused', 'cancelled'].includes(status)) return res.status(400).json({ error: 'Plan o estado no válido.' });
  const minutesLimit = MEMBERSHIP_PLANS[plan].minutes_limit;
  try {
    const response = await serviceRequest('/rest/v1/subscriptions?on_conflict=user_id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=representation' }, body: JSON.stringify({ user_id: req.params.id, plan, status, minutes_limit: minutesLimit, billing_provider: 'manual', provider_subscription_id: null, provider_price_id: null, billing_interval: null, current_period_start: null, current_period_end: null, cancel_at_period_end: false, updated_at: new Date().toISOString() }) });
    const body = await response.json();
    if (!response.ok) return res.status(response.status).json({ error: body.message || 'No se pudo actualizar la membresía.' });
    res.json({ subscription: body[0] || body });
  } catch (error) { res.status(502).json({ error: error.message || 'No se pudo actualizar la membresía.' }); }
});

app.get('/api/branding', requireUser, async (req, res) => {
  if (!pool) return res.json({ branding: null });
  try {
    const result = await pool.query('SELECT app_name, accent_hex, logo_url, splash_url, hero_url, version, updated_at FROM branding_configs WHERE owner_id=$1', [req.userId]);
    res.json({ branding: result.rows[0] || null });
  } catch (error) { res.status(502).json({ error: error.message || 'No se pudo cargar el branding.' }); }
});

app.put('/api/founder/branding', requireFounder, async (req, res) => {
  if (!pool) return res.status(503).json({ error: 'Base de datos no configurada.' });
  const appName = String(req.body?.app_name || 'KuromiNotes').trim().slice(0, 80);
  const accentHex = /^#[0-9a-fA-F]{6}$/.test(String(req.body?.accent_hex || '')) ? String(req.body.accent_hex) : '#FF77B7';
  const values = [req.userId, appName || 'KuromiNotes', accentHex, String(req.body?.logo_url || '').trim() || null, String(req.body?.splash_url || '').trim() || null, String(req.body?.hero_url || '').trim() || null];
  try {
    const result = await pool.query(`INSERT INTO branding_configs(owner_id,app_name,accent_hex,logo_url,splash_url,hero_url,version)
      VALUES($1,$2,$3,$4,$5,$6,1) ON CONFLICT(owner_id) DO UPDATE SET app_name=excluded.app_name, accent_hex=excluded.accent_hex, logo_url=excluded.logo_url, splash_url=excluded.splash_url, hero_url=excluded.hero_url, version=branding_configs.version+1, updated_at=now() RETURNING app_name,accent_hex,logo_url,splash_url,hero_url,version,updated_at`, values);
    res.json({ branding: result.rows[0] });
  } catch (error) { res.status(502).json({ error: error.message || 'No se pudo guardar el branding.' }); }
});

async function ensureSchema() {
  if (!pool) return;
  await pool.query(`
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE TABLE IF NOT EXISTS notes (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      owner_id text NOT NULL DEFAULT 'anonymous',
      title text NOT NULL,
      source text NOT NULL DEFAULT 'manual',
      media_type text,
      storage_path text,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS topics (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      owner_id text NOT NULL,
      title text NOT NULL,
      description text NOT NULL DEFAULT '',
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );
    ALTER TABLE notes ADD COLUMN IF NOT EXISTS topic_id uuid REFERENCES topics(id) ON DELETE SET NULL;
    ALTER TABLE notes ADD COLUMN IF NOT EXISTS speaker_mode text NOT NULL DEFAULT 'single';
    ALTER TABLE notes ADD COLUMN IF NOT EXISTS speaker_count integer NOT NULL DEFAULT 1;
    CREATE INDEX IF NOT EXISTS topics_owner_idx ON topics(owner_id, updated_at DESC);
    CREATE INDEX IF NOT EXISTS notes_topic_idx ON notes(topic_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS transcripts (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      note_id uuid NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
      content text NOT NULL DEFAULT '',
      segments jsonb NOT NULL DEFAULT '[]'::jsonb,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS note_media (
      note_id uuid PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
      filename text NOT NULL,
      mime_type text NOT NULL,
      content bytea NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS note_ai_outputs (
      note_id uuid PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
      source_text text NOT NULL DEFAULT '',
      summary text NOT NULL DEFAULT '',
      study jsonb NOT NULL DEFAULT '{}'::jsonb,
      status text NOT NULL DEFAULT 'completed',
      updated_at timestamptz NOT NULL DEFAULT now()
    );
    ALTER TABLE note_ai_outputs ADD COLUMN IF NOT EXISTS stage text NOT NULL DEFAULT 'queued';
    ALTER TABLE note_ai_outputs ADD COLUMN IF NOT EXISTS progress integer NOT NULL DEFAULT 0;
    ALTER TABLE note_ai_outputs ADD COLUMN IF NOT EXISTS message text NOT NULL DEFAULT 'En cola…';
    CREATE INDEX IF NOT EXISTS notes_owner_created_idx ON notes(owner_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS transcripts_note_idx ON transcripts(note_id);
    CREATE TABLE IF NOT EXISTS codex_oauth_states (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      owner_id text NOT NULL,
      state text UNIQUE NOT NULL,
      code_verifier text NOT NULL,
      host_id text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS codex_credentials (
      owner_id text PRIMARY KEY,
      access_token_enc text NOT NULL,
      id_token_enc text,
      refresh_token_enc text NOT NULL,
      expires_at timestamptz NOT NULL,
      account_id text,
      host_id text NOT NULL,
      updated_at timestamptz NOT NULL DEFAULT now()
    );
    ALTER TABLE codex_credentials ADD COLUMN IF NOT EXISTS id_token_enc text;
    CREATE TABLE IF NOT EXISTS codex_device_states (
      owner_id text PRIMARY KEY,
      device_auth_id text NOT NULL,
      user_code text NOT NULL,
      interval_seconds integer NOT NULL DEFAULT 5,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS codex_threads (
      owner_id text NOT NULL,
      note_id uuid REFERENCES notes(id) ON DELETE CASCADE,
      thread_id text NOT NULL,
      model text,
      updated_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (owner_id, note_id)
    );
    CREATE TABLE IF NOT EXISTS branding_configs (
      owner_id text PRIMARY KEY,
      app_name text NOT NULL DEFAULT 'Lumenote',
      accent_hex text NOT NULL DEFAULT '#B4A6ED',
      logo_url text,
      splash_url text,
      hero_url text,
      version integer NOT NULL DEFAULT 1,
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  `);
}

function requireCodexStorage() {
  if (!pool) throw new Error('DATABASE_URL no configurada.');
  if (!encryptionKey || encryptionKey.length !== 32) throw new Error('CODEX_TOKEN_ENCRYPTION_KEY debe ser una clave base64 de 32 bytes.');
}

function encrypt(value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey, iv);
  const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), encrypted].map((part) => part.toString('base64url')).join('.');
}

function decrypt(value) {
  const [iv, tag, data] = value.split('.').map((part) => Buffer.from(part, 'base64url'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
}

async function getCodexCredential(ownerId) {
  requireCodexStorage();
  const result = await pool.query('SELECT * FROM codex_credentials WHERE owner_id = $1', [ownerId]);
  if (!result.rowCount) return null;
  const row = result.rows[0];
  let access = decrypt(row.access_token_enc);
  let idToken = row.id_token_enc ? decrypt(row.id_token_enc) : access;
  let refresh = decrypt(row.refresh_token_enc);
  if (new Date(row.expires_at).getTime() - Date.now() < 60_000) {
    const next = await refreshAccessToken(refresh);
    access = next.access_token;
    idToken = next.id_token || idToken;
    refresh = next.refresh_token || refresh;
    await pool.query('UPDATE codex_credentials SET access_token_enc=$1, id_token_enc=$2, refresh_token_enc=$3, expires_at=$4, updated_at=now() WHERE owner_id=$5', [encrypt(access), encrypt(idToken), encrypt(refresh), new Date(Date.now() + Number(next.expires_in || 3600) * 1000), ownerId]);
  }
  return { ...row, accessToken: access, idToken, refreshToken: refresh };
}

async function transcribeWithCodex({ credential, file, model = process.env.CODEX_TRANSCRIBE_MODEL || 'gpt-4o-transcribe', language = 'es' }) {
  if (!credential?.accessToken) throw new Error('No hay una sesión Codex conectada.');
  const form = new FormData();
  form.append('file', new Blob([file.buffer], { type: file.mimetype || 'application/octet-stream' }), file.originalname || 'audio.m4a');
  form.append('model', model);
  if (language) form.append('language', language);
  form.append('response_format', 'verbose_json');
  const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { authorization: `Bearer ${credential.accessToken}` },
    body: form,
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error?.message || `Codex audio no disponible (${response.status}).`);
  return { text: body.text || '', segments: body.segments || [], provider: 'codex-oauth' };
}

// OpenClaw's free path is a local/CLI STT provider (for example whisper.cpp),
// not a hidden ChatGPT Plus endpoint.  Lumenote supports the same pattern via
// a small OpenAI-compatible Whisper sidecar configured with WHISPER_LOCAL_URL.
async function transcribeWithLocalWhisper({ file, language = process.env.WHISPER_LANGUAGE || 'es', speakerMode = 'single', speakerCount = 1 }) {
  const baseUrl = String(process.env.WHISPER_LOCAL_URL || 'http://lumenote-whisper:9000').replace(/\/$/, '');
  if (!baseUrl) throw new Error('No hay transcriptor local configurado.');
  const form = new FormData();
  form.append('file', new Blob([file.buffer], { type: file.mimetype || 'application/octet-stream' }), file.originalname || 'audio.m4a');
  form.append('language', language || 'es');
  form.append('speaker_mode', speakerMode === 'multi' ? 'multi' : 'single');
  form.append('speaker_count', String(Math.max(1, Math.min(12, Number(speakerCount) || 1))));
  const timeoutMs = Math.max(180000, Number(process.env.WHISPER_TIMEOUT_MS || 3600000));
  const response = await fetch(`${baseUrl}/transcribe`, { method: 'POST', body: form, signal: AbortSignal.timeout(timeoutMs) });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.text) throw new Error(body.error || `Transcriptor local no disponible (${response.status}).`);
  return { text: body.text, segments: body.segments || [], provider: 'local-whisper' };
}

async function saveTranscriptForUser({ ownerId, noteId, text, segments }) {
  if (!pool || !noteId) return;
  const note = await pool.query('SELECT id FROM notes WHERE id=$1 AND owner_id=$2', [noteId, ownerId]);
  if (!note.rowCount) throw new Error('La nota no pertenece al usuario actual.');
  await pool.query('INSERT INTO transcripts(note_id, content, segments) VALUES($1,$2,$3) ON CONFLICT(note_id) DO UPDATE SET content=excluded.content, segments=excluded.segments, created_at=now()', [noteId, text, JSON.stringify(segments || [])]);
}

function parseJsonObject(text) {
  try { return JSON.parse(text); } catch (_) {}
  const match = String(text || '').match(/\{[\s\S]*\}/);
  try { return match ? JSON.parse(match[0]) : {}; } catch (_) { return {}; }
}

function stripHtml(value) { return String(value || '').replace(/<[^>]+>/g, ' ').replace(/&quot;/g, '"').replace(/&#039;/g, "'").replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim(); }

async function discoverReferences(queries) {
  const results = [];
  for (const rawQuery of (Array.isArray(queries) ? queries : []).slice(0, 3)) {
    const query = String(rawQuery || '').trim();
    if (!query) continue;
    const encoded = encodeURIComponent(query);
    const [wiki, crossref] = await Promise.allSettled([
      fetch(`https://es.wikipedia.org/w/api.php?action=query&list=search&srsearch=${encoded}&srlimit=2&format=json&origin=*`, { headers: { 'user-agent': 'Lumenote/1.0 educational-note-assistant' }, signal: AbortSignal.timeout(12000) }).then((response) => response.json()),
      fetch(`https://api.crossref.org/works?query=${encoded}&rows=2&select=title,URL,author,published`, { headers: { 'user-agent': 'Lumenote/1.0 (mailto:support@lumenote.app)' }, signal: AbortSignal.timeout(12000) }).then((response) => response.json()),
    ]);
    if (wiki.status === 'fulfilled') {
      for (const item of wiki.value?.query?.search || []) results.push({ source: 'Wikipedia', query, title: item.title, url: `https://es.wikipedia.org/wiki/${encodeURIComponent(String(item.title).replace(/ /g, '_'))}`, excerpt: stripHtml(item.snippet) });
    }
    if (crossref.status === 'fulfilled') {
      for (const item of crossref.value?.message?.items || []) results.push({ source: 'Crossref', query, title: Array.isArray(item.title) ? item.title[0] : item.title, url: item.URL, excerpt: Array.isArray(item.author) ? item.author.slice(0, 3).map((author) => [author.given, author.family].filter(Boolean).join(' ')).join(', ') : '' });
    }
  }
  return [...new Map(results.filter((item) => item.title && item.url).map((item) => [item.url, item])).values()].slice(0, 10);
}

async function generateNoteOutputs({ ownerId, noteId, sourceText }) {
  const contextResult = await pool.query(`SELECT n.title, COALESCE(t.title, '') AS topic_title, COALESCE(tr.segments, '[]'::jsonb) AS segments FROM notes n LEFT JOIN topics t ON t.id=n.topic_id LEFT JOIN transcripts tr ON tr.note_id=n.id WHERE n.id=$1 AND n.owner_id=$2`, [noteId, ownerId]);
  const noteContext = contextResult.rows[0] || {};
  const timestampedTranscript = Array.isArray(noteContext.segments) && noteContext.segments.length
    ? noteContext.segments.map((segment) => `[${Math.floor(Number(segment.start || 0) / 60).toString().padStart(2, '0')}:${Math.floor(Number(segment.start || 0) % 60).toString().padStart(2, '0')}] ${segment.speaker ? `${segment.speaker}: ` : ''}${segment.text || ''}`).join('\n')
    : String(sourceText || '');
  const prompt = `Analiza una grabación y conviértela en un apunte inteligente, claro y fiel a lo que dijeron los oradores.
Prioriza exclusivamente lo que dijeron los oradores. Ignora silencios, ruido ambiental, música, sonidos de juego, muletillas y repeticiones sin valor. No inventes información.
El campo summary debe ser un apunte breve redactado según el contenido real de la conversación, no una descripción del archivo.
Agrupa ideas relacionadas, separa conceptos principales y secundarios, y conserva nombres, cifras, instrucciones, ejemplos, decisiones y conclusiones.
Los milestones deben señalar momentos realmente útiles con el timestamp exacto disponible. Si no hay un hito claro, no lo inventes.
Detecta instrucciones explícitas o señales de relevancia del orador, por ejemplo: "anoten", "recuerden", "tengan en cuenta", "esto es importante", "para el examen", "deben", "hay que", "no olviden", "la tarea es", "presten atención" y expresiones equivalentes según el contexto. Conserva la intención, el dato indicado y su timestamp. No conviertas comentarios casuales en órdenes.
Responde SOLO JSON válido con estas claves:
- summary: string
- key_points: array de strings
- outline: array de objetos {heading, details}
- milestones: array de objetos {time, title, detail}
- directives: array de objetos {time, cue, instruction, priority}
- research_queries: array de hasta 3 búsquedas concretas que ayudarían a ampliar o verificar el contenido; usa [] si no aporta valor
- flashcards: array de objetos {question,answer}
- quiz: array de 5 a 10 objetos {question,options,answer,explanation}; options debe contener exactamente 4 respuestas plausibles y answer debe ser el texto exacto de una opción

TEMA O CLASE: ${String(noteContext.topic_title || 'Sin tema asignado')}
NOMBRE DE LA NOTA: ${String(noteContext.title || '')}

TRANSCRIPCIÓN CON TIEMPOS:
${timestampedTranscript.slice(0, 120000)}`;
  const credential = await getCodexCredential(ownerId);
  if (!credential) throw new Error('Conecta Codex para procesar la nota.');
  const result = await runCodexTurn({ accessToken: credential.accessToken, idToken: credential.idToken, refreshToken: credential.refreshToken, accountId: credential.account_id, homeKey: ownerId, message: prompt, model: process.env.CODEX_MODEL, clientName: 'lumenote' });
  const parsed = parseJsonObject(result.answer);
  const discovered = await discoverReferences(parsed.research_queries);
  if (discovered.length) {
    const referencePrompt = `Alinea referencias reales con menciones concretas de esta transcripción. Responde SOLO JSON válido con la clave references, un array de objetos {title,url,source,time,connection}. Usa exclusivamente las URLs candidatas. Omite resultados irrelevantes y no inventes datos. El campo time debe corresponder al timestamp donde se menciona la idea relacionada.\n\nTRANSCRIPCIÓN:\n${timestampedTranscript.slice(0, 60000)}\n\nCANDIDATAS:\n${JSON.stringify(discovered)}`;
    try {
      const aligned = await runCodexTurn({ accessToken: credential.accessToken, idToken: credential.idToken, refreshToken: credential.refreshToken, accountId: credential.account_id, homeKey: ownerId, message: referencePrompt, model: process.env.CODEX_MODEL, clientName: 'lumenote-research' });
      parsed.references = parseJsonObject(aligned.answer).references || [];
    } catch (error) {
      console.warn('Reference alignment failed:', error.message);
      parsed.references = [];
    }
  } else parsed.references = [];
  await pool.query(`INSERT INTO note_ai_outputs(note_id,source_text,summary,study,status) VALUES($1,$2,$3,$4,'completed') ON CONFLICT(note_id) DO UPDATE SET source_text=excluded.source_text,summary=excluded.summary,study=excluded.study,status='completed',updated_at=now()`, [noteId, sourceText, String(parsed.summary || ''), JSON.stringify(parsed)]);
  return { ...parsed, threadId: result.threadId };
}

async function updateJob(noteId, values) {
  if (!pool) return;
  await pool.query(`UPDATE note_ai_outputs SET stage=$1, progress=$2, message=$3, status=$4, updated_at=now() WHERE note_id=$5`, [values.stage, values.progress, values.message, values.status || 'processing', noteId]);
}

async function extractMediaWithApi(file, instruction) {
  const mime = String(file.mimetype || '');
  if (mime.startsWith('text/') || /json|csv|markdown/i.test(mime) || /\.(txt|md|csv|json)$/i.test(String(file.originalname || ''))) {
    return file.buffer.toString('utf8');
  }
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'lumenote-extract-'));
  const extension = path.extname(String(file.originalname || '')) || (mime.includes('pdf') ? '.pdf' : mime.startsWith('image/') ? '.png' : '.bin');
  const inputPath = path.join(tempDir, `input${extension}`);
  await fs.writeFile(inputPath, file.buffer);
  try {
    if (mime.startsWith('image/') || /\.(png|jpe?g|webp|bmp|tiff?)$/i.test(extension)) {
      const { stdout } = await execFileAsync('tesseract', [inputPath, 'stdout', '-l', 'spa+eng', '--psm', '6'], { maxBuffer: 20 * 1024 * 1024 });
      return `${instruction}\n\n${stdout}`.trim();
    }
    if (mime.includes('pdf') || extension.toLowerCase() === '.pdf') {
      const { stdout } = await execFileAsync('pdftotext', ['-layout', inputPath, '-'], { maxBuffer: 50 * 1024 * 1024 });
      return stdout.trim();
    }
    if (mime.includes('wordprocessingml') || extension.toLowerCase() === '.docx') {
      const { stdout } = await execFileAsync('unzip', ['-p', inputPath, 'word/document.xml'], { maxBuffer: 50 * 1024 * 1024 });
      return stdout.replace(/<w:tab\/>/g, '\t').replace(/<w:br\/>/g, '\n').replace(/<\/w:p>/g, '\n').replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').trim();
    }
    throw new Error('Este formato todavía no tiene extractor local compatible.');
  } finally {
    await fs.rm(tempDir, { recursive: true, force: true });
  }
}

async function processMediaJob({ ownerId, noteId, file, language = 'es', speakerMode = 'single', speakerCount = 1, reservationId = null }) {
  try {
    await updateJob(noteId, { stage: 'preparing', progress: 8, message: 'Preparando el archivo…' });
    let sourceText = '';
    const isAudio = isAudioMedia(file);
    if (isAudio) {
      await updateJob(noteId, { stage: 'transcribing', progress: 25, message: 'Transcribiendo el audio con Codex…' });
      const credential = await getCodexCredential(ownerId);
      let transcription;
      const errors = [];
      // Prefer the local provider when configured: this is the OpenClaw-style
      // no-API-credit path for voice notes.
      if (!transcription) {
        try { transcription = await transcribeWithLocalWhisper({ file, language, speakerMode, speakerCount }); }
        catch (error) { errors.push(`Whisper local: ${error.message}`); }
      }
      if (!transcription && credential) {
        try { transcription = await transcribeWithCodex({ credential, file, language }); }
        catch (error) { errors.push(`Codex: ${error.message}`); }
      }
      if (!transcription?.text) throw new Error(errors.join(' | ') || 'No hay un transcriptor de audio disponible.');
      sourceText = transcription.text;
      await completeAudioQuota(reservationId);
      reservationId = null;
      await saveTranscriptForUser({ ownerId, noteId, text: sourceText, segments: transcription.segments || [] });
    } else {
      await updateJob(noteId, { stage: 'extracting', progress: 28, message: 'Leyendo el contenido del archivo…' });
      sourceText = await extractMediaWithApi(file, 'Extrae todo el texto y contenido relevante de este archivo para crear una nota de estudio. Describe una imagen con precisión.');
    }
    await updateJob(noteId, { stage: 'understanding', progress: 62, message: 'Entendiendo conceptos y estructura…' });
    const outputs = await generateNoteOutputs({ ownerId, noteId, sourceText });
    await updateJob(noteId, { stage: 'saving', progress: 92, message: 'Guardando resumen y material de estudio…' });
    await pool.query(`UPDATE note_ai_outputs SET source_text=$1, summary=$2, study=$3, status='completed', stage='completed', progress=100, message='Listo: contenido procesado.', updated_at=now() WHERE note_id=$4`, [sourceText, String(outputs.summary || ''), JSON.stringify(outputs), noteId]);
  } catch (error) {
    console.error('Process media job', error);
    await releaseAudioQuota(reservationId);
    await pool.query(`INSERT INTO note_ai_outputs(note_id,status,stage,progress,message,summary) VALUES($1,'error','error',100,$2,$3) ON CONFLICT(note_id) DO UPDATE SET status='error',stage='error',progress=100,message=excluded.message,summary=excluded.summary,updated_at=now()`, [noteId, error.message || 'No se pudo procesar la captura.', 'No se pudo completar el procesamiento.']);
  }
}

async function processTextJob({ ownerId, noteId, sourceText }) {
  try {
    await updateJob(noteId, { stage: 'understanding', progress: 35, message: 'Entendiendo el texto de la nota…' });
    const outputs = await generateNoteOutputs({ ownerId, noteId, sourceText });
    await updateJob(noteId, { stage: 'saving', progress: 92, message: 'Guardando resumen y material de estudio…' });
    await pool.query(`UPDATE note_ai_outputs SET source_text=$1, summary=$2, study=$3, status='completed', stage='completed', progress=100, message='Listo: contenido procesado.', updated_at=now() WHERE note_id=$4`, [sourceText, String(outputs.summary || ''), JSON.stringify(outputs), noteId]);
  } catch (error) {
    await pool.query(`INSERT INTO note_ai_outputs(note_id,status,stage,progress,message,summary) VALUES($1,'error','error',100,$2,$3) ON CONFLICT(note_id) DO UPDATE SET status='error',stage='error',progress=100,message=excluded.message,summary=excluded.summary,updated_at=now()`, [noteId, error.message || 'No se pudo procesar la nota.', 'No se pudo completar el procesamiento.']);
  }
}

app.get('/health', async (_req, res) => {
  let database = false;
  try { if (pool) { await pool.query('SELECT 1'); database = true; } } catch (_) {}
  res.json({ ok: true, provider: 'openai-api', configured: Boolean(client), database, codex: Boolean(process.env.CODEX_CLIENT_ID && process.env.CODEX_REDIRECT_URI && encryptionKey) });
});

app.get('/api/codex/auth/start', requireUser, async (req, res) => {
  try {
    requireCodexStorage();
    const ownerId = req.userId;
    const device = await requestDeviceCode();
    await pool.query('INSERT INTO codex_device_states(owner_id,device_auth_id,user_code,interval_seconds) VALUES($1,$2,$3,$4) ON CONFLICT(owner_id) DO UPDATE SET device_auth_id=excluded.device_auth_id,user_code=excluded.user_code,interval_seconds=excluded.interval_seconds,created_at=now()', [ownerId, device.deviceAuthId, device.userCode, device.interval]);
    res.json({ authorization_url: device.verificationUrl, user_code: device.userCode, interval: device.interval });
  } catch (error) { res.status(503).json({ error: error.message }); }
});

// Browser OAuth flow for the user's own ChatGPT plan. The device-code flow is
// kept above for environments without a configured redirect URI, but this is
// the preferred path because it requests the direct plan-use scope.
app.get('/api/codex/auth/oauth-start', requireUser, async (req, res) => {
  try {
    requireCodexStorage();
    const { state, verifier, challenge } = createPkceState();
    const hostId = crypto.randomUUID();
    await pool.query('INSERT INTO codex_oauth_states(owner_id,state,code_verifier,host_id) VALUES($1,$2,$3,$4)', [req.userId, state, verifier, hostId]);
    const authorizationUrl = buildAuthorizationUrl({ state, challenge, hostId });
    res.json({ authorization_url: authorizationUrl });
  } catch (error) { res.status(503).json({ error: error.message }); }
});

app.get('/api/codex/auth/device-status', requireUser, async (req, res) => {
  try {
    requireCodexStorage();
    const state = await pool.query('SELECT * FROM codex_device_states WHERE owner_id=$1', [req.userId]);
    if (!state.rowCount) return res.json({ connected: false, pending: false });
    const row = state.rows[0];
    const authorization = await pollDeviceCode({ deviceAuthId: row.device_auth_id, userCode: row.user_code, interval: row.interval_seconds, timeoutMs: 1000 });
    const token = await exchangeDeviceCode({ authorizationCode: authorization.authorization_code, codeVerifier: authorization.code_verifier });
    await pool.query(`INSERT INTO codex_credentials(owner_id,access_token_enc,id_token_enc,refresh_token_enc,expires_at,account_id,host_id) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(owner_id) DO UPDATE SET access_token_enc=excluded.access_token_enc,id_token_enc=excluded.id_token_enc,refresh_token_enc=excluded.refresh_token_enc,expires_at=excluded.expires_at,account_id=excluded.account_id,host_id=excluded.host_id,updated_at=now()`, [req.userId, encrypt(token.access_token), encrypt(token.id_token || token.access_token), encrypt(token.refresh_token), new Date(Date.now() + Number(token.expires_in || 3600) * 1000), accountIdFromToken(token.access_token), 'device-code']);
    await pool.query('DELETE FROM codex_device_states WHERE owner_id=$1', [req.userId]);
    res.json({ connected: true, pending: false });
  } catch (error) { res.json({ connected: false, pending: true, error: error.message }); }
});

app.get('/api/codex/auth/callback', async (req, res) => {
  try {
    requireCodexStorage();
    const { code, state, error: oauthError } = req.query;
    if (oauthError) return res.status(400).send(`Autorización cancelada: ${String(oauthError)}`);
    const stateResult = await pool.query('DELETE FROM codex_oauth_states WHERE state=$1 AND created_at > now() - interval \'10 minutes\' RETURNING *', [String(state || '')]);
    if (!stateResult.rowCount) return res.status(400).send('Estado OAuth inválido o expirado.');
    const token = await exchangeCode(String(code), stateResult.rows[0].code_verifier);
    if (!token.access_token || !token.refresh_token) throw new Error('La respuesta OAuth no incluyó los tokens requeridos.');
    await pool.query(`INSERT INTO codex_credentials(owner_id,access_token_enc,id_token_enc,refresh_token_enc,expires_at,account_id,host_id)
      VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(owner_id) DO UPDATE SET access_token_enc=excluded.access_token_enc, id_token_enc=excluded.id_token_enc, refresh_token_enc=excluded.refresh_token_enc, expires_at=excluded.expires_at, account_id=excluded.account_id, host_id=excluded.host_id, updated_at=now()`, [stateResult.rows[0].owner_id, encrypt(token.access_token), encrypt(token.id_token || token.access_token), encrypt(token.refresh_token), new Date(Date.now() + Number(token.expires_in || 3600) * 1000), accountIdFromToken(token.access_token), stateResult.rows[0].host_id]);
    res.type('html').send('<!doctype html><meta charset="utf-8"><title>Lumenote conectado</title><body><h2>Codex conectado a Lumenote</h2><p>Ya puedes volver a la aplicación.</p></body>');
  } catch (error) { console.error('Codex OAuth callback', error); res.status(502).send('No se pudo completar la autorización de Codex.'); }
});

app.get('/api/codex/auth/status', requireUser, async (req, res) => {
  try {
    requireCodexStorage();
    const result = await pool.query('SELECT account_id, expires_at, updated_at FROM codex_credentials WHERE owner_id=$1', [req.userId]);
    if (!result.rowCount) return res.json({ connected: false, plan_enabled: false, credential: null });
    res.json({ connected: true, plan_enabled: true, credential: result.rows[0], warning: null });
  } catch (error) { res.status(503).json({ connected: false, error: error.message }); }
});

app.post('/api/codex/chat', requireUser, async (req, res) => {
  try {
    const ownerId = req.userId;
    const message = String(req.body?.message || '').trim();
    if (!message) return res.status(400).json({ error: 'message es obligatorio.' });
    const credential = await getCodexCredential(ownerId);
    if (!credential) return res.status(401).json({ error: 'Conecta tu cuenta de ChatGPT/Codex primero.' });
    let noteContext = '';
    if (req.body?.note_id && pool) {
      const contextResult = await pool.query(`SELECT o.source_text, o.summary, o.study, n.title, n.topic_id FROM note_ai_outputs o JOIN notes n ON n.id=o.note_id WHERE o.note_id=$1 AND n.owner_id=$2`, [req.body.note_id, ownerId]);
      if (contextResult.rowCount) {
        const current = contextResult.rows[0];
        const all = current.topic_id ? await pool.query(`SELECT n.title, o.source_text, o.summary, o.study FROM note_ai_outputs o JOIN notes n ON n.id=o.note_id WHERE n.topic_id=$1 AND n.owner_id=$2 ORDER BY n.created_at ASC`, [current.topic_id, ownerId]) : contextResult;
        noteContext = all.rows.map((row) => `\nCAPTURA: ${row.title}\nCONTENIDO:\n${row.source_text || ''}\nRESUMEN:\n${row.summary || ''}\nESTUDIO:\n${JSON.stringify(row.study || {})}`).join('\n');
      }
    }
    const result = await runCodexTurn({ accessToken: credential.accessToken, idToken: credential.idToken, refreshToken: credential.refreshToken, accountId: credential.account_id, homeKey: ownerId, threadId: req.body?.thread_id || null, message: `${noteContext}\n\nPREGUNTA DEL USUARIO:\n${message}`, model: req.body?.model, clientName: 'lumenote' });
    if (req.body?.note_id && pool) await pool.query(`INSERT INTO codex_threads(owner_id,note_id,thread_id,model) VALUES($1,$2,$3,$4) ON CONFLICT(owner_id,note_id) DO UPDATE SET thread_id=excluded.thread_id, model=excluded.model, updated_at=now()`, [ownerId, req.body.note_id, result.threadId, req.body.model || null]);
    res.json(result);
  } catch (error) { console.error('Codex chat', error); res.status(502).json({ error: error.message || 'No se pudo consultar Codex.' }); }
});

app.post('/api/codex/transcribe', requireUser, upload.single('file'), async (req, res) => {
  let reservationId = null;
  try {
    if (!req.file) return res.status(400).json({ error: 'file es obligatorio.' });
    const credential = await getCodexCredential(req.userId);
    if (!credential) return res.status(401).json({ error: 'Conecta tu cuenta de Codex primero.' });
    const reservation = await reserveAudioQuota({ ownerId: req.userId, noteId: req.body?.note_id, file: req.file });
    reservationId = reservation.reservationId;
    const language = String(req.body?.language || 'es').split('-')[0].toLowerCase();
    const result = await transcribeWithCodex({ credential, file: req.file, model: req.body?.model, language });
    await completeAudioQuota(reservationId);
    reservationId = null;
    await saveTranscriptForUser({ ownerId: req.userId, noteId: req.body?.note_id, text: result.text, segments: result.segments });
    res.json(result);
  } catch (error) {
    await releaseAudioQuota(reservationId);
    console.error('Codex audio', error);
    res.status(error.status || 502).json({ error: error.message || 'No se pudo entender el audio con Codex.' });
  }
});

app.post('/api/notes/:id/process-media', requireUser, upload.single('file'), async (req, res) => {
  let reservationId = null;
  try {
    if (!req.file) return res.status(400).json({ error: 'file es obligatorio.' });
    const note = await pool.query('SELECT id FROM notes WHERE id=$1 AND owner_id=$2', [req.params.id, req.userId]);
    if (!note.rowCount) return res.status(404).json({ error: 'Nota no encontrada.' });
    const processingFile = { ...req.file, mediaType: String(req.body?.media_type || '') };
    if (isAudioMedia(processingFile)) {
      const reservation = await reserveAudioQuota({ ownerId: req.userId, noteId: req.params.id, file: processingFile });
      reservationId = reservation.reservationId;
    }
    const language = String(req.body?.language || 'es').split('-')[0].toLowerCase();
    const speakerMode = req.body?.speaker_mode === 'multi' ? 'multi' : 'single';
    const speakerCount = Math.max(1, Math.min(12, Number(req.body?.speaker_count) || (speakerMode === 'multi' ? 2 : 1)));
    await pool.query('UPDATE notes SET speaker_mode=$1, speaker_count=$2, updated_at=now() WHERE id=$3 AND owner_id=$4', [speakerMode, speakerCount, req.params.id, req.userId]);
    await pool.query(`INSERT INTO note_media(note_id,filename,mime_type,content) VALUES($1,$2,$3,$4) ON CONFLICT(note_id) DO UPDATE SET filename=excluded.filename,mime_type=excluded.mime_type,content=excluded.content,created_at=now()`, [req.params.id, req.file.originalname || 'captura', req.body?.media_type || req.file.mimetype || 'application/octet-stream', req.file.buffer]);
    await pool.query(`INSERT INTO note_ai_outputs(note_id,status,stage,progress,message,summary) VALUES($1,'processing','queued',0,'En cola para procesar…','') ON CONFLICT(note_id) DO UPDATE SET status='processing',stage='queued',progress=0,message='En cola para procesar…',updated_at=now()`, [req.params.id]);
    processMediaJob({ ownerId: req.userId, noteId: req.params.id, file: processingFile, language, speakerMode, speakerCount, reservationId }).catch(() => {});
    reservationId = null;
    res.status(202).json({ ok: true, status: 'processing', noteId: req.params.id });
  } catch (error) {
    await releaseAudioQuota(reservationId);
    console.error('Process media', error);
    res.status(error.status || 502).json({ error: error.message || 'No se pudo procesar la captura.' });
  }
});

app.post('/api/notes/:id/reprocess', requireUser, async (req, res) => {
  let reservationId = null;
  try {
    const result = await pool.query(`SELECT m.filename,m.mime_type,m.content,n.media_type FROM note_media m JOIN notes n ON n.id=m.note_id WHERE m.note_id=$1 AND n.owner_id=$2`, [req.params.id, req.userId]);
    if (!result.rowCount) return res.status(404).json({ error: 'No hay un archivo persistido para esta nota.' });
    await pool.query(`UPDATE note_ai_outputs SET status='processing',stage='queued',progress=0,message='Reprocesando el archivo…',updated_at=now() WHERE note_id=$1`, [req.params.id]);
    const row = result.rows[0];
    const file = { originalname: row.filename, mimetype: row.mime_type, mediaType: row.media_type, buffer: row.content };
    if (isAudioMedia(file)) {
      const reservation = await reserveAudioQuota({ ownerId: req.userId, noteId: req.params.id, file });
      reservationId = reservation.reservationId;
    }
    const note = await pool.query('SELECT speaker_mode, speaker_count FROM notes WHERE id=$1 AND owner_id=$2', [req.params.id, req.userId]);
    const speakerMode = note.rows[0]?.speaker_mode === 'multi' ? 'multi' : 'single';
    const speakerCount = Math.max(1, Math.min(12, Number(note.rows[0]?.speaker_count) || (speakerMode === 'multi' ? 2 : 1)));
    processMediaJob({ ownerId: req.userId, noteId: req.params.id, file, speakerMode, speakerCount, reservationId }).catch(() => {});
    reservationId = null;
    res.status(202).json({ ok: true, status: 'processing' });
  } catch (error) { await releaseAudioQuota(reservationId); res.status(error.status || 502).json({ error: error.message || 'No se pudo reprocesar la nota.' }); }
});

app.get('/api/notes/:id/media', requireUser, async (req, res) => {
  const result = await pool.query(`SELECT m.filename,m.mime_type,m.content FROM note_media m JOIN notes n ON n.id=m.note_id WHERE m.note_id=$1 AND n.owner_id=$2`, [req.params.id, req.userId]);
  if (!result.rowCount) return res.status(404).json({ error: 'Archivo no encontrado.' });
  const row = result.rows[0];
  res.setHeader('content-type', row.mime_type || 'application/octet-stream');
  res.setHeader('content-disposition', `attachment; filename="${row.filename}"`);
  res.send(row.content);
});

app.get('/api/notes/:id/insights', requireUser, async (req, res) => {
  if (!pool) return res.status(503).json({ error: 'DATABASE_URL no configurada.' });
  const result = await pool.query(`SELECT o.*, t.content AS transcript, COALESCE(t.segments, '[]'::jsonb) AS transcript_segments, n.speaker_mode, n.speaker_count, COALESCE(tp.title, '') AS topic_title
    FROM note_ai_outputs o
    JOIN notes n ON n.id=o.note_id
    LEFT JOIN transcripts t ON t.note_id=o.note_id
    LEFT JOIN topics tp ON tp.id=n.topic_id
    WHERE o.note_id=$1 AND n.owner_id=$2`, [req.params.id, req.userId]);
  res.json({ insights: result.rows[0] || null });
});

app.post('/api/notes/:id/process-text', requireUser, async (req, res) => {
  try {
    const sourceText = String(req.body?.text || '').trim();
    if (!sourceText) return res.status(400).json({ error: 'text es obligatorio.' });
    const note = await pool.query('SELECT id FROM notes WHERE id=$1 AND owner_id=$2', [req.params.id, req.userId]);
    if (!note.rowCount) return res.status(404).json({ error: 'Nota no encontrada.' });
    await pool.query(`INSERT INTO note_ai_outputs(note_id,status,stage,progress,message,source_text) VALUES($1,'processing','queued',0,'En cola para procesar…',$2) ON CONFLICT(note_id) DO UPDATE SET status='processing',stage='queued',progress=0,message='En cola para procesar…',source_text=excluded.source_text,updated_at=now()`, [req.params.id, sourceText]);
    processTextJob({ ownerId: req.userId, noteId: req.params.id, sourceText }).catch(() => {});
    res.status(202).json({ ok: true, status: 'processing', noteId: req.params.id });
  } catch (error) { res.status(502).json({ error: error.message || 'No se pudo procesar la nota.' }); }
});

app.get('/api/notes', requireUser, async (req, res) => {
  if (!pool) return res.status(503).json({ error: 'DATABASE_URL no configurada.' });
  const ownerId = req.userId;
  const result = await pool.query('SELECT n.*, t.title AS topic_title FROM notes n LEFT JOIN topics t ON t.id=n.topic_id WHERE n.owner_id = $1 ORDER BY n.created_at DESC', [ownerId]);
  res.json({ notes: result.rows });
});

app.get('/api/topics', requireUser, async (req, res) => {
  const result = await pool.query(`SELECT t.*, COUNT(n.id)::int AS note_count FROM topics t LEFT JOIN notes n ON n.topic_id=t.id WHERE t.owner_id=$1 GROUP BY t.id ORDER BY t.updated_at DESC`, [req.userId]);
  res.json({ topics: result.rows });
});

app.post('/api/topics', requireUser, async (req, res) => {
  const title = String(req.body?.title || '').trim();
  if (!title) return res.status(400).json({ error: 'title es obligatorio.' });
  const result = await pool.query('INSERT INTO topics(owner_id,title,description) VALUES($1,$2,$3) RETURNING *', [req.userId, title, String(req.body?.description || '')]);
  res.status(201).json({ topic: result.rows[0] });
});

app.patch('/api/topics/:id', requireUser, async (req, res) => {
  const title = String(req.body?.title || '').trim();
  if (!title) return res.status(400).json({ error: 'title es obligatorio.' });
  const result = await pool.query('UPDATE topics SET title=$1, description=$2, updated_at=now() WHERE id=$3 AND owner_id=$4 RETURNING *', [title, String(req.body?.description || ''), req.params.id, req.userId]);
  if (!result.rowCount) return res.status(404).json({ error: 'Tema no encontrado.' });
  res.json({ topic: result.rows[0] });
});

app.patch('/api/notes/:id/topic', requireUser, async (req, res) => {
  const topicId = req.body?.topic_id || null;
  if (topicId) {
    const topic = await pool.query('SELECT id FROM topics WHERE id=$1 AND owner_id=$2', [topicId, req.userId]);
    if (!topic.rowCount) return res.status(400).json({ error: 'Tema inválido.' });
  }
  const result = await pool.query('UPDATE notes SET topic_id=$1,updated_at=now() WHERE id=$2 AND owner_id=$3 RETURNING id,topic_id', [topicId, req.params.id, req.userId]);
  if (!result.rowCount) return res.status(404).json({ error: 'Nota no encontrada.' });
  res.json({ note: result.rows[0] });
});

app.post('/api/notes', requireUser, async (req, res) => {
  if (!pool) return res.status(503).json({ error: 'DATABASE_URL no configurada.' });
  const { title, source = 'manual', media_type = null, storage_path = null, topic_id = null } = req.body ?? {};
  const speakerMode = req.body?.speaker_mode === 'multi' ? 'multi' : 'single';
  const speakerCount = Math.max(1, Math.min(12, Number(req.body?.speaker_count) || (speakerMode === 'multi' ? 2 : 1)));
  if (!title?.trim()) return res.status(400).json({ error: 'title es obligatorio.' });
  const topic = topic_id ? await pool.query('SELECT id FROM topics WHERE id=$1 AND owner_id=$2', [topic_id, req.userId]) : { rowCount: 0 };
  if (topic_id && !topic.rowCount) return res.status(400).json({ error: 'Tema inválido.' });
  const result = await pool.query('INSERT INTO notes(owner_id, title, source, media_type, storage_path, topic_id, speaker_mode, speaker_count) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *', [req.userId, title.trim(), source, media_type, storage_path, topic_id, speakerMode, speakerCount]);
  res.status(201).json({ note: result.rows[0] });
});

app.patch('/api/notes/:id', requireUser, async (req, res) => {
  const title = String(req.body?.title || '').trim();
  if (!title) return res.status(400).json({ error: 'title es obligatorio.' });
  const result = await pool.query('UPDATE notes SET title=$1,updated_at=now() WHERE id=$2 AND owner_id=$3 RETURNING *', [title, req.params.id, req.userId]);
  if (!result.rowCount) return res.status(404).json({ error: 'Nota no encontrada.' });
  res.json({ note: result.rows[0] });
});

app.delete('/api/notes/:id', requireUser, async (req, res) => {
  if (!pool) return res.status(503).json({ error: 'DATABASE_URL no configurada.' });
  const result = await pool.query('DELETE FROM notes WHERE id = $1 AND owner_id = $2 RETURNING id', [req.params.id, req.userId]);
  if (!result.rowCount) return res.status(404).json({ error: 'Nota no encontrada.' });
  res.status(204).end();
});

app.post('/api/ai/chat', async (req, res) => {
  return res.status(410).json({ error: 'Esta ruta de pago fue deshabilitada. Usa la sesión individual de Codex.' });
  if (!client) return res.status(503).json({ error: 'OPENAI_API_KEY no configurada en el backend.' });
  const { message, noteContext = '', history = [] } = req.body ?? {};
  if (!message?.trim()) return res.status(400).json({ error: 'message es obligatorio.' });
  try {
    const input = [
      { role: 'system', content: 'Eres el tutor de Lumenote. Responde en español, con claridad y usando únicamente el contexto de la nota cuando exista.' },
      { role: 'user', content: `Contexto de la nota:\n${noteContext}\n\nHistorial:\n${history.map((x) => `${x.role || 'user'}: ${x.content || ''}`).join('\n')}\n\nPregunta:\n${message}` },
    ];
    const response = await client.responses.create({ model: process.env.OPENAI_CHAT_MODEL || 'gpt-4o-mini', input });
    res.json({ answer: response.output_text || 'No pude generar una respuesta.' });
  } catch (error) {
    console.error(error);
    res.status(502).json({ error: 'No se pudo consultar el modelo.' });
  }
});

app.post('/api/ai/transcribe', upload.single('file'), async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'file es obligatorio.' });
  try {
    // Free OpenClaw-style path: local STT first, never a metered API.
    try {
      const language = String(req.body?.language || 'es').split('-')[0].toLowerCase();
      const speakerMode = req.body?.speaker_mode === 'multi' ? 'multi' : 'single';
      const speakerCount = Math.max(1, Math.min(12, Number(req.body?.speaker_count) || (speakerMode === 'multi' ? 2 : 1)));
      const local = await transcribeWithLocalWhisper({ file: req.file, language, speakerMode, speakerCount });
      return res.json(local);
    } catch (localError) {
      console.warn('Whisper local no disponible:', localError.message);
    }
    const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    if (token && supabaseUrl && supabaseAnonKey) {
      const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, { headers: { apikey: supabaseAnonKey, authorization: `Bearer ${token}` } });
      if (userResponse.ok) {
        const user = await userResponse.json();
        try {
          const credential = await getCodexCredential(user.id);
          if (credential) {
            const language = String(req.body?.language || 'es').split('-')[0].toLowerCase();
            const result = await transcribeWithCodex({ credential, file: req.file, model: req.body?.model, language });
            await saveTranscriptForUser({ ownerId: user.id, noteId: req.body?.note_id, text: result.text, segments: result.segments });
            return res.json(result);
          }
        } catch (codexError) {
          console.warn('Codex audio no disponible; usando fallback configurado:', codexError.message);
        }
      }
    }
    return res.status(503).json({ error: 'No hay transcriptor local disponible.' });
  } catch (error) {
    console.error(error);
    res.status(502).json({ error: 'No se pudo transcribir el archivo.' });
  }
});

ensureSchema().then(() => app.listen(port, () => console.log(`Lumenote AI gateway listening on :${port}`))).catch((error) => { console.error('Database initialization failed', error); process.exit(1); });

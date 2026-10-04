import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import readline from 'node:readline';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const AUTH_URL = process.env.CODEX_AUTH_URL || 'https://auth.openai.com/api/accounts/authorize';
const TOKEN_URL = process.env.CODEX_TOKEN_URL || 'https://auth.openai.com/api/accounts/oauth/token';
const CLIENT_ID = process.env.CODEX_CLIENT_ID || '';
const REDIRECT_URI = process.env.CODEX_REDIRECT_URI || '';
// Direct ChatGPT-plan usage is a separate OAuth scope. Without it the
// credential can look connected while the app-server stream is rejected.
const OAUTH_SCOPES = process.env.CODEX_OAUTH_SCOPES || 'openid profile email offline_access chatgpt.tokens.use.direct';
const CODEX_PUBLIC_CLIENT_ID = process.env.CODEX_CLIENT_ID || 'app_EMoamEEZ73f0CkXaXp7hrann';
const CODEX_AUTH_BASE_URL = process.env.CODEX_AUTH_BASE_URL || 'https://auth.openai.com';
const CODEX_COMMAND = process.env.CODEX_COMMAND || 'codex';
const CODEX_ARGS_BASE = process.env.CODEX_APP_SERVER_ARGS_JSON
  ? JSON.parse(process.env.CODEX_APP_SERVER_ARGS_JSON)
  : ['app-server', '--listen', 'stdio://'];
// Use Codex's native ChatGPT runtime, the same path used by OpenClaw. The
// native runtime reads auth.json and routes through chatgpt.com/backend-api.
const CODEX_ARGS = CODEX_ARGS_BASE;

function requiredConfig() {
  if (!CLIENT_ID || !REDIRECT_URI) throw new Error('Configura CODEX_CLIENT_ID y CODEX_REDIRECT_URI.');
}

function base64url(value) {
  return Buffer.from(value).toString('base64url');
}

function randomString(bytes = 32) {
  return base64url(crypto.randomBytes(bytes));
}

export function createPkceState() {
  const verifier = randomString(48);
  const challenge = base64url(crypto.createHash('sha256').update(verifier).digest());
  return { state: randomString(32), verifier, challenge };
}

export function buildAuthorizationUrl({ state, challenge, hostId }) {
  requiredConfig();
  const url = new URL(AUTH_URL);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('client_id', CLIENT_ID);
  url.searchParams.set('redirect_uri', REDIRECT_URI);
  url.searchParams.set('scope', OAUTH_SCOPES);
  url.searchParams.set('state', state);
  url.searchParams.set('code_challenge', challenge);
  url.searchParams.set('code_challenge_method', 'S256');
  if (hostId) url.searchParams.set('ext_agent_host_id', hostId);
  return url.toString();
}

export async function requestDeviceCode() {
  const response = await fetch(`${CODEX_AUTH_BASE_URL}/api/accounts/deviceauth/usercode`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'user-agent': 'Lumenote/0.1' },
    body: JSON.stringify({ client_id: CODEX_PUBLIC_CLIENT_ID }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error || `Device auth failed (${response.status}).`);
  if (!body.device_auth_id || !(body.user_code || body.usercode)) throw new Error('OpenAI no devolvió un código de dispositivo válido.');
  return { deviceAuthId: body.device_auth_id, userCode: body.user_code || body.usercode, interval: Math.max(Number(body.interval) || 5, 1), verificationUrl: `${CODEX_AUTH_BASE_URL}/codex/device` };
}

export async function pollDeviceCode({ deviceAuthId, userCode, interval = 5, timeoutMs = 15 * 60 * 1000 }) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const response = await fetch(`${CODEX_AUTH_BASE_URL}/api/accounts/deviceauth/token`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'user-agent': 'Lumenote/0.1' },
      body: JSON.stringify({ device_auth_id: deviceAuthId, user_code: userCode }),
    });
    if (response.ok) return response.json();
    if (response.status !== 403 && response.status !== 404) throw new Error(`Device authorization failed (${response.status}).`);
    await new Promise((resolve) => setTimeout(resolve, interval * 1000));
  }
  throw new Error('La autorización de Codex expiró.');
}

export async function exchangeDeviceCode({ authorizationCode, codeVerifier }) {
  const response = await fetch(`${CODEX_AUTH_BASE_URL}/oauth/token`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', 'user-agent': 'Lumenote/0.1' },
    body: new URLSearchParams({ grant_type: 'authorization_code', code: authorizationCode, code_verifier: codeVerifier, client_id: CODEX_PUBLIC_CLIENT_ID, redirect_uri: `${CODEX_AUTH_BASE_URL}/deviceauth/callback` }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.access_token || !body.refresh_token) throw new Error(body.error || `Device token exchange failed (${response.status}).`);
  return body;
}

async function tokenRequest(body) {
  requiredConfig();
  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', accept: 'application/json' },
    body: new URLSearchParams({ client_id: CLIENT_ID, redirect_uri: REDIRECT_URI, ...body }),
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(`OAuth token exchange failed (${response.status}): ${json.error || 'unknown_error'}`);
  return json;
}

export function accountIdFromToken(accessToken) {
  try {
    const [, payload] = accessToken.split('.');
    const claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    const auth = claims['https://api.openai.com/auth'] || claims.auth || {};
    return auth.chatgpt_account_id || auth.account_id || claims.account_id || claims.sub || null;
  } catch (_) { return null; }
}

export function hasDirectChatGptPlanScope(accessToken) {
  try {
    const [, payload] = accessToken.split('.');
    const claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    const scopes = claims.scp || claims.scope || claims.scopes || [];
    return (Array.isArray(scopes) ? scopes : String(scopes).split(/\s+/)).includes('chatgpt.tokens.use.direct');
  } catch (_) { return false; }
}

export async function exchangeCode(code, verifier) {
  return tokenRequest({ grant_type: 'authorization_code', code, code_verifier: verifier });
}

export async function refreshAccessToken(refreshToken) {
  return tokenRequest({ grant_type: 'refresh_token', refresh_token: refreshToken });
}

function send(child, message) {
  child.stdin.write(`${JSON.stringify(message)}\n`);
}

function splitArgs() {
  return CODEX_ARGS.map((arg) => String(arg));
}

async function runCodexResponsesTurn({ accessToken, threadId, message, model }) {
  const response = await fetch('https://chatgpt.com/backend-api/codex/responses', {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
      originator: 'lumenote',
      'user-agent': 'lumenote/0.1',
    },
    body: JSON.stringify({
      model: model || process.env.CODEX_MODEL || 'gpt-5.5',
      input: [{ role: 'user', content: [{ type: 'input_text', text: message }] }],
      ...(threadId?.startsWith('resp_') ? { previous_response_id: threadId } : {}),
      stream: true,
      store: false,
    }),
    signal: AbortSignal.timeout(180000),
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error(`Codex Responses ${response.status}: ${detail.slice(0, 500)}`);
  }
  if (!response.body) throw new Error('Codex Responses no devolvió un stream.');
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let answer = '';
  let responseId = null;
  const consume = (line) => {
    if (!line.startsWith('data:')) return;
    const raw = line.slice(5).trim();
    if (!raw || raw === '[DONE]') return;
    let event;
    try { event = JSON.parse(raw); } catch (_) { return; }
    responseId ||= event.response?.id || event.id || null;
    if (event.type === 'response.output_text.delta') answer += event.delta || '';
    if (event.type === 'response.output_text.done' && !answer) answer = event.text || '';
    if (event.type === 'response.failed' || event.type === 'error') throw new Error(event.error?.message || event.message || 'Codex Responses falló.');
  };
  while (true) {
    const { value, done } = await reader.read();
    buffer += decoder.decode(value || new Uint8Array(), { stream: !done });
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || '';
    for (const line of lines) consume(line);
    if (done) break;
  }
  if (buffer) consume(buffer);
  if (!answer) throw new Error('Codex Responses terminó sin texto.');
  return { threadId: responseId || threadId || null, answer };
}

export async function runCodexTurn({ accessToken, idToken, refreshToken, accountId, homeKey = 'default', threadId, message, model, clientName = 'lumenote', version = '0.1.0' }) {
  // Direct Codex Responses is the reliable backend path. The app-server is
  // retained below for native tools, but its workspace-routing bootstrap is
  // currently unstable in headless deployments.
  return runCodexResponsesTurn({ accessToken, threadId, message, model });
  /* istanbul ignore next */
  const safeHomeKey = crypto.createHash('sha256').update(String(homeKey)).digest('hex').slice(0, 32);
  const codexHome = path.join(process.env.CODEX_USERS_HOME || path.join(os.tmpdir(), 'lumenote-codex-users'), safeHomeKey);
  await fs.mkdir(codexHome, { recursive: true });
  await fs.writeFile(path.join(codexHome, 'auth.json'), JSON.stringify({
    auth_mode: 'chatgpt',
    tokens: { access_token: accessToken, id_token: idToken || accessToken, refresh_token: refreshToken || '', account_id: accountId || undefined },
    last_refresh: new Date().toISOString(),
  }));
  const child = spawn(CODEX_COMMAND, splitArgs(), {
    env: {
      ...process.env,
      CODEX_HOME: codexHome,
      OPENAI_API_KEY: '',
      CODEX_API_KEY: '',
      CODEX_ACCESS_TOKEN: '',
    },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const lines = readline.createInterface({ input: child.stdout });
  let nextId = 1;
  let activeThreadId = threadId || null;
  let answer = '';
  let completed = false;
  let failure = null;
  const stderr = [];

  child.stderr.on('data', (chunk) => {
    const text = String(chunk);
    stderr.push(text);
    console.error('Codex app-server stderr:', text.trim().slice(0, 1000));
  });
  const waitFor = (predicate, timeoutMs = 120000) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Codex app-server timeout.')), timeoutMs);
    const onLine = (line) => {
      let event;
      try { event = JSON.parse(line); } catch (_) { return; }
      console.log('Codex app-server event:', event.method || (event.error ? 'error' : `response:${event.id || ''}`));
      if (event.error) failure = new Error(event.error.message || 'Codex app-server error.');
      if (event.method === 'error') {
        const detail = event.params?.error || event.params || {};
        const message = detail.message || detail.error || 'Codex app-server error.';
        console.error('Codex app-server protocol error:', JSON.stringify(detail).slice(0, 2000));
        failure = new Error(String(message));
      }
      if (event.method === 'item/agentMessage/delta') answer += event.params?.delta || event.params?.text || '';
      if (event.method === 'turn/completed') {
        completed = event.params?.turn?.status === 'completed' || event.params?.status === 'completed';
        if (!completed) failure = new Error(`Codex turn ${event.params?.turn?.status || event.params?.status || 'failed'}.`);
      }
      if (predicate(event) || event.method === 'error') { clearTimeout(timer); lines.off('line', onLine); resolve(event); }
    };
    lines.on('line', onLine);
  });

  try {
    send(child, { jsonrpc: '2.0', id: nextId++, method: 'initialize', params: { clientInfo: { name: clientName, title: 'Lumenote', version } } });
    await waitFor((event) => event.id === 1 || event.method === 'initialize');
    send(child, { jsonrpc: '2.0', method: 'initialized', params: {} });
    if (activeThreadId) {
      send(child, { jsonrpc: '2.0', id: nextId++, method: 'thread/resume', params: { threadId: activeThreadId } });
    } else {
      const selectedModel = model || process.env.CODEX_MODEL;
      send(child, { jsonrpc: '2.0', id: nextId++, method: 'thread/start', params: selectedModel ? { model: selectedModel } : {} });
      const started = await waitFor((event) => event.result?.thread?.id || event.method === 'thread/started');
      activeThreadId = started.result?.thread?.id || started.params?.thread?.id;
    }
    if (!activeThreadId) throw new Error('Codex no devolvió threadId.');
    send(child, { jsonrpc: '2.0', id: nextId++, method: 'turn/start', params: { threadId: activeThreadId, input: [{ type: 'text', text: message }] } });
    await waitFor((event) => event.method === 'turn/completed' || Boolean(event.error), 180000);
    if (failure || !completed) throw failure || new Error('Codex no completó el turno.');
    return { threadId: activeThreadId, answer };
  } finally {
    lines.close();
    child.kill();
  }
}

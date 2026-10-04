# Integración tipo OpenClaw/Codex

## Qué hace OpenClaw

OpenClaw separa tres piezas que no deben mezclarse:

1. **Identidad y autorización**: OAuth de OpenAI con PKCE. Genera `state`, `code_verifier` y `code_challenge`, abre el consentimiento en `auth.openai.com`, recibe el callback local y cambia el código por `access_token`, `refresh_token`, expiración e identidad de cuenta.
2. **Runtime**: ejecuta `codex app-server` como proceso hijo y se comunica por stdin/stdout con JSON Lines. El proceso recibe el token mediante una variable de entorno efímera.
3. **Conversación**: inicializa el app-server, inicia o reanuda un `thread`, envía `turn/start`, consume eventos de streaming y considera éxito únicamente cuando llega `turn/completed` con estado `completed`.

El callback documentado usa `http://localhost:1455/auth/callback`; para una máquina remota se puede usar túnel SSH o el flujo manual de pegar la URL de redirección. OpenClaw también contempla múltiples perfiles y renovación de tokens.

## Flujo que podemos reutilizar en Lumenote

```text
Flutter
  -> login OAuth PKCE en el dispositivo del usuario
  -> backend Lumenote: intercambia código y guarda refresh token cifrado
  -> backend inicia Codex app-server por usuario
  -> JSONL initialize / initialized
  -> thread/start o thread/resume
  -> turn/start
  -> eventos delta
  -> turn/completed
```

Para Lumenote se recomienda mantener dos rutas independientes:

- **Transcripción, resúmenes y procesamiento de archivos**: proveedor de API de servidor mediante `OPENAI_API_KEY` o un proveedor compatible configurado por el propietario.
- **Chat/agente conectado al plan del usuario**: OAuth de ChatGPT/Codex y `codex app-server`, siempre con autorización explícita del usuario y tokens aislados por cuenta.

## Componentes internos propuestos

- `oauth_sessions`: usuario, provider, estado PKCE, scopes, expiración y metadatos; nunca guardar el `code_verifier` después del intercambio.
- `provider_credentials`: refresh token cifrado con una clave del servidor, access token únicamente en memoria o almacenamiento temporal protegido, `account_id`, `expires_at` y versión de rotación.
- `agent_threads`: usuario, thread de Codex, modelo, título y último estado; no guardar tokens en esta tabla.
- `codex-runtime`: wrapper de Node que inicia el binario administrado, escribe JSONL y valida eventos/estado.

El backend debe aplicar aislamiento por `owner_id`, límites de tamaño y tiempo, cancelación del proceso hijo, renovación con mutex por cuenta y borrado/revocación local. Las respuestas del agente se deben asociar al `note_id` de Lumenote, pero el hilo de Codex debe conservar su propio identificador.

## Lo que no debemos copiar

- No reutilizar cookies de `chatgpt.com`, endpoints internos del sitio, ni tokens tomados de otra instalación de Codex.
- No construir un proxy que comparta una sesión de ChatGPT Plus entre usuarios.
- No exponer access/refresh tokens al cliente Flutter, logs, URLs, Supabase público o GitHub.
- No usar el catálogo de modelos como prueba de autorización: la inferencia completada es la que confirma acceso al modelo.

La implementación correcta para el producto es el flujo oficial de **Sign in with ChatGPT/Codex app-server**, con autorización individual y controles de seguridad. Para un MVP podemos empezar por el login OAuth y una sesión de chat; después añadir renovación, reanudación de hilos y colas para transcripción.

## Referencias estudiadas

- OpenAI Developers: [Codex app-server – Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)
- OpenClaw: [OAuth](https://github.com/openclaw/openclaw/blob/main/docs/concepts/oauth.md)
- OpenClaw: [OpenAI provider](https://github.com/openclaw/openclaw/blob/main/docs/providers/openai.md)
- OpenClaw: [Agent runtimes](https://github.com/openclaw/openclaw/blob/main/docs/concepts/agent-runtimes.md)
- OpenClaw: [Codex harness](https://github.com/openclaw/openclaw/blob/main/docs/plugins/codex-harness.md)
- Implementación de referencia: [openai-chatgpt-oauth-flow.runtime.ts](https://github.com/openclaw/openclaw/blob/main/extensions/openai/openai-chatgpt-oauth-flow.runtime.ts)

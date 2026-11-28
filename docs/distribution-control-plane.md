# Panel de distribución y operación de Lumenote

## Objetivo

Que el equipo gestione Lumenote Cloud y que una persona/partner pueda operar su propia instalación o marca sin recibir acceso a otras cuentas. El panel es un plano de control; las notas, medios y conversaciones permanecen aislados por tenant y no se deben copiar al plano de control.

## Dos consolas, permisos no intercambiables

### Consola de operador Lumenote

- Alta, pausa, baja y estado operativo de cada tenant/partner.
- Plan, estado de pago, consumo agregado, cuota y señales de riesgo; nada de leer contenido privado de notas por defecto.
- Configuración de dominios, branding, temas, logos y recursos remotos.
- Estado de despliegue, versión de backend/web, canal stable/beta, migraciones pendientes y compatibilidad mínima de apps.
- Servicios conectados, estado de jobs, salud/latencia, colas atascadas, límites y eventos webhook.
- Códigos promocionales, periodo de prueba, soporte y auditoría de cambios.

Solo el rol de operador/plataforma puede entrar. No usar un boolean `is_founder` global como única autorización; exigir rol de plataforma separado, MFA y registro de auditoría.

### Consola del tenant/partner

- Gestionar miembros, invitaciones, roles y asignación de membresías dentro de su organización.
- Configurar branding/dominio si el plan contratado lo permite.
- Elegir proveedores propios y cuotas si es instalación self-hosted.
- Ver uso agregado, exportar informes y administrar servicio; no cambiar entitlements que determina la plataforma en Lumenote Cloud.
- Generar enlaces de invitación o checkout solo para los productos aprobados por el operador; no definir cargos arbitrarios ni tocar webhooks.

Un despliegue self-hosted concede rol `instance_owner` a quien opera esa instancia. Ese usuario controla su propia base y configuración, no una cuenta maestra de Lumenote Cloud.

## Modelo de datos objetivo

Introducir estas entidades de forma aditiva, antes de mover filas:

- `tenants`: id, slug, owner, lifecycle, deployment_mode (`cloud`/`self_hosted`), plan, locale, timestamps.
- `tenant_members`: tenant_id, user_id, role, status, invited_at, joined_at; unique tenant/user.
- `tenant_branding`: tenant_id, app_name, palette, logo/mascot/splash URLs, domain, version.
- `tenant_entitlements`: tenant_id, plan/version, limits/features, period, source; el servidor es la autoridad.
- `tenant_provider_connections`: referencias/estado, no secretos en claro en PostgreSQL compartido; secretos cifrados o del secret manager del despliegue.
- `audit_log`, `release_channels`, `release_manifests`, `support_cases`, `billing_webhook_events`.

Todo recurso de usuario se filtra por tenant y dueño cuando aplique. Aislamiento obligatorio en SQL/RLS, backend y pruebas de acceso cruzado. Migración: crear tenant personal para cada usuario existente, asignarlo como owner, backfill de branding/membresías, validar conteos e IDs, activar lectura dual temporal, y después eliminar el camino antiguo solo en una release compatible.

## Releases y distribución

- Publicar imágenes Docker versionadas e inmutables (`api`, `web`, opcional `whisper`) en GHCR; conservar tags de versión y digest. Ofrecer `docker compose` para instalaciones pequeñas y documentación de backup/upgrade/rollback.
- Manifiesto firmado con versión, migraciones compatibles, hashes de assets y canal. Administrador puede promover stable/beta, programar el cambio y revertir assets/config.
- Web puede actualizar frontend/assets desde el despliegue sin descargar binario.
- Android/iOS: actualización de código/binario por Google Play/App Store/TestFlight o canal de distribución autorizado. No prometer hot update arbitrario de código nativo; solo branding/contenido remoto compatible, con versionado, firma y cache control.
- Generación de marca/build por partner puede ser fase posterior. Las credenciales de firma de apps son del dueño de la app, aisladas en su pipeline; nunca se almacenan en el panel como texto abierto.

## Comercialización y límites

Primera fase: Lumenote vende membresías directamente (Polar recomendado para empezar como MoR; confirmar elegibilidad y contrato de payouts), y partners administran sus propias instalaciones. No ofrecer revenue-share ni “revender suscripciones” hasta definir entidad legal, impuestos, soporte, chargebacks y conciliación. Si después se necesita split de pagos, analizar Stripe Connect/marketplace como proyecto separado; usar Whop solo si su canal de afiliados/marketplace es estratégico.

## Entrega por etapas

1. **Fundación (ahora):** un backend API, proveedor de membresías desacoplado, cuotas aplicadas por servidor, Docker reproducible, plan self-hosted documentado, roles actuales no ampliados.
2. **Tenant model:** migración de identidad y datos; políticas de acceso cruzado; test fixtures con dos tenants; panel de administración por tenant.
3. **Operaciones Cloud:** consola de plataforma, planes/usage, auditoría, health, releases, branding y dominios.
4. **Distribución partners:** invitaciones, branding aislado, export/import, imágenes Docker firmadas, versiones y canal beta/stable.
5. **Payouts de partners:** si hay demanda probada, revisar Stripe Connect y estructura fiscal/legal; no simularlo con créditos o cupones.

## Criterios de lanzamiento

- Un usuario de tenant A no puede leer/modificar perfiles, branding, miembros, notas, medios, uso ni cobros de tenant B.
- Un tenant admin no puede crear operadores globales ni cambiar el proveedor/tarifa de Lumenote Cloud.
- Dos despliegues self-hosted con distintos secrets y bases arrancan siguiendo solo la guía pública.
- Hay backup/restore probado, auditoría, migración reversible o plan de rollback, y pruebas de los webhooks duplicados/reordenados.
- La distribución móvil declara el canal de actualización real y no promete que se despliegue código iOS/Android remoto.

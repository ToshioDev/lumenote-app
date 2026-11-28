# Membresías y lanzamiento comercial (propuesta)

## Estado actual

- Planes provisionados: Gratis (60 min/mes), Plus (600 min/mes), Pro (2,400 min/mes). Son cuotas existentes del producto, no promesas de capacidad ya validadas.
- La base queda preparada para guardar precio mensual/anual en MXN y proveedor/IDs externos sin acoplar la membresía a un procesador.
- El cliente solo puede leer o borrar su propia fila de suscripción; altas/cambios de plan deben pasar por backend Founder o por webhooks verificados.
- El backend reserva y cobra minutos de audio de forma atómica mediante RPC; fallos de transcripción liberan la reserva y reprocesar consume cuota de nuevo. La migración debe aplicarse al proyecto Supabase antes de desplegar este backend.
- No se cobra todavía: faltan precios aprobados, cuenta comercial, productos/precios del proveedor, endpoints de checkout/portal/webhook y prueba en sandbox. La aplicación debe decirlo con claridad.

## Distribución: comunidad y SaaS

La misma versión pública debe admitir dos modos de despliegue, sin mantener un “backend open-source” y otro privado:

| Modo | Quién opera la infraestructura | Ingresos de Lumenote | Costos/dependencias |
| --- | --- | --- | --- |
| Autoalojado | La persona que instala el repo | Ninguno por uso del código | Su servidor, base de datos, almacenamiento y proveedor de IA o Whisper local |
| Lumenote Cloud | Nuestro equipo | Membresías Plus/Pro y cuotas administradas | Servidores, transcripción, almacenamiento, soporte, pagos e impuestos |

Un solo API modular mantiene auth, permisos, notas, jobs, cuotas, proveedores IA, pagos y webhooks bajo `/api`; los adaptadores intercambiables implementan los proveedores. Whisper local puede seguir siendo un contenedor interno opcional por su modelo/peso y aislamiento de recursos: no constituye un segundo backend público y no expone puerto a internet. PostgreSQL es la base transaccional de Lumenote. Supabase Auth/Storage continúa siendo una dependencia separada en esta fase; el autoalojado configura su propio proyecto Supabase o un stack compatible. No presentar la instalación como “todo incluido” hasta automatizar también ese servicio.

Variables/secrets de proveedores se configuran solo en cada despliegue: los usuarios autoalojados ponen sus propias claves y la app SaaS usa las de nuestra infraestructura. Nunca publicar claves de Codex, OpenAI, Supabase service-role, Polar, ni secretos de webhook en el repo o en el cliente Flutter. Las funciones cloud —backup, cola duradera, soporte, cuotas administradas, correo y checkout— pueden diferenciar la comodidad de la membresía; el código abierto conserva uso con servicios propios.

**Licencia pendiente de aprobación.** MIT permite uso comercial amplio y máxima adopción; AGPLv3 exige compartir modificaciones de red derivadas bajo su alcance y encaja mejor si se quiere reducir forks SaaS cerrados, pero conviene revisión legal. “Source available” no equivale a código abierto según OSI. No añado una licencia hasta que se elija deliberadamente.

## Oferta que probaría primero

Mantener tres niveles para que sea fácil decidir, con facturación mensual y anual (anual con descuento solo después de conocer margen y retención):

| Nivel | Uso | Propuesta de valor |
| --- | --- | --- |
| Gratis | Probar el ciclo de temas, notas y estudio; cuota pequeña de transcripción | Llegar al primer apunte útil sin tarjeta |
| Plus | Uso frecuente individual; cuota intermedia | Transcripción, resumen, chat y material de estudio del contenido propio |
| Pro | Uso intensivo y sesiones largas; mayor cuota y procesamiento prioritario si la operación lo soporta | Para semestre completo, proyectos o investigación |

No publicar los minutos como “ilimitados”. Mostrar cuota mensual, qué cuenta como minuto, reinicio de periodo, formatos/duración máxima por archivo y comportamiento al agotarse. Antes de cobrar, medir costo de inferencia/almacenamiento por hora, costo de soporte, tarifas del proveedor e impuestos. Ajustar minutos/precio con cohortes de prueba; ofrecer mensual/anual, periodo de prueba solo si el soporte de cancelación y fraude está listo.

## Recomendación de proveedor

**Polar como primera opción de lanzamiento internacional; Stripe como alternativa si el foco inicial es México y Lumenote ya tiene resuelta la gestión fiscal.** Polar admite vendedores de México, opera como Merchant of Record para ventas digitales y publica tarifas; su tarifa Starter actual aparece como 5% + USD 0.50, con 1.5% adicional para tarjetas internacionales. Confirmar la tarifa vigente en el dashboard antes de fijar precios. Polar mueve más carga de impuestos indirectos fuera del equipo, a cambio de más comisión y menor control del modelo de cobro. [Países soportados](https://docs.polar.sh/merchant-of-record/supported-countries), [tarifas](https://docs.polar.sh/merchant-of-record/fees), [alcance MoR](https://docs.polar.sh/merchant-of-record/introduction).

Stripe sería la alternativa de menor procesamiento en México: el precio publicado para tarjeta nacional es 3.6% + MXN 3; Billing añade 0.7% del volumen de Billing. Es más controlable y tiene Checkout y portal de cliente, pero Lumenote debe ocuparse de su propia obligación fiscal y conciliación. [Precios Stripe México](https://stripe.com/mx/pricing), [Stripe Billing](https://stripe.com/mx/billing/pricing).

Whop soporta planes recurrentes y MXN, pero lo elegiría solo si el canal de distribución/afiliados/marketplace de Whop aporta ventas que no obtendríamos con checkout propio. Añade una dependencia de plataforma sin una ventaja clara para la experiencia de notas SaaS. [Planes y precios](https://docs.whop.com/api-reference/plans/create-plan).

## Flujo de compra que debemos implementar

1. La app solicita a nuestro backend un checkout para un `plan_code` permitido; jamás envía monto ni IDs arbitrarios ni guarda credenciales del proveedor.
2. Backend crea la sesión asociada al `user_id` autenticado, devuelve una URL de checkout hospedada y la app la abre en navegador del sistema.
3. El retorno de checkout solo muestra “confirmando”; no otorga derechos. Un webhook con firma válida confirma pago/renovación, se deduplica por `event_id` y actualiza la suscripción.
4. El backend aplica el periodo, cuota, gracia por impago y cancelación al cierre del periodo. La cancelación conserva acceso pagado hasta `current_period_end`; fallo de pago queda en `past_due` durante una ventana definida.
5. “Administrar membresía” abre un enlace autenticado al portal del proveedor; no se procesan tarjetas dentro de Flutter.
6. Refund/disputa suspende o revoca según política aprobada; cada transición queda en registro auditable. Webhooks repetidos y fuera de orden deben ser idempotentes y comprobar versión/fecha del estado.

## Antes de activar cobros

- Founder debe aprobar precios, frecuencia anual/descuento, impuestos, reembolsos, cancelación, gracia y cuotas por nivel.
- Abrir la organización de Polar y completar identidad/beneficiario/payout; crear productos con precios mensual y anual para Plus y Pro; crear token de servidor y secreto de webhook; configurar sandbox primero.
- Antes de anunciar cuotas, aplicar la migración y probar medición con varios formatos, sesiones largas, reintentos, solicitudes simultáneas, fallos del transcriptor y reinicio UTC mensual. La API mide audio con `ffprobe`, redondea hacia arriba al minuto y rechaza cuando no puede medir o reservar.
- Pasar pruebas: compra aprobada, pago fallido, renovación, cancelación fin de periodo, refund, webhook duplicado, usuario existente que compra, y compra iniciada por una cuenta que después cierra sesión.
- Revisar términos de suscripción, aviso de renovación, privacidad, soporte y tratamiento fiscal con asesoría adecuada al domicilio de quien venda.

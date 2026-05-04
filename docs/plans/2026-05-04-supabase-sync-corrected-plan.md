# Plan Corregido: sincronizacion Supabase local-first para Muesli

> **Estado:** Implementado el 2026-05-04 sobre la rama `beta`. El detalle del
> resultado vive en `docs/progress.md` (entrada 2026-05-04) y los puntos de
> divergencia respecto a este plan se anotan en línea como `Implementation
> note` cuando aplica.

Este documento reemplaza a nivel practico la propuesta de `2026-04-28-supabase-sync-plan.md`.

Esta version esta escrita para que otro agente pueda implementarla sin asumir contexto previo del proyecto.

## 1. Objetivo

Agregar sincronizacion multi-dispositivo usando Supabase sin romper el enfoque local-first de Muesli y sin pelearse innecesariamente con cambios upstream.

El producto final debe permitir que el mismo usuario use Muesli en varias Macs y vea los mismos:

- `meetings`
- `dictations`
- `meeting_folders`
- `customMeetingTemplates`
- preferencias minimas asociadas a templates y organizacion
- `customWords`

La base local sigue siendo la base operativa del app. Supabase es una capa de replicacion y reconciliacion, no la fuente primaria de UI.

## 2. Restricciones duras del repo actual

Estas decisiones salen del estado real del codigo y no deben cambiarse en esta iniciativa:

- La app usa SQLite local y el CRUD principal vive en `native/MuesliNative/Sources/MuesliCore/DictationStore.swift`.
- `meetings` no es una tabla simple: hoy incluye `calendar_event_id`, `calendar_event_snapshot`, `mic_audio_path`, `system_audio_path`, `saved_recording_path`, `meeting_status`, `manual_notes`, y metadatos de template.
- `meeting_folders` no es plana: hoy incluye `parent_folder_id`, `color_hex` e `icon_name`.
- Configuracion de usuario vive en `config.json` a traves de `ConfigStore` y `AppConfig`, no en SQLite.
- Existen reuniones en estados vivos (`recording`, `processing`) que no deben sincronizarse mientras estan activas.
- Existen deletes fisicos locales hoy. No se puede asumir que ya existe soft delete local.

Referencias:

- `native/MuesliNative/Sources/MuesliCore/DictationStore.swift`
- `native/MuesliNative/Sources/MuesliCore/StorageModels.swift`
- `native/MuesliNative/Sources/MuesliNativeApp/Models.swift`
- `native/MuesliNative/Sources/MuesliNativeApp/ConfigStore.swift`

## 3. Decisiones de arquitectura

### 3.1 Decision principal

No modificar el schema funcional de `dictations`, `meetings` y `meeting_folders` para meter `sync_id`, `updated_at` o `deleted_at`.

En su lugar:

- se conserva el schema funcional tal como esta;
- se agregan tablas auxiliares de sync dentro del mismo SQLite;
- se agregan triggers que actualizan solo metadata de sync;
- se agrega un repositorio de sync separado que habla directo con SQLite;
- `DictationStore` sigue siendo el CRUD del producto;
- la logica de sync nunca reescribe el comportamiento existente del app.

Esta es la decision mas importante para minimizar choque con upstream.

### 3.2 Por que no usar `updated_at` dentro de las tablas principales

No usar el enfoque del plan anterior basado en triggers que mutan `updated_at` en las tablas de dominio.

Razon:

- cuando bajemos cambios remotos y hagamos `UPDATE` local, esos triggers volverian a marcar el row como editado por el usuario local;
- eso genera re-subidas falsas, bucles, y resolucion de conflictos incorrecta.

La seleccion de filas para upload no debe basarse en `updated_at` de la tabla principal. Debe basarse en metadata de sync separada y en un flag `dirty`.

### 3.3 Modelo de consistencia

Esto es sync personal entre dispositivos del mismo usuario, no colaboracion multiusuario.

Por tanto:

- la politica de conflicto sera `last-write-wins` a nivel de entidad;
- el timestamp de comparacion sera `client_updated_at`;
- en empate exacto, gana el `device_id` lexicograficamente mayor;
- si las cargas canonicas son identicas, se considera no-conflicto aunque cambie la version remota.

Esto es aceptable para una app personal multi-Mac, pero no es un CRDT ni colaboracion segura en tiempo real.

## 4. Datos que SI y NO se sincronizan

### 4.1 Se sincronizan

#### Dictations

- `timestamp`
- `duration_seconds`
- `raw_text`
- `app_context`
- `word_count`
- `source`
- `started_at`
- `ended_at`

#### Meetings

Solo para reuniones con estado terminal:

- `completed`
- `note_only`
- `failed`

Campos sincronizados:

- `title`
- `calendar_event_id`
- `calendar_event_snapshot`
- `start_time`
- `end_time`
- `duration_seconds`
- `raw_transcript`
- `formatted_notes`
- `meeting_status`
- `manual_notes`
- `word_count`
- `selected_template_id`
- `selected_template_name`
- `selected_template_kind`
- `selected_template_prompt`
- relacion con carpeta

#### Meeting folders

- `name`
- `parent_folder_id`
- `color_hex`
- `icon_name`
- `sort_order` si en el futuro pasa a usarse; hoy no debe ser obligatorio para la logica

#### Preferencias sincronizadas

Desde `AppConfig`:

- `customMeetingTemplates`
- `defaultMeetingTemplateID`
- `autoTemplateTargetID`
- `meetingTitlePrompt`
- `hiddenBuiltInTemplateIDs`
- `customWords`
- `folderOrder`

### 4.2 No se sincronizan

Nunca deben subir a Supabase:

- `openAIAPIKey`
- `openRouterAPIKey`
- tokens de ChatGPT
- tokens de Google Calendar
- hotkeys
- modelos STT y modelos de summary
- settings visuales y de ventana
- onboarding state
- `hiddenLocalCalendarIDs`
- `hiddenCalendarEventIDs`
- flags de permisos locales
- `mic_audio_path`
- `system_audio_path`
- `saved_recording_path`
- archivos de audio
- cualquier ruta local del filesystem

## 5. Diseño local: tablas auxiliares de sync en SQLite

Crear estas tablas desde un nuevo repositorio de sync, no desde `DictationStore` salvo que haga falta compartir utilidades.

### 5.1 Tabla `sync_metadata`

Una fila por entidad local sincronizable.

```sql
CREATE TABLE IF NOT EXISTS sync_metadata (
    entity_type TEXT NOT NULL,                 -- dictation | meeting | folder
    local_id INTEGER NOT NULL,
    remote_id TEXT,                            -- UUID remoto
    client_updated_at TEXT NOT NULL,           -- ISO8601 UTC del ultimo cambio local o remoto aplicado
    remote_version INTEGER NOT NULL DEFAULT 0, -- version conocida en Supabase
    last_seen_server_updated_at TEXT,          -- ISO8601 UTC de Supabase
    last_payload_hash TEXT,                    -- SHA256 del payload canonico sincronizado
    dirty INTEGER NOT NULL DEFAULT 1,          -- 1 = hay que subir
    last_writer_device_id TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (entity_type, local_id),
    UNIQUE (entity_type, remote_id)
);

CREATE INDEX IF NOT EXISTS idx_sync_metadata_dirty
ON sync_metadata(entity_type, dirty, client_updated_at);
```

### 5.2 Tabla `sync_tombstones`

Registra deletes locales aunque la fila de dominio ya no exista.

```sql
CREATE TABLE IF NOT EXISTS sync_tombstones (
    entity_type TEXT NOT NULL,                 -- dictation | meeting | folder
    local_id INTEGER NOT NULL,
    remote_id TEXT,
    client_deleted_at TEXT NOT NULL,           -- ISO8601 UTC
    last_known_remote_version INTEGER NOT NULL DEFAULT 0,
    dirty INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (entity_type, local_id)
);

CREATE INDEX IF NOT EXISTS idx_sync_tombstones_dirty
ON sync_tombstones(entity_type, dirty, client_deleted_at);
```

### 5.3 Tabla `sync_state`

Cursores, flags y estado global del subsistema.

```sql
CREATE TABLE IF NOT EXISTS sync_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

Claves esperadas:

- `device_id`
- `preferences_dirty`
- `preferences_remote_version`
- `preferences_client_updated_at`
- `preferences_last_seen_server_updated_at`
- `preferences_last_payload_hash`
- `pull_cursor:dictations`
- `pull_cursor:meetings`
- `pull_cursor:meeting_folders`
- `pull_cursor:user_preferences`

El valor de cada cursor sera JSON:

```json
{"server_updated_at":"2026-05-04T10:20:30.123Z","id":"uuid-or-user-id"}
```

## 6. Triggers locales

Crear triggers sobre las tablas principales para marcar metadata de sync.

### 6.1 Insert / update

Para `dictations`, `meetings` y `meeting_folders`:

- `AFTER INSERT` => upsert en `sync_metadata`, `dirty=1`, `client_updated_at=now UTC`
- `AFTER UPDATE` => upsert en `sync_metadata`, `dirty=1`, `client_updated_at=now UTC`

Importante:

- no se tocan columnas de la tabla principal;
- el manager de sync usara `dirty`, no `updated_at` del row de dominio.

### 6.2 Delete

Para `dictations`, `meetings` y `meeting_folders`:

- `BEFORE DELETE` => copiar `remote_id` y `remote_version` desde `sync_metadata` hacia `sync_tombstones`
- `AFTER DELETE` => borrar la fila correspondiente de `sync_metadata`

### 6.3 Efecto de aplicar cambios remotos

Los triggers tambien van a dispararse cuando `SyncRepository` haga inserts/updates por cambios remotos.

Eso es correcto.

Despues de aplicar un cambio remoto, `SyncRepository` debe corregir inmediatamente `sync_metadata` para dejar:

- `dirty=0`
- `remote_id=<uuid remoto>`
- `remote_version=<version remota>`
- `client_updated_at=<client_updated_at remoto>`
- `last_seen_server_updated_at=<server_updated_at remoto>`
- `last_payload_hash=<hash payload remoto>`
- `last_writer_device_id=<device remoto>`

Este paso es obligatorio. Sin esto, el row quedaria sucio por culpa del trigger.

## 7. Diseño remoto en Supabase

Usar cuatro tablas de negocio sincronizadas y una opcional de dispositivos.

### 7.1 `meeting_folders`

```sql
CREATE TABLE public.meeting_folders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    parent_folder_id UUID REFERENCES public.meeting_folders(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    color_hex TEXT,
    icon_name TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    client_updated_at TIMESTAMPTZ NOT NULL,
    server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    remote_version BIGINT NOT NULL DEFAULT 1,
    last_writer_device_id TEXT NOT NULL,
    deleted_at TIMESTAMPTZ
);
```

### 7.2 `meetings`

```sql
CREATE TABLE public.meetings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    folder_id UUID REFERENCES public.meeting_folders(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    calendar_event_id TEXT,
    calendar_event_snapshot JSONB,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    duration_seconds DOUBLE PRECISION,
    raw_transcript TEXT NOT NULL DEFAULT '',
    formatted_notes TEXT NOT NULL DEFAULT '',
    meeting_status TEXT NOT NULL,
    manual_notes TEXT NOT NULL DEFAULT '',
    word_count INTEGER NOT NULL DEFAULT 0,
    selected_template_id TEXT,
    selected_template_name TEXT,
    selected_template_kind TEXT,
    selected_template_prompt TEXT,
    client_updated_at TIMESTAMPTZ NOT NULL,
    server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    remote_version BIGINT NOT NULL DEFAULT 1,
    last_writer_device_id TEXT NOT NULL,
    deleted_at TIMESTAMPTZ
);
```

### 7.3 `dictations`

```sql
CREATE TABLE public.dictations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL,
    duration_seconds DOUBLE PRECISION,
    raw_text TEXT NOT NULL DEFAULT '',
    app_context TEXT NOT NULL DEFAULT '',
    word_count INTEGER NOT NULL DEFAULT 0,
    source TEXT NOT NULL DEFAULT 'dictation',
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    client_updated_at TIMESTAMPTZ NOT NULL,
    server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    remote_version BIGINT NOT NULL DEFAULT 1,
    last_writer_device_id TEXT NOT NULL,
    deleted_at TIMESTAMPTZ
);
```

### 7.4 `user_preferences`

Una fila por usuario.

```sql
CREATE TABLE public.user_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    custom_meeting_templates JSONB NOT NULL DEFAULT '[]',
    hidden_built_in_template_ids JSONB NOT NULL DEFAULT '[]',
    custom_words JSONB NOT NULL DEFAULT '[]',
    default_meeting_template_id TEXT NOT NULL DEFAULT 'auto',
    auto_template_target_id TEXT NOT NULL DEFAULT '',
    meeting_title_prompt TEXT NOT NULL DEFAULT '',
    folder_order_remote_ids JSONB NOT NULL DEFAULT '[]',
    client_updated_at TIMESTAMPTZ NOT NULL,
    server_updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    remote_version BIGINT NOT NULL DEFAULT 1,
    last_writer_device_id TEXT NOT NULL
);
```

### 7.5 Trigger remoto de versionado

Crear una funcion Postgres que en cada `UPDATE`:

- incremente `remote_version`
- actualice `server_updated_at = now()`

Aplicar a:

- `meeting_folders`
- `meetings`
- `dictations`
- `user_preferences`

### 7.6 Indices remotos

Agregar como minimo:

- `(user_id, deleted_at, server_updated_at, id)` para cada tabla sincronizada
- `(user_id, calendar_event_id)` en `meetings` cuando no sea null

## 8. Seguridad en Supabase

### 8.1 RLS

RLS obligatorio en todas las tablas.

Politica base:

```sql
ALTER TABLE public.meeting_folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dictations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY meeting_folders_own ON public.meeting_folders
FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY meetings_own ON public.meetings
FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY dictations_own ON public.dictations
FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY user_preferences_own ON public.user_preferences
FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
```

### 8.2 Auth del cliente

No usar magic link en MVP porque complica callback + parsing + flujo sin SDK.

Usar:

- email + password
- REST directo contra Supabase Auth
- refresh token guardado en Keychain
- access token en memoria y/o Keychain segun implementacion elegida

UI minima:

- email
- password
- create account
- sign in
- sign out

### 8.3 Secretos

En el bundle del app solo vive:

- `supabaseURL`
- `supabaseAnonKey`

Nunca usar `service_role` en el cliente.

### 8.4 Privacidad

Este diseño NO es end-to-end encryption.

Los transcripts, notas, dictados, templates y custom words viven legibles en Supabase para el usuario autenticado.

Si se requiere E2E, eso es otra iniciativa separada.

## 9. Reconciliacion de IDs y primer sync

Este punto es obligatorio. No subir todo a ciegas en el primer login.

### 9.1 Regla general

La primera vez que una entidad local no tiene `remote_id`, antes de crear un row remoto se intenta reconciliar con un row remoto existente del mismo usuario.

Si hay match, se guarda el mapping y no se duplica.

### 9.2 Match de dictations

Fingerprint:

- `timestamp`
- `duration_seconds` redondeado a 3 decimales
- `raw_text`
- `app_context`

Hash sugerido:

`sha256(timestamp + "|" + duration + "|" + raw_text + "|" + app_context)`

### 9.3 Match de meetings

Prioridad de match:

1. Si `calendar_event_id` existe en ambos lados:
   `calendar_event_id + start_time`
2. Si no:
   `start_time + rounded(duration_seconds, 3) + sha256(raw_transcript)`

No usar `title` como clave primaria de reconciliacion.

### 9.4 Match de folders

Match por path logico unico:

- construir path desde raiz con `parent_folder_id`
- ejemplo: `/Customers/Acme/Weekly`

Si el path existe una sola vez en remoto, mapear.
Si hay ambiguedad, no mapear: subir como nueva carpeta.

### 9.5 Primer sync por tabla

Para cada tabla:

- si remoto esta vacio y local tiene datos: upload local
- si local esta vacio y remoto tiene datos: download remoto
- si ambos tienen datos y no hay mappings: correr reconciliacion antes de crear nuevas filas

## 10. Payloads canonicos y hashing

Definir una serializacion canonica JSON con llaves ordenadas y sin campos locales o de servidor.

### 10.1 Meeting hash

Incluye:

- title
- calendar_event_id
- calendar_event_snapshot
- start_time
- end_time
- duration_seconds
- raw_transcript
- formatted_notes
- meeting_status
- manual_notes
- word_count
- selected_template_id
- selected_template_name
- selected_template_kind
- selected_template_prompt
- folder_remote_id

No incluye:

- local id
- remote_version
- server_updated_at
- audio paths

### 10.2 Dictation hash

Incluye solo campos sincronizados de dictation.

### 10.3 Folder hash

Incluye:

- name
- parent_folder_remote_id
- color_hex
- icon_name
- sort_order

### 10.4 Preferences hash

Incluye:

- custom_meeting_templates
- hidden_built_in_template_ids
- custom_words
- default_meeting_template_id
- auto_template_target_id
- meeting_title_prompt
- folder_order_remote_ids

## 11. Politica exacta de conflictos

### 11.1 Regla base

Conflicto existe cuando:

- la entidad local esta `dirty`, y
- el `remote_version` actual en Supabase es distinto del `remote_version` que conoce `sync_metadata`

### 11.2 Resolucion

1. Cargar payload remoto actual.
2. Calcular hash remoto y hash local canonicos.
3. Si hashes iguales:
   marcar limpio y actualizar metadata local sin sobrescribir datos.
4. Si hashes distintos:
   comparar `client_updated_at`.
5. Si local `client_updated_at` > remoto `client_updated_at`:
   el local sobreescribe remoto.
6. Si local `client_updated_at` < remoto `client_updated_at`:
   el remoto sobreescribe local.
7. Si timestamps iguales:
   gana el `device_id` lexicograficamente mayor.

### 11.3 Politica por tipo

- `dictations`: `LWW` de entidad completa
- `meetings`: `LWW` de entidad completa
- `meeting_folders`: `LWW` de entidad completa
- `user_preferences`: `LWW` de entidad completa

No hacer merge campo por campo en MVP.

### 11.4 Riesgo conocido

Si el mismo usuario edita exactamente la misma entidad en dos Macs casi al mismo tiempo, una de las dos versiones puede perderse.

Eso se acepta en MVP.

## 12. Politica de borrado

### 12.1 Remoto

Los deletes remotos son soft delete:

- `deleted_at` se rellena
- `remote_version` sube
- `server_updated_at` se actualiza

### 12.2 Local

Los deletes locales siguen siendo fisicos, como ya funciona hoy.

Para no perder el evento de borrado:

- el trigger local crea un tombstone en `sync_tombstones`
- luego el row de dominio puede desaparecer

### 12.3 Upload de tombstones

Para una entidad con `remote_id` conocido:

- hacer `PATCH` remoto condicionado por `remote_version`
- setear `deleted_at`
- actualizar `client_updated_at`
- actualizar `last_writer_device_id`

Si el row nunca existio en remoto, borrar el tombstone local sin hacer llamada remota.

### 12.4 Aplicacion local de deletes remotos

Cuando se baja una entidad con `deleted_at != null`:

- si existe localmente, borrarla;
- borrar su `sync_metadata`;
- borrar tombstone local si existiera;
- en meetings, si `saved_recording_path` local existe, hacer best-effort delete del archivo antes de borrar la fila, replicando la semantica de delete existente.

### 12.5 Retencion de tombstones

- remoto: mantener `deleted_at` al menos 30 dias
- local: purgar tombstones limpios con mas de 30 dias

## 13. Orden exacto de un ciclo de sync

Cada ciclo debe correr en un `actor` unico para evitar reentradas.

### 13.1 Upload

Orden:

1. `meeting_folders` upserts
2. `dictations` upserts
3. `meetings` upserts
4. `user_preferences` upsert
5. `meetings` tombstones
6. `dictations` tombstones
7. `meeting_folders` tombstones

Razon:

- meetings dependen de folders;
- preferencias dependen del mapping remoto de folders para `folderOrder`;
- los tombstones de folders deben ir al final porque localmente borrar una carpeta tambien mueve meetings y reparenta hijos.

### 13.2 Download

Orden:

1. `meeting_folders`
2. `user_preferences`
3. `dictations`
4. `meetings`

Razon:

- meetings dependen de folders;
- `folderOrder` depende del mapping de folders;
- dictations son independientes.

## 14. Cursores de descarga

Cada tabla remota se descarga en paginas ordenadas por:

- `server_updated_at ASC`
- `id ASC`

Cursor local:

```json
{"server_updated_at":"2026-05-04T10:20:30.123Z","id":"<uuid>"}
```

Filtro siguiente pagina:

- `server_updated_at > cursor.server_updated_at`
- o `server_updated_at = cursor.server_updated_at AND id > cursor.id`

No usar solo timestamp.

## 15. Criterios de inclusion para upload

### 15.1 Meetings

Subir solo si:

- hay `sync_metadata.dirty = 1`
- el meeting NO esta en `recording`
- el meeting NO esta en `processing`

### 15.2 Dictations

Subir si `dirty=1`.

### 15.3 Folders

Subir si `dirty=1`.

### 15.4 Preferences

Subir si `sync_state.preferences_dirty = true`.

## 16. Preferences sync: snapshot exacto

Crear un snapshot especifico para sync con este shape:

```json
{
  "customMeetingTemplates": [],
  "hiddenBuiltInTemplateIDs": [],
  "customWords": [],
  "defaultMeetingTemplateID": "auto",
  "autoTemplateTargetID": "",
  "meetingTitlePrompt": "",
  "folderOrderRemoteIDs": []
}
```

### 16.1 Conversion de `folderOrder`

Localmente `folderOrder` usa `Int64`.

Para subir:

- resolver cada `Int64` a `remote_id` usando `sync_metadata`
- ignorar temporalmente las carpetas que aun no tengan `remote_id`

Para bajar:

- convertir `folderOrderRemoteIDs` a ids locales con `sync_metadata`
- guardar solo los que tengan mapping local

### 16.2 Integracion con `updateConfig`

En `MuesliController.updateConfig(_:)`:

1. tomar snapshot sync-relevante del config viejo
2. mutar config
3. persistir config
4. tomar snapshot sync-relevante del config nuevo
5. si cambio el snapshot sync-relevante:
   - marcar `preferences_dirty = true`
   - actualizar `preferences_client_updated_at`
   - pedir `scheduleSync`

No disparar sync por cambios de config no sincronizados.

## 17. Auth y sesiones

### 17.1 Almacenamiento local

Guardar en Keychain:

- refresh token
- access token opcionalmente
- user id
- expiry

Guardar fuera de Keychain solo estado no sensible si hace falta:

- ultimo email usado

### 17.2 Cliente REST

Implementar cliente REST sin SDK, usando:

- `URLSession`
- `POST /auth/v1/signup`
- `POST /auth/v1/token?grant_type=password`
- `POST /auth/v1/token?grant_type=refresh_token`
- `GET/PATCH/POST` contra PostgREST

### 17.3 Refresco de token

Antes de cada ciclo:

- validar expiry
- refrescar si faltan menos de 30 segundos

Si el refresh falla con 401:

- limpiar sesion local
- pausar sync
- mostrar estado de autenticacion caida en Settings

## 18. Integracion exacta en el codigo

## 18.1 Archivos nuevos

### En `native/MuesliNative/Sources/MuesliCore/Sync/`

- `LocalSyncRepository.swift`
- `LocalSyncModels.swift`
- `SyncPayloadHasher.swift`

Responsabilidades:

- crear tablas auxiliares
- crear triggers
- leer candidatos `dirty`
- leer y escribir `sync_state`
- aplicar rows remotos a SQLite
- mantener mappings local/remote

### En `native/MuesliNative/Sources/MuesliNativeApp/Sync/`

- `SupabaseAuthManager.swift`
- `SupabaseRESTClient.swift`
- `SupabaseSyncManager.swift`
- `SyncSettingsView.swift`
- `SyncViewModels.swift`

Responsabilidades:

- auth
- refresh token
- subida y descarga
- debounce de sync
- UI de sync

## 18.2 Archivos existentes a tocar

### `AppDelegate.swift`

- crear `SupabaseSyncManager`
- inyectarle `dictationStore.databasePath()`
- inyectarle closures para leer/escribir config sync-relevante si hace falta
- llamar `start()` del manager despues de `controller.start()`
- llamar `shutdown()` en terminate

### `MuesliController.swift`

- agregar propiedad opcional o inyectada de `SupabaseSyncManager`
- al final de `syncAppState()`, llamar `syncManager?.notifyPotentialLocalDataChange()`
  - este metodo debe hacer debounce interno y no debe lanzar un sync inmediato cada vez
- en `updateConfig(_:)`, comparar snapshot viejo/nuevo sync-relevante y llamar `syncManager?.notifyPreferencesChanged()`

No tocar todos los metodos write uno por uno.
La centralizacion debe ser:

- `syncAppState()` para cambios de datos
- `updateConfig(_:)` para preferencias

### `AppState.swift`

Agregar:

- `case sync` a `SettingsPane`
- estado visible de sync:
  - `isSupabaseAuthenticated`
  - `lastSyncAt`
  - `syncStatusText`
  - `syncErrorText`
  - `syncedMeetingCount`
  - `syncedDictationCount`
  - `syncedFolderCount`

### `SettingsView.swift`

- agregar el tab/pane `Sync`
- renderizar `SyncSettingsView`

### `L10n.swift`

Agregar strings del pane Sync.

## 19. API local del `LocalSyncRepository`

Definir explicitamente estas operaciones:

- `migrateIfNeeded()`
- `ensureDeviceID() -> String`
- `markPreferencesDirty(snapshot: SyncPreferencesSnapshot)`
- `dirtyFolders(limit:)`
- `dirtyDictations(limit:)`
- `dirtyMeetings(limit:)`
- `dirtyTombstones(entityType:, limit:)`
- `currentPreferencesSnapshot()`
- `markFolderSynced(localID:, remoteID:, remoteVersion:, clientUpdatedAt:, serverUpdatedAt:, payloadHash:, lastWriterDeviceID:)`
- `markDictationSynced(...)`
- `markMeetingSynced(...)`
- `markPreferencesSynced(remoteVersion:, clientUpdatedAt:, serverUpdatedAt:, payloadHash:, lastWriterDeviceID:)`
- `applyRemoteFolder(_:)`
- `applyRemoteDictation(_:)`
- `applyRemoteMeeting(_:)`
- `applyRemotePreferences(_:)`
- `purgeCleanTombstones(olderThanDays:)`
- `loadCursor(for:)`
- `saveCursor(for:, value:)`

## 20. API de `SupabaseSyncManager`

Definir explicitamente:

- `start()`
- `shutdown()`
- `syncNow(reason:) async`
- `notifyPotentialLocalDataChange()`
- `notifyPreferencesChanged()`
- `signIn(email:password:) async`
- `signUp(email:password:) async`
- `signOut()`

El manager debe:

- ser `actor`
- colapsar triggers repetidos en un solo sync
- ignorar `notifyPotentialLocalDataChange()` si no hay sesion

## 21. Estrategia de scheduling

### Obligatorio

- al lanzar la app
- al autenticarse
- boton manual `Sync now`
- debounce despues de `notifyPotentialLocalDataChange()`
- debounce despues de `notifyPreferencesChanged()`
- cada 5 minutos mientras la app este activa y autenticada
- al terminar la app, best-effort sync corto

### Debounce

- datos: 2 segundos
- preferencias: 1 segundo

## 22. Reglas de aplicacion remota por entidad

### 22.1 Folder remoto

1. resolver `parent_folder_id` remoto a local si existe
2. buscar mapping por `remote_id`
3. si existe y `deleted_at` es null:
   actualizar folder local
4. si no existe y `deleted_at` es null:
   insertar folder local
5. si `deleted_at` no es null:
   aplicar delete local si existe
6. al final, escribir metadata limpia

### 22.2 Dictation remota

1. buscar mapping por `remote_id`
2. si existe y no esta borrada:
   reemplazar payload local
3. si no existe y no esta borrada:
   insertar local
4. si viene borrada:
   borrar local si existe
5. escribir metadata limpia

### 22.3 Meeting remota

1. resolver `folder_id` remoto a local si existe
2. buscar mapping por `remote_id`
3. si existe y no esta borrada:
   reemplazar meeting local completo salvo audio paths
4. si no existe y no esta borrada:
   insertar local
5. si viene borrada:
   borrar local y hacer best-effort cleanup de saved recording
6. escribir metadata limpia

### 22.4 Preferences remotas

1. convertir JSON remoto a snapshot local
2. mapear `folderOrderRemoteIDs` a `folderOrder` local
3. actualizar solo los campos sincronizados dentro de `AppConfig`
4. persistir con `ConfigStore.save`
5. no tocar campos no sincronizados
6. marcar `preferences_dirty = false`

## 23. Campos locales que nunca debe tocar la aplicacion remota

Aunque se reescriba un meeting remoto, preservar localmente:

- `mic_audio_path`
- `system_audio_path`
- `saved_recording_path`

Si el row local existe y llega update remoto:

- copiar esos tres campos viejos al row actualizado

Si el row remoto llega por primera vez:

- esos tres campos deben quedar `NULL`

## 24. Fases de implementacion recomendadas

### Fase 1

- `LocalSyncRepository`
- tablas auxiliares
- triggers
- tests unitarios de metadata y tombstones

### Fase 2

- `SupabaseAuthManager`
- `SupabaseRESTClient`
- login/signup/signout/refresh

### Fase 3

- upload de `meeting_folders`, `dictations`, `meetings`, `user_preferences`
- tombstones
- tests de conflicto y delete

### Fase 4

- download y apply remoto
- reconciliacion inicial
- cursores

### Fase 5

- UI de Settings
- estado visible
- contadores y errores

## 25. Tests obligatorios

### Local sync metadata

- insert local crea `sync_metadata`
- update local marca `dirty`
- delete local crea tombstone
- remote apply deja `dirty=0`

### Reconciliacion

- primer sync de meeting por `calendar_event_id`
- primer sync de meeting por transcript hash
- primer sync de folder por path
- primer sync de dictation por fingerprint

### Conflictos

- local mas nuevo gana
- remoto mas nuevo gana
- hash igual no produce write innecesario
- empate exacto usa `device_id`

### Deletes

- delete local sube `deleted_at`
- delete remoto borra local
- delete de folder respeta move/null local existente

### Reglas funcionales

- meetings `recording` y `processing` no se suben
- audio paths nunca viajan al remoto
- `folderOrder` convierte ids locales a remotos y viceversa
- preferences remotas no pisan API keys ni settings locales

## 26. Criterios de aceptacion

Se considera terminada esta iniciativa cuando:

1. Un usuario crea cuenta o inicia sesion en dos Macs.
2. Un meeting completado en Mac A aparece en Mac B.
3. Una dictation creada en Mac B aparece en Mac A.
4. Una carpeta creada o renombrada se replica.
5. Un template custom creado o editado se replica.
6. `customWords` se replican.
7. Borrar un meeting en una Mac lo borra en la otra.
8. Ningun secreto local ni audio path aparece en Supabase.
9. Meetings vivos no se sincronizan hasta estado terminal.
10. El app sigue funcionando si Supabase esta caido; la base local sigue siendo usable.

## 27. Conclusiones

La idea original de usar Supabase como capa intermedia es correcta.

Lo que habia que corregir era:

- no tocar el schema funcional de negocio para meter sync;
- no basar el algoritmo en `updated_at` de las tablas principales;
- definir tombstones;
- definir reconciliacion inicial;
- incluir el schema real actual del repo;
- definir exactamente que campos de config si y no se sincronizan;
- centralizar los puntos de integracion para no entrar en conflicto con upstream.

Si Claude Code sigue este documento, deberia poder implementar un MVP solido y bastante desacoplado del trabajo activo del autor.

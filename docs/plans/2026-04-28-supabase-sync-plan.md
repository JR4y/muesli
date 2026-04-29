# Viabilidad y diseño: sincronización Supabase para Muesli

## Contexto

El usuario quiere evaluar la viabilidad de usar Supabase como capa de sincronización para el app macOS Muesli (local-first, SQLite). El objetivo es backup + acceso desde múltiples Macs del mismo usuario. Es un **fork** — el sync debe ser un módulo desacoplado que toque el mínimo de código existente.

---

## Datos actuales (SQLite local, 3 tablas)

| Tabla | Campos relevantes para sync | Tamaño típico |
|---|---|---|
| `dictations` | id, timestamp, duration_seconds, raw_text, app_context, word_count, source, started_at, ended_at | ~1KB/registro |
| `meetings` | id, title, start/end_time, raw_transcript, formatted_notes, manual_notes, word_count, status, calendar_event_snapshot (JSON), selected_template_*, folder_id | ~20–150KB/registro |
| `meeting_folders` | id, name, color_hex, sort_order | <1KB |

**Config.json (parcial):** custom_templates, custom_words, hidden_builtin_template_ids, folder_order, default_meeting_template_id, meeting_title_prompt

**NO se sincroniza:** openAIAPIKey, openRouterAPIKey, hotkey config, rutas de audio, window frames, sttBackend/Model, darkMode, launchAtLogin, onboarding state.

---

## Veredicto: **Viable**

- A 20KB promedio/meeting, 500 reuniones = ~10MB. Free tier de Supabase (500MB) aguanta ~16.000 reuniones.
- El esquema SQLite mapea casi 1:1 a Postgres.
- El mayor trabajo no es técnico sino de arquitectura: mantener el módulo de sync completamente desacoplado.

---

## Principio de diseño: máximo desacoplamiento del fork

### Puntos de acoplamiento PERMITIDOS (mínimo indispensable)

| Cambio | Dónde | Magnitud |
|---|---|---|
| Añadir columnas de sync al SQLite | `DictationStore.swift` — migración de schema | ~20 líneas SQL |
| Arrancar el sync manager | `AppDelegate` o `MuesliController.init` | 1–2 líneas |
| Añadir tab "Sync" en Settings | `SettingsView.swift` — añadir case al enum + content view | ~15 líneas |

### Mecanismo de detección de cambios: SQLite triggers

En vez de hookearse en `insertMeeting`, `insertDictation`, etc., se usan triggers de SQLite que actualizan `updated_at` automáticamente. El sync manager simplemente consulta:

```sql
SELECT * FROM meetings WHERE updated_at > :last_synced OR sync_id IS NULL
```

**Esto no requiere ningún cambio en el código de escritura existente.**

---

## Esquema Supabase (4 tablas)

```sql
-- Row Level Security: cada usuario solo ve sus datos
-- Política aplicada a todas las tablas:
-- CREATE POLICY "own" ON <tabla> FOR ALL USING (auth.uid() = user_id);

CREATE TABLE meeting_folders (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    color_hex   TEXT,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ   -- soft delete para sync
);

CREATE TABLE meetings (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id                TEXT,              -- qué Mac lo creó (diagnóstico)
    title                    TEXT NOT NULL,
    start_time               TIMESTAMPTZ NOT NULL,
    end_time                 TIMESTAMPTZ,
    duration_seconds         DOUBLE PRECISION,
    raw_transcript           TEXT,              -- hasta ~100KB
    formatted_notes          TEXT,              -- hasta ~50KB
    manual_notes             TEXT NOT NULL DEFAULT '',
    word_count               INTEGER NOT NULL DEFAULT 0,
    meeting_status           TEXT NOT NULL DEFAULT 'completed',
    calendar_event_id        TEXT,
    calendar_event_snapshot  JSONB,
    selected_template_id     TEXT,
    selected_template_name   TEXT,
    selected_template_kind   TEXT,
    selected_template_prompt TEXT,
    folder_id                UUID REFERENCES meeting_folders(id) ON DELETE SET NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at               TIMESTAMPTZ
    -- SIN mic_audio_path / system_audio_path / saved_recording_path
);

CREATE TABLE dictations (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id        TEXT,
    timestamp        TIMESTAMPTZ NOT NULL,
    duration_seconds DOUBLE PRECISION,
    raw_text         TEXT,
    app_context      TEXT,
    word_count       INTEGER NOT NULL DEFAULT 0,
    source           TEXT NOT NULL DEFAULT 'dictation',
    started_at       TIMESTAMPTZ,
    ended_at         TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);

-- Una fila por usuario, JSONB para flexibilidad de schema sin migraciones
CREATE TABLE user_preferences (
    user_id                      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    custom_templates             JSONB NOT NULL DEFAULT '[]',
    custom_words                 JSONB NOT NULL DEFAULT '[]',
    hidden_builtin_template_ids  JSONB NOT NULL DEFAULT '[]',
    folder_order                 JSONB NOT NULL DEFAULT '[]',   -- array de UUIDs locales
    default_meeting_template_id  TEXT,
    auto_template_target_id      TEXT,
    meeting_title_prompt         TEXT,
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

---

## Cambios al SQLite local (migración en DictationStore.swift)

```sql
-- En el bloque de migración existente (schemaVersion++)
-- Estas columnas son nullable para no romper registros existentes

ALTER TABLE dictations      ADD COLUMN sync_id    TEXT;   -- UUID asignado en primer sync
ALTER TABLE dictations      ADD COLUMN updated_at TEXT DEFAULT (datetime('now'));
ALTER TABLE dictations      ADD COLUMN deleted_at TEXT;

ALTER TABLE meetings        ADD COLUMN sync_id    TEXT;
ALTER TABLE meetings        ADD COLUMN updated_at TEXT DEFAULT (datetime('now'));
ALTER TABLE meetings        ADD COLUMN deleted_at TEXT;

ALTER TABLE meeting_folders ADD COLUMN sync_id    TEXT;
ALTER TABLE meeting_folders ADD COLUMN updated_at TEXT DEFAULT (datetime('now'));
ALTER TABLE meeting_folders ADD COLUMN deleted_at TEXT;

-- Índices para sync incremental eficiente
CREATE INDEX IF NOT EXISTS idx_dictations_sync  ON dictations(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_meetings_sync    ON meetings(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_folders_sync     ON meeting_folders(updated_at DESC);

-- Triggers: actualizan updated_at sin tocar el código de aplicación
CREATE TRIGGER IF NOT EXISTS meetings_set_updated_at
    AFTER UPDATE ON meetings
    BEGIN UPDATE meetings SET updated_at = datetime('now') WHERE id = NEW.id; END;

CREATE TRIGGER IF NOT EXISTS dictations_set_updated_at
    AFTER UPDATE ON dictations
    BEGIN UPDATE dictations SET updated_at = datetime('now') WHERE id = NEW.id; END;

CREATE TRIGGER IF NOT EXISTS folders_set_updated_at
    AFTER UPDATE ON meeting_folders
    BEGIN UPDATE meeting_folders SET updated_at = datetime('now') WHERE id = NEW.id; END;
```

---

## Estructura de archivos del módulo Sync (todo nuevo)

```
native/MuesliNative/Sources/MuesliNativeApp/Sync/
├── SupabaseClient.swift          — HTTP layer (URLSession + PostgREST API)
├── SupabaseAuthManager.swift     — email auth + Keychain token storage
├── SupabaseSyncManager.swift     — actor principal de sync
├── SyncState.swift               — tipos: SyncStatus, SyncError, DeviceID
└── Settings/
    └── SyncSettingsView.swift    — pantalla de integración en Settings
```

**Sin dependencias externas** — se usa URLSession directo contra la API REST de Supabase (PostgREST + GoTrue). Esto mantiene el bundle limpio y evita añadir SPM packages al fork.

---

## Estrategia de sync: last-write-wins con updated_at

- Cada Mac tiene un `device_id` (UUID generado en primer uso, guardado en Keychain)
- **Upload:** `SELECT * WHERE sync_id IS NULL OR updated_at > last_upload_timestamp` → upsert en Supabase
- **Download:** `GET /meetings?updated_at=gt.{last_download_timestamp}` → upsert local por `sync_id`
- **Conflicto:** gana el registro con `updated_at` más reciente
- **Borrado:** soft-delete (`deleted_at = now()`) → se propaga al otro Mac, que borra el registro local

### Triggers de sync (sin polling agresivo)
1. Al lanzar la app — sync completo si >12h, incremental si reciente
2. Al completar una reunión o dictación — upload inmediato del registro
3. Timer de 5 minutos (solo si app activa y usuario autenticado)
4. Botón manual "Sincronizar ahora" en la pantalla de Settings

Para (2): **la única adición al código existente** es en los 2-3 sitios de `MuesliController` donde se completa una reunión/dictación, llamar `SyncManager.shared.triggerUpload()` — un método no-blocking que no bloquea el flujo existente.

---

## Pantalla de integración en Settings

**Cambio en SettingsView.swift:** añadir `.sync` al enum `SettingsPane` y el case en el content switch (~15 líneas). Todo el contenido vive en `SyncSettingsView.swift`.

```
┌─────────────────────────────────────────┐
│  ⚙ General  ◉ Dictation  Meetings  Sync │
├─────────────────────────────────────────┤
│                                         │
│  Muesli Sync                            │
│  ─────────────────────────────────────  │
│  [Inicia sesión con tu correo]          │
│                                         │
│  ○ No conectado                         │
│                                         │
│  ─────────────────────────────────────  │
│  (después de login)                     │
│  ✓ Conectado como user@email.com        │
│  Último sync: hace 3 minutos            │
│  Reuniones sincronizadas: 47            │
│  Dictaciones sincronizadas: 312         │
│                                         │
│  [Sincronizar ahora]  [Cerrar sesión]   │
└─────────────────────────────────────────┘
```

---

## Resumen de contactos con código existente

| Archivo existente | Qué se toca | Líneas ~|
|---|---|---|
| `DictationStore.swift` | Añadir SQL de migración (schema + triggers) | +40 líneas SQL |
| `SettingsView.swift` | Añadir `.sync` al enum + case en switch | +15 líneas |
| `MuesliController.swift` | Llamar `SyncManager.shared.triggerUpload()` en 2-3 puntos | +3 líneas |
| `AppDelegate.swift` o similar | `SyncManager.shared.setup(dbPath:)` en init | +2 líneas |

**Total de contacto con código del fork: ~60 líneas.** El resto (auth, sync logic, UI) vive en archivos nuevos.

---

## Estimación de tamaño en Supabase

| Datos | Promedio | 500 registros |
|---|---|---|
| raw_transcript | ~20KB | ~10MB |
| formatted_notes | ~8KB | ~4MB |
| dictations raw_text | ~1KB | ~0.5MB |
| metadata | ~2KB | ~1MB |
| **Total** | | **~15.5MB / 500 reuniones** |

Free tier (500MB) → ~16.000 reuniones. Más que suficiente para uso personal.

---

## Verificación

- Login con cuenta nueva → `user_preferences` creada en Supabase
- Crear reunión en Mac A → tras trigger, aparece en Mac B en próximo sync
- Editar notas en Mac B → `updated_at` se actualiza via trigger → gana en próximo sync
- Borrar carpeta en Mac A → `deleted_at` propagado → desaparece en Mac B
- Verificar en Supabase Dashboard que ninguna tabla contiene `openAIAPIKey` ni rutas de audio
- Verificar que sin sesión activa el app funciona igual que antes (cero degradación)

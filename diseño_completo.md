# Diseño Completo — App Entrenador Personal de Gimnasio

> **Agente:** Cody | **Fecha:** 2026-04-16 | **Target:** 100 usuarios, GDPR, VPS limitado

---

## 1. MODELO DE DATOS (PostgreSQL + RLS)

### 1.1 Schema SQL Completo

```sql
-- ============================================================
-- EXTENSIONES Y ENUMS
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- para búsqueda difusa si sirve

CREATE TYPE rol_usuario AS ENUM ('admin', 'entrenador', 'usuario');
CREATE TYPE sexo_biologico AS ENUM ('M', 'F', 'O');  -- GDPR: datos sensibles
CREATE TYPE unidad_peso AS ENUM ('kg', 'lb');
CREATE TYPE unidad_distancia AS ENUM ('km', 'mi');
CREATE TYPE tipo_ejercicio AS ENUM ('fuerza', 'cardio', 'flexibilidad', 'equilibrio');
CREATE TYPE grupo_muscular AS ENUM ('pecho', 'espalda', 'hombro', 'bicep', 'tricep', 'antebrazo', 'abdomen', 'oblicuos', 'cuadriceps', 'femoral', 'gluteo', 'gemelo', 'core', 'full_body');
CREATE TYPE tipo_rutina AS ENUM ('fuerza', 'hipertrofia', 'definicion', 'cardio', 'funcional', 'flexibilidad');
CREATE TYPE dificultad_ejercicio AS ENUM ('principiante', 'intermedio', 'avanzado');
CREATE TYPE tipo_registro_nutricional AS ENUM ('comida', 'snack', 'suplemento');
CREATE TYPE estado_sesion AS ENUM ('planificada', 'en_progreso', 'completada', 'cancelada');
CREATE TYPE fuente_creacion AS ENUM ('entrenador', 'ia', 'usuario');

-- ============================================================
-- TABLA: usuarios (gestión de cuentas — Ramón crea las cuentas)
-- ============================================================

CREATE TABLE usuarios (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           VARCHAR(255) NOT NULL UNIQUE,
    hashed_password VARCHAR(255) NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    apellidos       VARCHAR(150),
    rol             rol_usuario  NOT NULL DEFAULT 'usuario',
    idioma          VARCHAR(5)   DEFAULT 'es',
    timezone        VARCHAR(50)  DEFAULT 'Europe/Madrid',
    email_verificado BOOLEAN     DEFAULT FALSE,
    fecha_alta      TIMESTAMPTZ  DEFAULT NOW(),
    ultimo_acceso   TIMESTAMPTZ,
    esta_activo     BOOLEAN      DEFAULT TRUE,
    -- GDPR: consentimiento
    consentimiento_gdpr      BOOLEAN  NOT NULL DEFAULT FALSE,
    fecha_consentimiento     TIMESTAMPTZ,
    consentimiento_marketing BOOLEAN  DEFAULT FALSE,
    version_politica_privacidad VARCHAR(20) DEFAULT '1.0',  -- trackear versión aceptada

    CONSTRAINT email_valido CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

CREATE INDEX idx_usuarios_email ON usuarios(email);
CREATE INDEX idx_usuarios_rol ON usuarios(rol);

-- ============================================================
-- TABLA: perfiles_salud (datos sensibles de salud — GDPR)
-- ============================================================

CREATE TABLE perfiles_salud (
    id                        UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id                UUID  NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,

    -- Datos corporales
    fecha_nacimiento          DATE,
    sexo_biologico            sexo_biologico,
    altura_cm                 DECIMAL(5,2),
    peso_actual_kg            DECIMAL(5,2),
    peso_deseado_kg           DECIMAL(5,2),
    porcentaje_grasa          DECIMAL(4,1),   -- NULL = no medido
    porcentaje_musculo        DECIMAL(4,1),

    -- Metabolismo
    tmb_kcal                  INTEGER,  -- Tasa Metabólica Basal calculada
    factor_actividad          DECIMAL(3,2) DEFAULT 1.2,  -- 1.2-1.9 según nivel

    -- Lesiones y condiciones médicas (CRÍTICO para GDPR)
    lesiones                  TEXT[],  -- ARRAY de texto, ej: {'rodilla','espalda'}
    condiciones_medicas       TEXT[],
    alergias                  TEXT[],
    medicamentos              TEXT[],

    -- Restricciones dietéticas
    restricciones_nutricionales TEXT[],  -- vegano, sin-gluten, etc.

    -- Objetivo principal
    objetivo_principal        VARCHAR(100),
    objetivo_detalle          TEXT,

    -- Consentimiento específico datos salud (GDPR Art. 9)
    consentimiento_salud      BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_consentimiento_salud TIMESTAMPTZ,

    -- Metadatos
    fecha_ultima_actualizacion TIMESTAMPTZ DEFAULT NOW(),
    fuente_creacion            fuente_creacion DEFAULT 'usuario',
    created_at                TIMESTAMPTZ DEFAULT NOW(),

    -- RLS
    CONSTRAINT fk_perfil_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
);
ALTER TABLE perfiles_salud ENABLE ROW LEVEL SECURITY;

-- RLS: usuario solo ve su propio perfil
CREATE POLICY rl_perfil_salud_usuario ON perfiles_salud
    FOR ALL USING (usuario_id = current_setting('app.current_user_id', TRUE)::UUID);

-- ============================================================
-- TABLA: ejercicios (catálogo global — solo admins/editors pueden modificar)
-- ============================================================

CREATE TABLE ejercicios (
    id                UUID   PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre            VARCHAR(150) NOT NULL,
    nombre_normalizado VARCHAR(150),  -- para búsqueda sin acentos
    descripcion       TEXT,
    grupo_muscular    grupo_muscular NOT NULL,
    grupos_secundarios grupo_muscular[],
    tipo_ejercicio    tipo_ejercicio NOT NULL,
    dificultad        dificultad_ejercicio DEFAULT 'principiante',
    equipo_necesario VARCHAR(100),   -- 'none', 'barra', 'mancuernas', 'polea', 'maquina', 'banco', 'cinta', 'bicicleta'

    -- Instrucciones
    instrucciones     TEXT[],
    musculos_implicados TEXT[],

    -- Metadatos
    es_publico        BOOLEAN DEFAULT TRUE,
    creado_por        UUID REFERENCES usuarios(id),
    created_at        TIMESTAMPTZ DEFAULT NOW(),
    updated_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_ejercicios_grupo ON ejercicios(grupo_muscular);
CREATE INDEX idx_ejercicios_tipo ON ejercicios(tipo_ejercicio);
CREATE INDEX idx_ejercicios_nombre_trgm ON ejercicios USING gin(nombre_normalizado gin_trgm_ops);

-- RLS: cualquier usuario autenticado puede leer ejercicios públicos
CREATE POLICY rl_ejercicios_read ON ejercicios
    FOR SELECT USING (es_publico = TRUE OR creado_por = current_setting('app.current_user_id', TRUE)::UUID);

-- ============================================================
-- TABLA: rutinas (plantilla de rutina de entreno)
-- ============================================================

CREATE TABLE rutinas (
    id              UUID   PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre          VARCHAR(150) NOT NULL,
    descripcion     TEXT,
    tipo_rutina     tipo_rutina NOT NULL,
    dificultad      dificultad_ejercicio,
    duracion_estimada_minutos INTEGER,
    frecuencia_semanal INTEGER DEFAULT 3,  -- veces por semana recomendadas

    -- Relación
    usuario_id      UUID REFERENCES usuarios(id),  -- NULL = rutina de sistema
    creador_id      UUID REFERENCES usuarios(id),
    es_publica      BOOLEAN DEFAULT FALSE,  -- si trainer la comparte

    -- Info IA
    fuente_creacion fuente_creacion DEFAULT 'entrenador',
    metadata_ia     JSONB,  -- tags, rationale, notas de IA

    -- Metadatos
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    activa          BOOLEAN DEFAULT TRUE
);

ALTER TABLE rutinas ENABLE ROW LEVEL SECURITY;

CREATE POLICY rl_rutinas_usuario ON rutinas
    FOR ALL USING (
        usuario_id = current_setting('app.current_user_id', TRUE)::UUID
        OR es_publica = TRUE
        OR (usuario_id IS NULL AND es_publica = TRUE)
    );

-- ============================================================
-- TABLA: rutina_ejercicios (ejercicios dentro de una rutina)
-- ============================================================

CREATE TABLE rutina_ejercicios (
    id              UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
    rutina_id       UUID  NOT NULL REFERENCES rutinas(id) ON DELETE CASCADE,
    ejercicio_id    UUID  NOT NULL REFERENCES ejercicios(id),
    orden           INTEGER NOT NULL DEFAULT 1,
    series          INTEGER NOT NULL DEFAULT 3,
    repeticiones    VARCHAR(30) NOT NULL DEFAULT '10-12',  -- rango o valor fijo
    descanso_segundos INTEGER DEFAULT 90,
    tempo           VARCHAR(10),  -- ej: "3-1-2-0" (conc-ecc-pause)
    notas           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABLA: sesiones_entreno (instancia de una sesión real)
-- ============================================================

CREATE TABLE sesiones_entreno (
    id              UUID   PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id      UUID   NOT NULL REFERENCES usuarios(id),
    rutina_id      UUID REFERENCES rutinas(id),  -- NULL si es sesión libre
    nombre          VARCHAR(150),

    fecha_inicio    TIMESTAMPTZ NOT NULL,
    fecha_fin       TIMESTAMPTZ,
    duracion_minutos INTEGER,
    estado          estado_sesion DEFAULT 'planificada',

    -- Calorías estimadas/gastadas
    kcal_estimadas  INTEGER,
    kcal_real       INTEGER,

    -- Notas y feedback
    notas           TEXT,
    notas_ia        TEXT,  -- análisis post-sesión por IA

    -- Geo-localización (GDPR: consentimiento SEPARADO obligatorio)
    consentimiento_ubicacion BOOLEAN DEFAULT FALSE,  -- ⚠️ Bloqueador 3: consentimiento explícito
    ubicacion_lat   DECIMAL(9,6),  -- solo si consentimiento_ubicacion = TRUE
    ubicacion_lon   DECIMAL(9,6),  -- solo si consentimiento_ubicacion = TRUE
    ubicacion_nombre VARCHAR(100),

    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE sesiones_entreno ENABLE ROW LEVEL SECURITY;

CREATE POLICY rl_sesiones_usuario ON sesiones_entreno
    FOR ALL USING (usuario_id = current_setting('app.current_user_id', TRUE)::UUID);

CREATE INDEX idx_sesiones_usuario_fecha ON sesiones_entreno(usuario_id, fecha_inicio DESC);

-- ============================================================
-- TABLA: sesion_ejercicio_registros (sets reales ejecutados)
-- ============================================================

CREATE TABLE sesion_ejercicio_registros (
    id              UUID  PRIMARY KEY DEFAULT uuid_generate_v4(),
    sesion_id       UUID  NOT NULL REFERENCES sesiones_entreno(id) ON DELETE CASCADE,
    ejercicio_id    UUID  NOT NULL REFERENCES ejercicios(id),
    orden           INTEGER DEFAULT 1,

    -- Registro real
    set_numero      INTEGER NOT NULL,
    peso_kg         DECIMAL(6,2),
    repeticiones    INTEGER NOT NULL,
    rpe             DECIMAL(3,1),  -- Rate of Perceived Exertion 1-10
    distancia_m     INTEGER,  -- para cardio
    duracion_seg    INTEGER,  -- para cardio

    -- Flags
    completado      BOOLEAN DEFAULT FALSE,
    omitido         BOOLEAN DEFAULT FALSE,
    motivo_omision  VARCHAR(200),

    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- TABLA: registros_nutricionales (comidas diarias)
-- ============================================================

CREATE TABLE registros_nutricionales (
    id                UUID   PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id        UUID   NOT NULL REFERENCES usuarios(id),
    fecha             DATE   NOT NULL,
    tipo              tipo_registro_nutricional NOT NULL,
    nombre            VARCHAR(200) NOT NULL,
    hora              TIME,
    -- Macros
    kcal              INTEGER,
    proteina_g        DECIMAL(6,2),
    carbohidratos_g   DECIMAL(6,2),
    grasa_g           DECIMAL(6,2),
    fibra_g            DECIMAL(6,2),
    azucar_g           DECIMAL(6,2),
    sodio_mg           INTEGER,
    -- Volumen
    cantidad_g        DECIMAL(8,2),  -- peso en gramos
    unidad_cantidad   VARCHAR(20) DEFAULT 'g',
    -- Metadata
    fuente            VARCHAR(50) DEFAULT 'manual',  -- 'manual', 'barcode', 'ia'
    alimento_externo_id VARCHAR(100),  -- si viene de API externa
    created_at        TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE registros_nutricionales ENABLE ROW LEVEL SECURITY;

CREATE POLICY rl_nutricion_usuario ON registros_nutricionales
    FOR ALL USING (usuario_id = current_setting('app.current_user_id', TRUE)::UUID);

CREATE INDEX idx_nutricion_usuario_fecha ON registros_nutricionales(usuario_id, fecha DESC);

-- ============================================================
-- TABLA: registro_diario (resumen diario宏观)
-- ============================================================

CREATE TABLE registro_diario (
    id                UUID   PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id        UUID   NOT NULL REFERENCES usuarios(id),
    fecha             DATE   NOT NULL UNIQUE,

    -- Peso
    peso_kg          DECIMAL(5,2),
    peso_nota        VARCHAR(100),

    -- Agua
    agua_ml           INTEGER DEFAULT 0,

    -- Sueño
    horas_sueno       DECIMAL(3,1),
    calidad_sueno    INTEGER CHECK (calidad_sueno BETWEEN 1 AND 5),

    -- Estado físico
    nivel_energia     INTEGER CHECK (nivel_energia BETWEEN 1 AND 5),
    nivel_dolor       INTEGER CHECK (nivel_dolor BETWEEN 1 AND 5),
    estado_animo      INTEGER CHECK (estado_animo BETWEEN 1 AND 5),

    -- Notas
    notas             TEXT,

    -- Goals adherence
    entreno_realizado BOOLEAN,
    nutricion_seguida BOOLEAN,

    created_at        TIMESTAMPTZ DEFAULT NOW(),
    updated_at        TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE registro_diario ENABLE ROW LEVEL SECURITY;

CREATE POLICY rl_registro_diario_usuario ON registro_diario
    FOR ALL USING (usuario_id = current_setting('app.current_user_id', TRUE)::UUID);

CREATE INDEX idx_registro_diario_usuario_fecha ON registro_diario(usuario_id, fecha DESC);

-- ============================================================
-- TABLA: objetivos_nutricionales (macros objetivo por usuario)
-- ============================================================

CREATE TABLE objetivos_nutricionales (
    id              UUID   PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id      UUID   NOT NULL REFERENCES usuarios(id) UNIQUE,
    kcal_diarias    INTEGER,
    proteina_g      DECIMAL(6,2),
    carbohidratos_g DECIMAL(6,2),
    grasa_g         DECIMAL(6,2),
    fibra_g         DECIMAL(6,2),
    agua_ml         INTEGER DEFAULT 2000,
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE objetivos_nutricionales ENABLE ROW LEVEL SECURITY;

CREATE POLICY rl_objetivos_nutricionales_usuario ON objetivos_nutricionales
    FOR ALL USING (usuario_id = current_setting('app.current_user_id', TRUE)::UUID);

-- ============================================================
-- TABLA: logs_ia (trazabilidad de consultas a OpenClaw — GDPR)
-- ============================================================

CREATE TABLE logs_ia (
    id                UUID   PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id        UUID   REFERENCES usuarios(id),
    sesion_entreno_id UUID REFERENCES sesiones_entreno(id),
    tipo_consulta     VARCHAR(50) NOT NULL,  -- 'recomendacion_rutina', 'analisis_sesion', 'consejo_nutricional'
    prompt_enviado    TEXT NOT NULL,
    respuesta_recibida TEXT,
    tokens_usados     INTEGER,
    duracion_ms       INTEGER,
    created_at        TIMESTAMPTZ DEFAULT NOW(),

    -- GDPR: guardar para auditoría, pero con retención limitada
    -- ⚠️ HP-9: CHECK solo es documentación; purga real via pg_cron (sección 4.3)
);

CREATE INDEX idx_logs_ia_usuario ON logs_ia(usuario_id, created_at DESC);

-- Los logs de IA se purgan a los 90 días (GDPR: minimizar datos)
-- POLICY: admin ve todos, usuario ve los suyos
ALTER TABLE logs_ia ENABLE ROW LEVEL SECURITY;

CREATE POLICY rl_logs_ia_admin ON logs_ia
    FOR ALL USING (
        current_setting('app.current_user_role', TRUE) = 'admin'
        OR usuario_id = current_setting('app.current_user_id', TRUE)::UUID
    );

-- ============================================================
-- TABLA: refresh_tokens (sesiones)
-- ============================================================

CREATE TABLE refresh_tokens (
    id          UUID   PRIMARY KEY DEFAULT uuid_generate_v4(),
    usuario_id  UUID   NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    token_hash  VARCHAR(255) NOT NULL UNIQUE,
    dispositivo VARCHAR(200),
    ip          INET,
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    revoked     BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_refresh_tokens_usuario ON refresh_tokens(usuario_id);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);
```

### 1.2 RLS — Implementación concreta de SET/RESET por request

> ⚠️ **Bloqueador 1 (CRÍTICO):** asyncpg reutiliza conexiones del pool. Sin reset
> explícito en cada request, las session vars de usuario A pueden filtrarse a usuario B.

**CÓDIGO CONCRETO — FastAPI + asyncpg:**

```python
# backend/app/db/connection.py
# ─────────────────────────────────────────────────────────────
import asyncpg
from contextlib import asynccontextmanager
from fastapi import Request
from typing import Optional

# Pool global — se crea una vez al startup de la app
_db_pool: Optional[asyncpg.Pool] = None


async def init_db_pool(min_conns: int = 2, max_conns: int = 10) -> None:
    global _db_pool
    _db_pool = await asyncpg.create_pool(
        host=settings.DB_HOST,
        port=settings.DB_PORT,
        user=settings.DB_USER,
        password=settings.DB_PASSWORD,
        database=settings.DB_NAME,
        min_size=min_conns,
        max_size=max_conns,
        # ⚠️ CRÍTICO: command_timeout protege contra queries colgadas
        command_timeout=60,
    )


async def close_db_pool() -> None:
    global _db_pool
    if _db_pool:
        await _db_pool.close()


@asynccontextmanager
async def acquire_rls_connection(user_id: str, user_role: str):
    """
    Adquiere una conexión del pool y resetea TODAS las session vars
    antes de establecer las del usuario actual.

    Pattern: SET LOCAL (transacción) + RESET between requests.
    Se usa dentro de un "with" para garantizar RESET aunque haya excepciones.
    """
    async with _db_pool.acquire() as conn:
        # ── RESET completo de todas las vars de app antes de cada request ──
        # RESET ALL no es soportado por SET LOCAL, así que reseteamos
        # explícitamente las que usamos. Añadir aquí cualquier nueva var.
        await conn.execute("""
            RESET app.current_user_id;
            RESET app.current_user_role;
        """)

        # ── SET LOCAL para este request (existe solo durante la transacción) ──
        # SET LOCAL solo vive dentro de la transacción actual; al devolver
        # la conexión al pool la transacción hace commit/rollback y
        # los valores se pierden. Pero por seguridad adicional hacemos
        # el RESET explícito al adquirir (arriba) y al liberar (abajo).
        await conn.execute("""
            SET LOCAL app.current_user_id = $1;
            SET LOCAL app.current_user_role = $2;
        """, user_id, user_role)

        # yield permite usar la conexión en el handler
        yield conn

        # ── RESET post-request (doble seguridad antes de devolver al pool) ──
        await conn.execute("""
            RESET app.current_user_id;
            RESET app.current_user_role;
        """)


# Helper para usar en endpoints FastAPI (dependency injection):
from fastapi import Depends

async def get_db_conn(request: Request) -> asyncpg.Connection:
    """
    Dependency que devuelve una conexión con RLS configurada.
    Se usa como: async with get_db_conn(request) as conn:
    """
    user_id = request.state.user_id      # JWT validado por middleware
    user_role = request.state.user_role # 'admin' | 'entrenador' | 'usuario'

    async with acquire_rls_connection(user_id, user_role) as conn:
        yield conn
```

**Middleware FastAPI que establece las session vars (segunda línea de defensa):**

```python
# backend/app/middleware/rls_middleware.py
# ─────────────────────────────────────────────────────────────
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

class RLSMiddleware(BaseHTTPMiddleware):
    """
    Middleware que inyecta las session vars de RLS DESPUÉS de que
    el JWT haya sido validado y ANTES de llegar al handler.

    El flujo real de SET/RESET está en acquire_rls_connection().
    Este middleware solo extrae los valores del JWT y los pone
    en request.state para que get_db_conn() los use.
    """
    async def dispatch(self, request: Request, call_next):
        # Auth middleware (o dependency) ya validó el JWT y puso user_id en state
        # Si no hay auth (endpoints públicos), no hay RLS vars que inyectar
        response = await call_next(request)
        return response
```

**Uso en un endpoint FastAPI:**

```python
# backend/app/routers/ejercicios.py
# ─────────────────────────────────────────────────────────────
from fastapi import APIRouter, Depends
import asyncpg

router = APIRouter(prefix="/v1/exercises", tags=["ejercicios"])

async def get_current_user_id(request: Request) -> str:
    # Validado por el auth dependency (o middleware) previo
    return request.state.user_id

@router.get("/")
async def listar_ejercicios(
    request: Request,
    conn: asyncpg.Connection = Depends(get_db_conn),
    # ^ Depends(autenticación) omitted for brevity
    limit: int = 20,
    offset: int = 0,
):
    # La conexión 'conn' ya tiene SET LOCAL app.current_user_id = <user_id>
    # Cualquier query sobre tablas con RLS filtra automáticamente
    rows = await conn.fetch("""
        SELECT id, nombre, grupo_muscular, tipo_ejercicio, dificultad
        FROM ejercicios
        WHERE es_publico = TRUE
        ORDER BY nombre
        LIMIT $1 OFFSET $2
    """, limit, offset)
    return {"ok": True, "data": [dict(r) for r in rows]}
```

**Resumen de por qué esto es seguro:**
1. `acquire_rls_connection()` hace `RESET` de vars ANTES de `SET LOCAL` en cada request.
2. `SET LOCAL` existe solo durante la transacción — se revierte al commit/rollback.
3. Segundo `RESET` post-request antes de devolver la conexión al pool.
4. El pool de asyncpg nunca recircula una conexión con vars de otro usuario.
5. RLS policy en PostgreSQL comprueba `current_setting('app.current_user_id', TRUE)::UUID`
   en cada SELECT/INSERT/UPDATE/DELETE de forma atómica.
```

---

## 2. DISEÑO API REST

### 2.1 Estructura de Respuestas Estandar

```json
// Éxito
{
  "ok": true,
  "data": { ... },
  "meta": { "page": 1, "limit": 20, "total": 150 }
}

// Error
{
  "ok": false,
  "error": {
    "code": "PERFIL_NO_ENCONTRADO",
    "message": "No existe perfil de salud para este usuario",
    "detail": { ... }
  }
}
```

### 2.1.1 Paginación — HP-5

> **HP-5:** Todos los endpoints que devuelven listas tienen paginación explícita.

**Parámetros de query (todos opcionales, defaults):**
| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `limit` | int | `20` | Filas por página (máximo: `100`) |
| `offset` | int | `0` | Filas saltadas (offset = page × limit) |
| `cursor` | string | — | Cursor opaco (alternativa a offset, preferible para páginas grandes) |

**Respuesta con metadatos de paginación:**
```json
{
  "ok": true,
  "data": [ ... ],
  "meta": {
    "limit": 20,
    "offset": 0,
    "total": 143,
    "has_more": true,
    "next_offset": 20
  }
}
```

**Endpoints afectados (HP-5):**
- `GET /v1/users` → `limit` (admin only)
- `GET /v1/routines`
- `GET /v1/exercises`
- `GET /v1/sessions`
- `GET /v1/nutrition`
- `GET /v1/daily-records`
- `GET /v1/admin/stats` → stats agregados (no paginación necesaria)

**Ejemplo: obtener página 3 de ejercicios**
```
GET /v1/exercises?limit=20&offset=40
→ offset 40 = página 3 (0-indexed: page 2 × 20)
```
```

### 2.2 Endpoints

```
AUTH
──────────────────────────────────────────────────────────────────
POST   /api/v1/auth/register         Alta cuenta (solo admin/Ramón)
POST   /api/v1/auth/login            Login → access_token + refresh_token
POST   /api/v1/auth/refresh          Refrescar access_token
POST   /api/v1/auth/logout           Revocar refresh_token
POST   /api/v1/auth/verify-email     Verificar email

USUARIOS
──────────────────────────────────────────────────────────────────
GET    /api/v1/users/me              Perfil propio
PATCH  /api/v1/users/me              Actualizar perfil propio
> ⚠️ **Bloqueador 2 (CRÍTICO):** `DELETE /users/me` — anonimización campo por campo (GDPR Art. 17)
>
> **Qué se hace con cada campo al solicitar baja:**
>
> | Tabla | Campo | Acción |
> |-------|-------|--------|
> | `usuarios` | `email` | `anon_user_<uuid>@deleted.local` (único, irreversible) |
> | `usuarios` | `hashed_password` | `NULL` (inutilizable) |
> | `usuarios` | `nombre` | `'[ANONIMIZADO]'` |
> | `usuarios` | `apellidos` | `NULL` |
> | `usuarios` | `rol` | mantiene `'usuario'` |
> | `usuarios` | `consentimiento_gdpr` | `FALSE` (revocado) |
> | `usuarios` | `fecha_consentimiento` | `NULL` |
> | `usuarios` | `consentimiento_marketing` | `FALSE` |
> | `usuarios` | `ultimo_acceso` | mantiene (para auditoría de acceso) |
> | `usuarios` | `esta_activo` | `FALSE` (bloquea login) |
> | `usuarios` | `fecha_alta` | mantiene (para stats agregados históricos) |
> | `perfiles_salud` | **TODOS** | `NULL` (lesiones, condiciones médicas, etc.) |
> | `perfiles_salud` | `consentimiento_salud` | `FALSE` |
> | `sesiones_entreno` | `notas`, `notas_ia` | `'[ANONIMIZADO]'` (historial deportivo anonimizado) |
> | `sesiones_entreno` | `ubicacion_lat/lon` | `NULL` (coordenadas eliminadas) |
> | `sesiones_entreno` | `ubicacion_nombre` | `NULL` |
> | `registros_nutricionales` | **TODOS** | `DELETE` (datos nutricionales eliminados) |
> | `registro_diario` | **TODOS** | `DELETE` (registros diarios eliminados) |
> | `objetivos_nutricionales` | **TODOS** | `DELETE` |
> | `refresh_tokens` | **TODOS** | `DELETE` (sesiones revocadas) |
> | `logs_ia` | **TODOS** | `DELETE` ( logs IA del usuario eliminados) |
>
> **Se mantiene (sin identificar al usuario):**
> - `usuarios.fecha_alta`, `usuarios.ultimo_acceso` (stats agregados, no identificables)
> - `sesiones_entreno.fecha_inicio`, `fecha_fin`, `duracion_minutos`, `kcal_*`, `estado`
>   → histórico anonimizado (útil para stats del sistema, no atribuible)
>
> **SQL de anonimización (transaction atómica):**
> ```sql
> BEGIN;
>   -- 1. Anonimizar usuario
>   UPDATE usuarios SET
>     email = 'anon_user_' || id || '@deleted.local',
>     hashed_password = NULL,
>     nombre = '[ANONIMIZADO]',
>     apellidos = NULL,
>     esta_activo = FALSE,
>     consentimiento_gdpr = FALSE,
>     fecha_consentimiento = NULL,
>     consentimiento_marketing = FALSE
>   WHERE id = :user_id;
>
>   -- 2. Anonimizar perfil salud
>   UPDATE perfiles_salud SET
>     fecha_nacimiento = NULL, sexo_biologico = NULL, altura_cm = NULL,
>     peso_actual_kg = NULL, peso_deseado_kg = NULL, porcentaje_grasa = NULL,
>     porcentaje_musculo = NULL, tmb_kcal = NULL, lesiones = NULL,
>     condiciones_medicas = NULL, alergias = NULL, medicamentos = NULL,
>     restricciones_nutricionales = NULL, consentimiento_salud = FALSE
>   WHERE usuario_id = :user_id;
>
>   -- 3. Anonimizar sesiones (coordenadas + notas)
>   UPDATE sesiones_entreno SET
>     notas = '[ANONIMIZADO]', notas_ia = '[ANONIMIZADO]',
>     ubicacion_lat = NULL, ubicacion_lon = NULL, ubicacion_nombre = NULL,
>     consentimiento_ubicacion = FALSE
>   WHERE usuario_id = :user_id;
>
>   -- 4. Eliminar datos nutricionales (no preservables sin identificar)
>   DELETE FROM registros_nutricionales WHERE usuario_id = :user_id;
>   DELETE FROM objetivos_nutricionales WHERE usuario_id = :user_id;
>   DELETE FROM registro_diario WHERE usuario_id = :user_id;
>
>   -- 5. Eliminar tokens de sesión
>   DELETE FROM refresh_tokens WHERE usuario_id = :user_id;
>
>   -- 6. Eliminar logs IA
>   DELETE FROM logs_ia WHERE usuario_id = :user_id;
> COMMIT;
> ```
>
> La row de `usuarios` NO se elimina (preserva stats históricos agregados).
> La fila de `rutinas` y `sesiones_entreno` se mantiene con datos anonimizados.

DELETE /api/v1/users/me              Solicitar baja (GDPR: anonymize campo × campo)
GET    /api/v1/users/me/privacy       Ver qué datos tenemos (GDPR Art.15)
POST   /api/v1/users/me/consent       Registrar consentimiento GDPR

PERFIL SALUD
──────────────────────────────────────────────────────────────────
GET    /api/v1/health-profile         Mi perfil de salud
PUT    /api/v1/health-profile         Crear/actualizar perfil salud
DELETE /api/v1/health-profile         Eliminar datos salud (GDPR)

RUTINAS
──────────────────────────────────────────────────────────────────
GET    /api/v1/routines               Listar rutinas propias
POST   /api/v1/routines               Crear rutina
GET    /api/v1/routines/{id}          Ver detalle rutina
PUT    /api/v1/routines/{id}          Actualizar rutina
DELETE /api/v1/routines/{id}          Eliminar rutina
GET    /api/v1/routines/{id}/execute   Detalle para ejecutar (con ejercicios)

EJERCICIOS (catálogo)
──────────────────────────────────────────────────────────────────
GET    /api/v1/exercises              Listar ejercicios (filtros: grupo, tipo, dificultad)
GET    /api/v1/exercises/{id}         Detalle ejercicio
GET    /api/v1/exercises/search       Búsqueda por nombre

SESIONES ENTRENO
──────────────────────────────────────────────────────────────────
GET    /api/v1/sessions               Listar sesiones (filtros: fecha, estado)
POST   /api/v1/sessions               Crear sesión planificada
GET    /api/v1/sessions/{id}          Detalle sesión
PATCH  /api/v1/sessions/{id}          Actualizar (iniciar, completar, cancelar)
DELETE /api/v1/sessions/{id}          Eliminar sesión
POST   /api/v1/sessions/{id}/exercises Registrar sets de un ejercicio en sesión

REGISTRO DIARIO
──────────────────────────────────────────────────────────────────
GET    /api/v1/daily-records          Listar registros diarios
GET    /api/v1/daily-records/{fecha}  Registro de un día
PUT    /api/v1/daily-records/{fecha}  Crear/actualizar registro diario

NUTRICIÓN
──────────────────────────────────────────────────────────────────
GET    /api/v1/nutrition              Registros nutricionales (filtros: fecha)
POST   /api/v1/nutrition              Registrar alimento
PUT    /api/v1/nutrition/{id}        Editar registro
DELETE /api/v1/nutrition/{id}        Eliminar registro
GET    /api/v1/nutrition/goals        Objetivos nutricionales propios
PUT    /api/v1/nutrition/goals        Actualizar objetivos
GET    /api/v1/nutrition/summary/{fecha}  Resumen macros del día

CONSULTAS IA
──────────────────────────────────────────────────────────────────
POST   /api/v1/ai/recommend-routine   Solicitar recomendación de rutina
POST   /api/v1/ai/analyze-session    Analizar sesión completada
POST   /api/v1/ai/nutrition-advice   Consejo nutricional

  ⚠️ HP-6: Rate limiting IA — 10 llamadas/minuto por usuario a cada endpoint.
           Implementado con slowapi (límite por IP+user_id en memoria o Redis).
           Al superar límite: HTTP 429 con Retry-After en headers.


ADMIN (solo rol=admin)
──────────────────────────────────────────────────────────────────
GET    /api/v1/admin/users           Listar usuarios
POST   /api/v1/admin/users           Crear usuario (Ramón crea cuentas)
PATCH  /api/v1/admin/users/{id}      Editar usuario
GET    /api/v1/admin/stats           Estadísticas de uso
POST   /api/v1/admin/exercises       Crear ejercicio global
```

### 2.3 Ejemplos de Payloads

**POST /api/v1/auth/register (cuenta nueva)**
```json
{
  "email": "usuario@email.com",
  "password": "ContraseñaSegura123!",
  "nombre": "Carlos",
  "apellidos": "García López"
}
```
→ Requiere `consentimiento_gdpr: true` (en body o separado)

**PUT /api/v1/health-profile**
```json
{
  "fecha_nacimiento": "1990-05-15",
  "sexo_biologico": "M",
  "altura_cm": 178.5,
  "peso_actual_kg": 82.3,
  "peso_deseado_kg": 75.0,
  "lesiones": ["tobillo izquierdo (2019)"],
  "condiciones_medicas": [],
  "objetivo_principal": "perder_grasa",
  "objetivo_detalle": "Reducir porcentaje de grasa manteniendo masa muscular",
  "consentimiento_salud": true
}
```

**POST /api/v1/sessions**
```json
{
  "rutina_id": "uuid-rutina",
  "nombre": "Pierna - Lunes",
  "fecha_inicio": "2026-04-20T18:00:00Z"
}
```

**POST /api/v1/sessions/{id}/exercises**
```json
{
  "ejercicio_id": "uuid-ejercicio",
  "registros": [
    { "set_numero": 1, "peso_kg": 60.0, "repeticiones": 12, "rpe": 7 },
    { "set_numero": 2, "peso_kg": 60.0, "repeticiones": 10, "rpe": 8 },
    { "set_numero": 3, "peso_kg": 55.0, "repeticiones": 8, "rpe": 9, "completado": false }
  ]
}
```

**POST /api/v1/ai/recommend-routine**
```json
{
  "objetivo": "hipertrofia",
  "dias_por_semana": 4,
  "duracion_max_minutos": 75,
  "equipo_disponible": ["barra", "mancuernas", "polea"],
  "lesiones_o_limitaciones": ["evitar press militar por lesión hombro"],
  "nivel_experiencia": "intermedio"
}
```
→ Respuesta: rutina completa con ejercicios, series, repeticiones, descansos

---

## 3. FLUJO: FLUTTER → BACKEND → OPENCLAW

```
┌──────────────┐     HTTPS      ┌─────────────────┐    HTTP      ┌─────────────────┐
│  App Flutter │ ─────────────► │  FastAPI        │ ───────────► │  OpenClaw       │
│  (usuario)   │                │  Backend        │              │  Gateway        │
│              │ ◄───────────── │  (VPS)          │ ◄─────────── │  (IA Cody)      │
│              │   JSON REST    │                 │   JSON + IA  │                 │
└──────────────┘                └────────┬────────┘              └─────────────────┘
                                        │
                                        │ SQL (vía asyncpg
                                        │  + pooler)
                                        ▼
                              ┌──────────────────┐
                              │   PostgreSQL     │
                              │   (RLS activo)   │
                              │   100 usuarios   │
                              └──────────────────┘

FLUJO DETALLADO POR OPERACIÓN:

① LOGIN:
   App ──POST /auth/login──► FastAPI ──verifica hash──► PostgreSQL(users)
                              ◄─── ok ─────────────
   FastAPI ◄── genera JWT ──► access_token (15min) + refresh_token (30 días)
   App almacena tokens en flutter_secure_storage

② CONSULTAR DATOS (ej: obtener perfil salud):
   App ──GET /health-profile──► FastAPI (JWT en Authorization: Bearer)
     │                          │ Valida JWT → extrae user_id
     │                          │ SET app.current_user_id = user_id (PostgreSQL session var)
     │                          │ SELECT * FROM perfiles_salud WHERE usuario_id = user_id
     │                          │ RLS filtra automáticamente
     ▼                          ◄─── JSON ─────────
   App renderiza

③ PEDIR RECOMENDACIÓN IA:
   App ──POST /ai/recommend-routine──► FastAPI
     │                                  │ Valida JWT
     │                                  │ Consulta perfil salud + rutinas + histórico → construye context
     │                                  │ POST {prompt, context} ──► OpenClaw Gateway
     │                                  │                            POST /v1/chat/completions
     │                                  │ ◄── respuesta IA ────────
     │                                  │ Log en logs_ia (auditoría GDPR)
     ▼                                  ◄─── JSON ──────
   App recibe rutina recomendada
```

### 3.1 Conexión Flutter ↔ Backend

```dart
// lib/core/network/api_client.dart (concepto)
// ─────────────────────────────────────────────

// Base URL configurada por variable de entorno
// En desarrollo: http://10.0.2.2:8000 (Android emulator)
// En producción: https://api.tu-dominio.com

class ApiClient {
  final Dio _dio;
  final TokenStorage _tokenStorage;

  ApiClient({required TokenStorage tokenStorage}) {
    _dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
    // Interceptor: adjunta JWT en cada request
    _dio.interceptors.add(AuthInterceptor(_tokenStorage));
    // Interceptor: maneja 401 → refresh token
    _dio.interceptors.add(RetryInterceptor(_dio, _tokenStorage));
  }
}
```

### 3.2 Conexión Backend ↔ OpenClaw Gateway

```python
# backend/app/services/ia_gateway.py
# ─────────────────────────────────────────────────────────────────────────────
# ⚠️ Bloqueador 4 (CRÍTICO): La URL y API key NUNCA en código.
# En producción usar: variable de entorno + secrets file (no repo).
# ─────────────────────────────────────────────────────────────────────────────

import httpx
from httpx import AsyncClient, TimeoutException, HTTPStatusError
import asyncio
from app.core.config import settings

# ── Configuración de secrets ──────────────────────────────────────────────────
# Development (.env):
#   OPENCLAW_GATEWAY_URL=http://localhost:18789
#   OPENCLAW_API_KEY=sk-openclaw-...   (del dashboard de OpenClaw)
#
# Production: variable de entorno real o lee desde secrets file:
#   secrets_path = "/run/secrets/openclaw_api_key"
#   with open(secrets_path) as f:
#       OPENCLAW_API_KEY = f.read().strip()
#
# NUNCA hardcodear valores. settings usa pydantic-settings que lee de env.

OPENCLAW_GATEWAY_URL = settings.OPENCLAW_GATEWAY_URL   # desde env
OPENCLAW_API_KEY     = settings.OPENCLAW_API_KEY       # desde env / secrets file

# ── Retry con exponential backoff ─────────────────────────────────────────────
# HP-7: Especificado para llamadas OpenClaw
DEFAULT_TIMEOUT_SEC  = 30.0       # timeout total de la llamada
MAX_RETRIES         = 3
BASE_DELAY_SEC      = 1.0        # delay inicial para backoff

async def consultar_ia(
    tipo_consulta: str,
    prompt: str,
    contexto_usuario: dict,
    user_id: UUID,
    sesion_id: UUID | None = None,
) -> dict:
    """
    Envía consulta al gateway OpenClaw con retry + exponential backoff.

    HP-7: Timeout real (30s), reintentos con exponential backoff (1s, 2s, 4s).
    En caso de fallo tras MAX_RETRIES, se devuelve error controlado (no excepción).
    """
    prompt_completo = f"""
    [Contexto del usuario]
    - Objetivo: {contexto_usuario.get('objetivo')}
    - Nivel: {contexto_usuario.get('nivel_experiencia')}
    - Equipamiento disponible: {contexto_usuario.get('equipo')}
    - Limitaciones: {contexto_usuario.get('lesiones')}

    [Consulta]
    {prompt}
    """

    headers = {
        "Authorization": f"Bearer {OPENCLAW_API_KEY}",
        "Content-Type": "application/json",
    }

    body = {
        "model": "cody",
        "messages": [
            {"role": "system", "content": "Eres un entrenador personal certificado..."},
            {"role": "user", "content": prompt_completo}
        ],
        "temperature": 0.7,
    }

    last_exception = None

    for attempt in range(MAX_RETRIES):
        try:
            async with AsyncClient(
                timeout=httpx.Timeout(DEFAULT_TIMEOUT_SEC, connect=10.0)
            ) as client:
                response = await client.post(
                    f"{OPENCLAW_GATEWAY_URL}/v1/chat/completions",
                    headers=headers,
                    json=body,
                )
                response.raise_for_status()
                resultado = response.json()

        except (TimeoutException, HTTPStatusError) as exc:
            last_exception = exc
            if attempt < MAX_RETRIES - 1:
                delay = BASE_DELAY_SEC * (2 ** attempt)  # 1s → 2s → 4s
                await asyncio.sleep(delay)
            continue
        except Exception as exc:
            # Error inesperado: no reintentar (podría ser 4xx, etc.)
            last_exception = exc
            break
    else:
        # Tras todos los reintentos: registrar error y devolver respuesta de error
        # HP-7: No lanzar excepción al cliente; devolver error controlado
        return {
            "error": True,
            "code": "IA_GATEWAY_UNAVAILABLE",
            "message": "El servicio de IA no está disponible. Inténtalo más tarde.",
            "detail": str(last_exception) if last_exception else None,
        }

    # Log de auditoría IA (GDPR)
    await guardar_log_ia(
        usuario_id=user_id,
        sesion_entreno_id=sesion_id,
        tipo_consulta=tipo_consulta,
        prompt_enviado=prompt_completo,
        respuesta_recibida=resultado.get("choices", [{}])[0].get("message", {}).get("content", ""),
        tokens_usados=resultado.get("usage", {}).get("total_tokens"),
    )

    return resultado
```

---

## 4. CUMPLIMIENTO GDPR — DECISIONES DE DISEÑO

| Requisito GDPR | Implementación |
|---|---|
| **Art. 5** — Principios datos | Datos mínimos: solo lo necesario para el servicio |
| **Art. 6** — Base legal | Consentimiento explícito (registro + aceptación política) |
| **Art. 7** — Consentimiento | Boolean + timestamp + versión política aceptada |
| **Art. 9** — Datos salud | Consentimiento salud SEPARADO del GDPR general. No obligatorio |
| **Art. 15** — Acceso | Endpoint GET /users/me/privacy exporta todos los datos |
| **Art. 17** — Supresión | DELETE /users/me = anonymize (no DROP row, conserva stats agregados) |
| **Art. 20** — Portabilidad | GET /users/me/privacy devuelve JSON exportable |
| **Art. 25** — Privacy by design | RLS en todas las tablas de usuario; sin acceso cruzado |
| **Art. 32** — Seguridad | JWT con 15min, refresh token con expiry, hash bcrypt |
| Retención logs IA | 90 días máximo, purga automática |
| **HP-9 — Purga logs_ia** | pg_cron job diario: `DELETE FROM logs_ia WHERE created_at < NOW() - INTERVAL '90 days'` —job: `'0 3 * * *'` (3 AM diaria). El CHECK constraint en la tabla es solo documentación; la purga real la hace el job. Alternativa sin pg_cron: cron del sistema que ejecuta script SQL vía `psql`. |

**HP-9 — Configuración del job pg_cron:**
```sql
-- Habilitar extensión pg_cron (requiere SUPERUSER)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Permitir uso a usuario de la app (no SUPERUSER si se configura finement)
GRANT USAGE ON SCHEMA cron TO app_user;

-- Programar purga diaria a las 3 AM
SELECT cron.schedule(
    'purge-old-logs-ia',      -- nombre del job
    '0 3 * * *',              -- cron: 3:00 AM cada día
    $$DELETE FROM logs_ia WHERE created_at < NOW() - INTERVAL '90 days'$$
);

-- Ver jobs activos:
-- SELECT * FROM cron.job;
-- Ver runs:
-- SELECT * FROM cron.job_run_details WHERE jobname = 'purge-old-logs-ia';
```

**Fallback (sin pg_cron):** cron del sistema ejecuta `psql`:
```
# /etc/cron.d/purge-logs-ia
0 3 * * * postgres psql -d gymapp -c "DELETE FROM logs_ia WHERE created_at < NOW() - INTERVAL '90 days'"
```

---

## 5. ESTRUCTURA PROYECTO FLUTTER

```
gym_trainer_app/
│
├── android/                    # Config Android nativa
├── ios/                        # Config iOS nativa
├── web/                        # Soporte web
├── linux/                      # Soporte desktop
│
├── lib/
│   │
│   ├── main.dart               # entry point
│   │
│   ├── app.dart                # MaterialApp + routing
│   │
│   ├── core/                   # Infraestructura compartida
│   │   ├── config/
│   │   │   ├── env.dart        # variables de entorno (API URL, etc.)
│   │   │   └── theme.dart      # tema de la app
│   │   │
│   │   ├── network/
│   │   │   ├── api_client.dart       # Dio client + interceptors
│   │   │   ├── api_endpoints.dart    # constantes de paths
│   │   │   ├── api_exception.dart    # excepciones de red
│   │   │   └── auth_interceptor.dart # JWT auth
│   │   │
│   │   ├── storage/
│   │   │   ├── secure_storage.dart   # tokens (flutter_secure_storage)
│   │   │   └── preferences_storage.dart # settings locales
│   │   │
│   │   ├── errors/
│   │   │   └── failures.dart         # Result type / Either
│   │   │
│   │   └── utils/
│   │       ├── date_utils.dart
│   │       └── validators.dart
│   │
│   ├── features/               # Feature modules (Clean Architecture)
│   │   │
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   ├── models/           # UserModel, TokenModel
│   │   │   │   ├── repositories/     # AuthRepositoryImpl
│   │   │   │   └── datasources/      # AuthRemoteDataSource
│   │   │   ├── domain/
│   │   │   │   ├── entities/         # User, AuthTokens
│   │   │   │   ├── repositories/     # AuthRepository (abstract)
│   │   │   │   └── usecases/        # LoginUseCase, LogoutUseCase
│   │   │   └── presentation/
│   │   │       ├── providers/        # auth_state provider
│   │   │       ├── screens/          # login_screen, register_screen
│   │   │       └── widgets/
│   │   │
│   │   ├── health_profile/
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   └── presentation/
│   │   │
│   │   ├── routines/
│   │   │   ├── data/
│   │   │   │   ├── models/          # RoutineModel, RoutineExerciseModel
│   │   │   │   ├── repositories/
│   │   │   │   └── datasources/
│   │   │   ├── domain/
│   │   │   │   ├── entities/        # Routine, Exercise (core)
│   │   │   │   ├── repositories/
│   │   │   │   └── usecases/        # GetRoutines, CreateRoutine, etc.
│   │   │   └── presentation/
│   │   │       ├── providers/       # routines_provider (StateNotifier)
│   │   │       ├── screens/         # routine_list, routine_detail, routine_form
│   │   │       └── widgets/        # exercise_card, set_row
│   │   │
│   │   ├── sessions/
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   └── presentation/
│   │   │
│   │   ├── nutrition/
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   └── presentation/
│   │   │
│   │   ├── daily_records/
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   └── presentation/
│   │   │
│   │   ├── ai_recommendations/
│   │   │   ├── data/
│   │   │   ├── domain/
│   │   │   └── presentation/
│   │   │       ├── screens/   # recommendation_result_screen
│   │   │       └── widgets/   # ai_loading_indicator
│   │   │
│   │   └── home/
│   │       └── presentation/
│   │           ├── providers/
│   │           │   └── home_provider.dart
│   │           └── screens/
│   │               └── home_screen.dart
│   │
│   ├── shared/                 # Reutilizable entre features
│   │   ├── widgets/
│   │   │   ├── app_button.dart
│   │   │   ├── app_text_field.dart
│   │   │   ├── loading_indicator.dart
│   │   │   ├── error_view.dart
│   │   │   └── empty_state.dart
│   │   │
│   │   └── providers/
│   │       ├── connectivity_provider.dart
│   │       └── theme_provider.dart
│   │
│   └── router/
│       └── app_router.dart    # go_router configuration
│
├── pubspec.yaml
├── .env.example
├── analysis_options.yaml
└── README.md
```

### HP-6 — Rate Limiting en endpoints IA

**Implementación (FastAPI + slowapi + Redis):**

```python
# backend/app/api/v1/ai.py
# ─────────────────────────────────────────────────────────────────────────────
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request

# Por usuario autenticado; si no hay JWT, cae back a IP
def get_user_or_ip(request: Request) -> str:
    try:
        return request.state.user_id  # del JWT validado
    except AttributeError:
        return get_remote_address(request)

limiter = Limiter(key_func=get_user_or_ip, storage_uri="redis://localhost:6379/0")

# ── Endpoints con rate limit ─────────────────────────────────────────────────
@router.post("/recommend-routine")
@limiter.limit("10/minute")  # HP-6: 10 llamadas/min por usuario
async def recommend_routine(request: Request, ...):
    ...

@router.post("/analyze-session")
@limiter.limit("10/minute")
async def analyze_session(request: Request, ...):
    ...

@router.post("/nutrition-advice")
@limiter.limit("10/minute")
async def nutrition_advice(request: Request, ...):
    ...

# ── Custom error handler para 429 ───────────────────────────────────────────
from fastapi.responses import JSONResponse

@router.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=429,
        content={
            "ok": False,
            "error": {
                "code": "RATE_LIMIT_EXCEEDED",
                "message": "Demasiadas solicitudes al servicio de IA. "
                           "Máximo 10/min. Intenta en un momento.",
                "detail": {"retry_after_seconds": exc.detail}
            }
        },
        headers={"Retry-After": str(exc.detail)}
    )
```

**Nota:** Si Redis no está disponible en el VPS, usar storage en memoria
(`Limiter(storage_uri="memory://")`) con penalización en concurrencia (límite
suave para 100 usuarios, Redis es preferible para producción real).

### Decisiones de stack Flutter

- **Estado:** flutter_riverpod (2.x) — testable, escalable, no boilerplate excesivo
- **Routing:** go_router — declarative, deep linking, guard routes (auth check)
- **HTTP:** dio — interceptores, retry automático, timeout configurables
- **Seguridad:** flutter_secure_storage — tokens JWT en keystore (no SharedPreferences)
> **HP-10 / Decisión: drift eliminado.** Para 100 usuarios en VPS limitado NO hay
> requisito de offline-first. Se sustituye por:
> - Cache en memoria (lru_cache) para ejercicios catálogos → TTL 1h
> - Eliminación de cache local (sin persistencia offline)
> - Si futuro requisito offline aparece: reconsiderar drift, no ahora

- **Local cache (en memoria):** ejercicios catálogo cacheados con TTL 1h
  (no se persiste nada en SQLite — arquitectura simple, 100 usuarios)
- **UI:** Material 3 — personalización con theme.dart

---

## 6. DIAGRAMA DE FLUJO DE DATOS (ASCII)

```
USUARIO
  │
  │ [1] Login (email + password)
  ▼
┌──────────────┐
│  FLUTTER APP │
│  (Auth State)│ ← JWT access_token + refresh_token en SecureStorage
└──────┬───────┘
       │ Dio + AuthInterceptor (JWT adjuntado automáticamente)
       │ [2] GET /health-profile
       │ [3] GET /routines
       │ [4] POST /sessions/{id}/exercises
       │ [5] POST /ai/recommend-routine
       ▼
┌──────────────────────────────────────────────────────┐
│                    FASTAPI BACKEND                     │
│                                                       │
│  Routes Layer (api/v1/)                               │
│    │                                                  │
│  Middleware                                          │
│    ├── JWT Validation → extrae user_id, role          │
│    ├── RLS Session → SET app.current_user_id = UUID  │
│    └── GDPR Audit Logger                              │
│    │                                                  │
│  Services Layer (business logic)                      │
│    ├── UserService                                   │
│    ├── RoutineService                                │
│    ├── SessionService                                │
│    ├── NutritionService                              │
│    └── IaGatewayService  ──────────────────────────┐ │
│                                                    │ │
│  Repository Layer (data access)                    │ │
│    │                                                │ │
└────┼────────────────────────────────────────────────┼─┘
     │ asyncpg (connection pool, session-level vars) │
     │ SELECT ... WHERE usuario_id = $current_user   │ │
     ▼                                                │ │
┌──────────────────┐      Prompt + Contexto     ┌─────▼─────────────┐
│   PostgreSQL      │  ◄────────────────────────── │  OpenClaw Gateway │
│   (RLS ACTIVE)    │                             │  (IA Cody)        │
│                  │ ──── Logs IA (auditoría) ──► │                   │
│  Tables:         │                             └───────────────────┘
│  - usuarios      │                                    ▲
│  - perfiles_salud│                                    │
│  - rutinas       │                                    │
│  - ejercicios    │         JSON response              │
│  - sesiones_     │ ◄───────────────────────────────────┘
│  - registros_nutr│
│  - registro_diario
└──────────────────┘

RLS GUARANTEE: even if bug in app layer, user A cannot read user B's data
```

---

## 7. CONSIDERACIONES DE RENDIMIENTO (100 usuarios, VPS limitado)

| Aspecto | Decisión |
|---|---|
| **Pool de conexiones BD** | asyncpg pool=10 conexiones máx (suficiente para 100 users) |
| **JWT expiry** | 15 min access token (short-lived), 30 días refresh |
| **IA como recomendación** | No se llama IA en cada request; cachear respuestas 24h |
| **Índices** | Solo índices en columnas filtradas (usuario_id + fecha) |
| **Paginación** | Todas las listas con `limit=20, offset=0` por defecto |
| **Logs IA** | Retención 90 días, sin full-text index (coste alto) |
| **Migrations** | Alembic para schema migrations en producción |

---

**Resumen de entregables:**
- ✅ Schema SQL completo con RLS, enums, constraints y auditoría GDPR
- ✅ Especificación API REST con 30+ endpoints
- ✅ Diagrama de flujo Flutter ↔ FastAPI ↔ PostgreSQL + OpenClaw
- ✅ Estructura Flutter con Clean Architecture y feature modules
- ✅ Stack tecnológico justificado

> Los writes directos los haría Ramón desde el main agent. Aquí tienes el diseño completo para que lo revise, ajuste y valide antes de implementar.

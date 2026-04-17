# Gym Trainer App

Estado actual: siguiente fase mínima útil encima del prototipo.

## Decisión de repositorio
Se publica como **monorepo**.

Motivo: backend, app Flutter, SQL y documentación siguen siendo un solo producto con releases acopladas. Separarlo ahora añadiría fricción sin beneficio claro.

Referencia breve: `docs/repository-strategy.md`.

## Qué incluye

### Backend (`backend/`)
- FastAPI con estructura modular por `app/`
- Variables de entorno con `.env.example`
- PostgreSQL real mediante SQLAlchemy + psycopg
- Endpoints:
  - `GET /`
  - `GET /api/v1/health`
  - `GET /api/v1/exercises`
- `docker-compose.yml` para levantar PostgreSQL local
- `db/schema.sql` con tabla `exercises` y seed inicial

### Flutter (`flutter_app/`)
- Skeleton de app con pantalla inicial más útil
- Llamada real al backend en `GET /api/v1/exercises`
- Lista, recarga manual, pull-to-refresh y estados de error
- Preparada para completar plataformas con `flutter create .`

## Estructura

```text
backend/
  app/
  db/schema.sql
  docker-compose.yml
flutter_app/
docs/
Makefile
README.md
```

## Arranque rápido

### Backend

```bash
cp backend/.env.example backend/.env
make backend-install
make backend-up
make backend-run
```

Checks:

```bash
make backend-check
```

### Flutter

Requiere Flutter SDK instalado en la máquina:

```bash
cd flutter_app
flutter create .
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1
```

Para Android Emulator:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

## Qué funciona ya
- Backend sirviendo ejercicios desde PostgreSQL real, no desde memoria.
- Healthcheck validando conexión a base de datos.
- Seed inicial persistido en PostgreSQL.
- Flutter preparado para consumir esos datos con una UI base más sólida.
- Repo listo para publicarse como monorepo.

## Limitaciones reales ahora mismo
- No hay auth ni usuarios todavía.
- No hay tests automáticos aún.
- En este entorno no está instalado Flutter SDK, así que no pude ejecutar `flutter create` ni `flutter run` aquí.
- En este entorno tampoco está instalado `gh`; para GitHub usaré API HTTP con el PAT disponible.

## Siguiente paso recomendado
1. Añadir detalle de ejercicio y modelo de rutina.
2. Crear login mock o sesión mínima.
3. Montar CI básica para backend y lint Flutter.

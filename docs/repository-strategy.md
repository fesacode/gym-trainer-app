# Estrategia de repositorio

## Decisión
Monorepo único: `gym-trainer-app`

## Motivo breve
Ahora mismo backend, app Flutter, esquema SQL y documentación forman un solo producto y avanzan al mismo ritmo. Separarlos ya metería sobrecoste en coordinación, versionado y CI sin dar una ventaja real.

## Cuándo dividirlo después
Si el backend empieza a servir a más clientes, aparecen equipos distintos o necesitamos releases totalmente independientes, entonces sí tiene sentido separar `gym-trainer-api` y `gym-trainer-flutter`.

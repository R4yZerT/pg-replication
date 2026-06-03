# PostgreSQL Streaming Replication Lab

Primary → Standby streaming replication con Docker Compose.
Basado en [Marcel Dempers' guide](https://github.com/marcel-dempers/docker-development-youtube-series/tree/master/storage/databases/postgresql/3-replication)
y [este video](https://www.youtube.com/watch?v=FC2JMBYDcJE).

---

## Arquitectura

```
┌─ TU MÁQUINA (macOS) ───────────────────────────────────────┐
│                                                              │
│  ┌──────────────┐    streaming WAL    ┌──────────────┐       │
│  │  pg-primary  │ ──────────────────▶ │  pg-replica  │       │
│  │  (read-write)│      TCP 5432       │  (read-only) │       │
│  │  puerto 5432 │                     │  puerto 5433 │       │
│  └──────┬───────┘                     └──────────────┘       │
│         │                                                    │
│         │ puerto 5432 expuesto en 0.0.0.0                    │
├─────────┼────────────────────────────────────────────────────┤
│         ▼                                                     │
│  ┌──────────────┐                                            │
│  │  Tu compañero│  psql -h 192.168.x.x -p 5432 -U postgres  │
│  │  (otra PC)   │  Misma red local                           │
│  └──────────────┘                                            │
└──────────────────────────────────────────────────────────────┘
```

---

## Prerequisitos

- Docker Desktop 4.15+ (con Compose V2)
- Apple Silicon (M1/M2/M3) o Intel — imagen `postgres:16` (multi-arch)
- Tu compañero solo necesita un cliente PostgreSQL (`psql`, DBeaver, etc.)

---

## Comandos esenciales

### 1. Iniciar el lab

```bash
cd /Users/yeipezz/Documents/pg-replication
docker compose up -d --build
```

Esto levanta:
- **pg-primary** (lectura/escritura, puerto `5432`)
- **pg-replica** (solo lectura, puerto `5433`)

### 2. Verificar que la replicación funciona

```bash
# Ver WAL sender activo (state = streaming)
docker compose exec primary psql -U postgres -c \
  "SELECT client_addr, state, sync_state FROM pg_stat_replication;"

# Ver replication slot activo (active = t)
docker compose exec primary psql -U postgres -c \
  "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;"
```

### 3. Probar datos reales

```bash
# Escribir en primary
docker compose exec primary psql -U postgres -c "
  CREATE TABLE demo (id serial PRIMARY KEY, data text, created_at timestamptz DEFAULT now());
  INSERT INTO demo (data) VALUES ('hola desde primary');
"

# Leer en replica — debe aparecer inmediatamente
docker compose exec replica psql -U postgres -c "SELECT * FROM demo;"

# Verificar que replica es read-only (debe fallar)
docker compose exec replica psql -U postgres -c "CREATE TABLE fail (id int);"
```

### 4. Medir lag (opcional)

```bash
# Lag en tiempo desde primary
docker compose exec primary psql -U postgres -c \
  "SELECT write_lag, flush_lag, replay_lag FROM pg_stat_replication;"

# Lag en bytes desde replica
docker compose exec replica psql -U postgres -c \
  "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(),
          pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn() AS lag_bytes;"
```

### 5. Detener y limpiar

```bash
docker compose down -v
```

---

## Cómo se conecta tu compañero (misma red local)

Tu máquina expone PostgreSQL en **`0.0.0.0:5432`** (todas las interfaces de red).

### Paso 1: Obtén tu IP local

```bash
ipconfig getifaddr en0
# Ejemplo: 192.168.20.72
```

### Paso 2: Tu compañero se conecta con cualquier cliente

```bash
# psql
psql -h 192.168.20.72 -p 5432 -U postgres -d postgres

# Cadena de conexión universal
postgresql://postgres:postgres@192.168.20.72:5432/postgres
```

**Credenciales por defecto:**

| Variable | Valor |
|---|---|
| Usuario | `postgres` |
| Password | `postgres` |
| Base de datos | `postgres` |
| Puerto primary | `5432` |
| Puerto replica | `5433` |

> Si no conecta, desactivar temporalmente el firewall de macOS:
> **Preferencias del Sistema → Red → Firewall → Apagar**
> (O agregar Docker a la lista de permitidos)

### ¿Qué ve tu compañero?

- **Primary (5432):** lectura y escritura. Puede insertar, modificar, borrar.
- **Replica (5433):** solo lectura. Lo que escriba en el primary aparece automáticamente aquí.

---

## Explicación de la configuración

### ¿Dónde se habilita la replicación?

**Archivo:** `primary/config/postgresql.conf`

```ini
wal_level = replica         # Nivel de WAL suficiente para replicación
max_wal_senders = 3         # Máximo de conexiones de replicación simultáneas
wal_keep_size = 256MB       # WAL retenido por si el standby se desconecta
```

- `wal_level = replica` — genera suficiente información en los WAL para que un standby pueda reconstruir la base de datos. Valores posibles: `minimal` (solo recuperación de crash), `replica` (permite replicación), `logical` (permite replicación lógica además de física).
- `max_wal_senders = 3` — cantidad de procesos WAL sender que pueden estar activos. Cada standby consume un sender.
- `wal_keep_size = 256MB` — espacio en disco reservado para retener segmentos WAL. Si el standby se atrasa más de esto sin usar un replication slot, pierde sincronía.

### ¿Quién puede replicar?

**Archivo:** `primary/config/pg_hba.conf`

```
host  replication  replicator  0.0.0.0/0  scram-sha-256
```

Esta línea permite al usuario `replicator` (creado en `01-setup-replication.sql`) conectarse desde cualquier IP para hacer replicación.

### ¿Cómo se crea el usuario de replicación?

**Archivo:** `primary/init/01-setup-replication.sql`

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl123';
SELECT pg_create_physical_replication_slot('replication_slot_1');
```

- `REPLICATION` — permiso especial para ejecutar `pg_basebackup` y conectar como WAL receiver.
- `replication_slot_1` — garantiza que el primary no borre segmentos WAL hasta que el standby los consuma.

### ¿Cómo se inicializa el standby?

**Archivo:** `replica/init-replica.sh`

```bash
pg_basebackup -h pg-primary -p 5432 -U replicator \
  -D "$PGDATA" -Fp -Xs -R -S replication_slot_1 -P -v
```

| Parámetro | Qué hace |
|---|---|
| `-h pg-primary` | Host del primary (nombre del servicio Docker) |
| `-U replicator` | Usuario con permiso REPLICATION |
| `-D "$PGDATA"` | Directorio donde escribir el backup |
| `-Fp` | Formato plain (archivos normales, no tar) |
| `-Xs` | Incluye WAL al final del backup (streaming) |
| `-R` | **Crea `standby.signal`** y escribe `primary_conninfo` en `postgresql.auto.conf` |
| `-S replication_slot_1` | Usa el replication slot para no perder WAL |
| `-P -v` | Muestra progreso verbose |

### Modo hot standby

**Archivo:** `replica/config/postgresql.conf`

```ini
hot_standby = on
```

Permite que el standby acepte consultas SELECT (solo lectura) mientras aplica WAL. Si estuviera en `off`, el standby no aceptaría ninguna conexión.

---

## Flujo completo: ¿cómo viajan los datos?

```
1. Cliente escribe:  INSERT INTO demo VALUES (1);
2. Primary:          Escribe el cambio en el WAL (Write-Ahead Log)
3. WAL sender:       Proceso que lee el WAL y lo envía por TCP al standby
4. Red:              Los bytes viajan al puerto 5432 del standby
5. WAL receiver:     Proceso en standby que recibe los datos
6. WAL write:        Los escribe en disco (pg_wal del standby)
7. WAL flush:        Los asegura en disco
8. WAL replay:       Aplica los cambios a los archivos de datos
9. Replica visible:  SELECT en replica ya muestra el dato
```

Cada paso tiene su LSN (Log Sequence Number). Puedes monitorearlos con:

```bash
docker compose exec primary psql -U postgres -c \
  "SELECT sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
```

- `sent_lsn` = último byte enviado por el primary
- `write_lsn` = último byte recibido y escrito por el standby
- `flush_lsn` = último byte flusheado a disco en standby
- `replay_lsn` = último byte aplicado (visible en queries)

Si todos son iguales, el standby está **al día** sin lag.

---

## Failover (simular caída del primary)

```bash
# 1. Apagar primary
docker compose stop primary

# 2. Promover replica a nuevo primary
docker compose exec replica bash -c "pg_ctl promote -D /data"

# 3. Replica ahora acepta escritura
docker compose exec replica psql -U postgres -c "INSERT INTO demo (data) VALUES ('promovido!');"

# 4. Para restaurar el setup original, limpiar y rebuild
docker compose down -v
docker compose up -d --build
```

---

## Estructura del proyecto

```
pg-replication/
├── docker-compose.yml                 # Orquestación primary + replica
├── README.md
├── primary/
│   ├── config/
│   │   ├── postgresql.conf            # wal_level=replica, max_wal_senders=3
│   │   ├── pg_hba.conf                # replica user authentication
│   │   └── pg_ident.conf              # mapa de usuarios (vacio por defecto)
│   └── init/
│       └── 01-setup-replication.sql   # CREATE ROLE replicator + slot
└── replica/
    ├── Dockerfile                     # postgres:16 + entrypoint personalizado
    ├── config/
    │   ├── postgresql.conf            # hot_standby=on
    │   ├── pg_hba.conf                # solo trust localhost + scram-sha-256
    │   └── pg_ident.conf              # mapa de usuarios (vacio por defecto)
    └── init-replica.sh               # pg_basebackup al arrancar
```

---

## Variables de entorno (personalizables)

| Variable | Default | Descripción |
|---|---|---|
| `POSTGRES_USER` | `postgres` | Superuser |
| `POSTGRES_PASSWORD` | `postgres` | Password del superuser |
| `POSTGRES_DB` | `postgres` | Base de datos por defecto |
| `REPLICATION_USER` | `replicator` | Usuario de replicación |
| `REPLICATION_PASSWORD` | `repl123` | Password del replicador |

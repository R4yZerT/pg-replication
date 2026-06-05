# PostgreSQL Streaming Replication Lab

Primary → Standby streaming replication con Docker Compose.
Basado en [Marcel Dempers' guide](https://github.com/marcel-dempers/docker-development-youtube-series/tree/master/storage/databases/postgresql/3-replication)
y [este video](https://www.youtube.com/watch?v=FC2JMBYDcJE).

---

## Arquitectura

```
┌─ MÁQUINA A (primaria) ─────────────┐    ┌─ MÁQUINA B (réplica) ────────────┐
│                                     │    │                                   │
│  ┌──────────────┐                   │    │  ┌──────────────┐                 │
│  │  pg-primary  │◀─ psql escribe ── │    │  │  pg-replica  │◀─ psql lee ────│
│  │  (read-write)│                   │    │  │  (read-only) │                 │
│  │  puerto 5432 │─── WAL stream ────│───▶│  │  puerto 5433 │                 │
│  └──────────────┘   TCP 5432       │    │  └──────────────┘                 │
│                                     │    │                                   │
│  IP: 192.168.x.x                    │    │  IP: 192.168.y.y                  │
└─────────────────────────────────────┘    └───────────────────────────────────┘
```

---

## Prerequisitos

- Docker Desktop 4.15+ (con Compose V2)
- Apple Silicon (M1/M2/M3) o Intel — imagen `postgres:16` (multi-arch)
- Tu compañero solo necesita un cliente PostgreSQL (`psql`, DBeaver, etc.)

---

## Comandos esenciales

### Opción A: Todo en una máquina (desarrollo local)

```bash
cd /Users/yeipezz/Documents/pg-replication
docker compose up -d --build
```

Esto levanta:
- **pg-primary** (lectura/escritura, puerto `5432`)
- **pg-replica** (solo lectura, puerto `5433`)

### Opción B: 2 máquinas separadas (laboratorio)

#### Máquina A (primaria)
```bash
cd /Users/yeipezz/Documents/pg-replication
docker compose -f docker-compose.primary.yml up -d
```

#### Máquina B (réplica)
```bash
cd /Users/yeipezz/Documents/pg-replication
PRIMARY_HOST=<IP-de-MAQUINA-A> docker compose -f docker-compose.replica.yml up -d --build
```

Ejemplo:
```bash
PRIMARY_HOST=192.168.20.72 docker compose -f docker-compose.replica.yml up -d --build
```

> **Windows:** usa `set` en CMD o `$env:` en PowerShell:
> ```cmd
> REM CMD
> set PRIMARY_HOST=192.168.20.72
> docker compose -f docker-compose.replica.yml up -d --build
> ```
> ```powershell
> # PowerShell
> $env:PRIMARY_HOST="192.168.20.72"; docker compose -f docker-compose.replica.yml up -d --build
> ```

> **⚠️ Atención sobre los comandos siguientes:**
> Los comandos de verificación usan `docker compose exec primary/replica`, que funcionan con `docker-compose.yml` (Opción A). En **Opción B**:
> - **Máquina A (primaria):** usa `docker compose -f docker-compose.primary.yml exec primary ...`
> - **Máquina B (réplica):** el servicio se llama `replica`, no `primary`. Para consultar la primaria desde la Máquina B, usa `psql -h <IP-DE-MAQUINA-A> -U postgres -d postgres` directamente; para la réplica local, usa `docker compose -f docker-compose.replica.yml exec replica psql ...`

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

## Conexiones entre máquinas

### Máquina A: obtener IP local

```bash
ipconfig getifaddr en0
# Ejemplo: 192.168.20.72
```

```cmd
REM Windows (CMD)
ipconfig
```

### Máquina B: conectar a la primaria

```bash
# psql a la primaria (escribir datos)
psql -h 192.168.20.72 -p 5432 -U postgres -d postgres

# psql a la réplica local (leer datos)
psql -h localhost -p 5433 -U postgres -d postgres

# Cadena de conexión universal a la primaria
postgresql://postgres:postgres@192.168.20.72:5432/postgres
```

**Credenciales por defecto:**

| Variable | Valor |
|---|---|
| Usuario | `postgres` |
| Password | `postgres` |
| Base de datos | `postgres` |
| Puerto primary (Máq. A) | `5432` |
| Puerto replica (Máq. B) | `5433` |

> Si no conecta, desactivar temporalmente el firewall:
> macOS → **Preferencias del Sistema → Red → Firewall → Apagar**
> (O agregar Docker a la lista de permitidos)

### ¿Qué hace cada quién?

- **Máquina A (primaria, puerto 5432):** lectura y escritura. Cualquier INSERT/UPDATE/DELETE se replica a la Máquina B.
- **Máquina B (réplica, puerto 5433):** solo lectura. Ve los mismos datos que la primaria. Rechaza escrituras.
- **Ambos** pueden conectarse a la primaria (5432) para escribir.

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
├── docker-compose.yml                 # Opción A: primary + replica (1 máquina)
├── docker-compose.primary.yml         # Opción B: solo primary (Máquina A)
├── docker-compose.replica.yml         # Opción B: solo replica (Máquina B)
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
    └── init-replica.sh               # pg_basebackup al arrancar (usa $PRIMARY_HOST)
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

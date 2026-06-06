# PostgreSQL Streaming Replication + Biblioteca Lab

Replicación primaria → standby con Docker Compose, más una base de datos **biblioteca** precargada con libros clásicos, filosofía y literatura universal.

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

- **Máquina A (primaria):** macOS con Docker Desktop 4.15+
- **Máquina B (réplica):** Windows con Docker Desktop
- Cliente PostgreSQL (`psql`) instalado en ambas máquinas
- Ambas máquinas en la **misma red local**

---

## Paso a paso

### Opción A: Todo en una máquina (desarrollo local)

```bash
cd /Users/yeipezz/Documents/pg-replication
docker compose up -d --build
```

Esto levanta:
- **pg-primary** — lectura/escritura, puerto `5432`
- **pg-replica** — solo lectura, puerto `5433`

Ambos servicios arrancan con la base de datos **biblioteca** (schema con libros, socios, préstamos y recibos).

---

### Opción B: 2 máquinas separadas (laboratorio)

#### Paso 1: Máquina A (primaria — macOS)

```bash
cd /Users/yeipezz/Documents/pg-replication
docker compose -f docker-compose.primary.yml up -d
```

Obtener la IP local para compartir con la Máquina B:

```bash
ipconfig getifaddr en0
# Ejemplo: 192.168.20.72
```

#### Paso 2: Máquina B (réplica — Windows)

Elegir según la terminal:

**CMD:**
```cmd
cd C:\ruta\pg-replication
set PRIMARY_HOST=192.168.20.72
docker compose -f docker-compose.replica.yml down -v
docker compose -f docker-compose.replica.yml up -d --build
```

**PowerShell:**
```powershell
cd C:\ruta\pg-replication
$env:PRIMARY_HOST="192.168.20.72"
docker compose -f docker-compose.replica.yml down -v
docker compose -f docker-compose.replica.yml up -d --build
```

> Reemplazar `192.168.20.72` por la IP real de la Máquina A.

#### Paso 3: Verificar que la réplica funciona

**En la Máquina A (macOS):**

```bash
# Ver WAL sender activo (state = streaming)
docker compose exec primary psql -U postgres -c \
  "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
```

**En la Máquina B (Windows):**

```cmd
REM Verificar que la réplica está en modo recovery
docker compose -f docker-compose.replica.yml exec replica psql -U postgres -c "SELECT pg_is_in_recovery();"

REM Debe mostrar: t
```

---

### Consultar la base de datos biblioteca

La base de datos incluye un schema `biblioteca` con todas las tablas. PostgreSQL no lo busca por defecto, así que hay que indicarlo en las queries:

**Forma larga (siempre funciona):**

```sql
SELECT * FROM biblioteca.libros;
SELECT * FROM biblioteca.socios;
SELECT * FROM biblioteca.prestamos;
SELECT * FROM biblioteca.recibos;
```

**Forma corta (después de fijar el schema por defecto):**

```sql
SET search_path TO biblioteca;
SELECT * FROM libros;
```

**En macOS (Opción A):**

```bash
# Listar libros
docker compose exec primary psql -U postgres -c "SELECT * FROM biblioteca.libros;"

# Leer desde la réplica (Opción A)
docker compose exec replica psql -U postgres -c "SELECT * FROM biblioteca.libros;"
```

**En Windows (Opción B — Máquina B):**

```cmd
REM Desde el contenedor réplica
docker compose -f docker-compose.replica.yml exec replica psql -U postgres -c "SELECT * FROM biblioteca.libros;"

REM O conectando directo a la primaria (host a host)
psql -h 192.168.20.72 -p 5432 -U postgres -d postgres -c "SELECT * FROM biblioteca.libros;"
```

---

### Ejemplos de consultas para la biblioteca

```sql
-- Todos los libros de filosofía
SELECT titulo, autor FROM biblioteca.libros l
JOIN biblioteca.categorias c ON c.id = l.categoria_id
WHERE c.nombre = 'Filosofía';

-- Libros disponibles (con stock > 0)
SELECT titulo, cantidad_disponible FROM biblioteca.libros
WHERE cantidad_disponible > 0;

-- Registrar un socio
INSERT INTO biblioteca.socios (cedula, nombre, telefono, email)
VALUES ('12345678', 'Juan Pérez', '555-1234', 'juan@email.com');

-- Prestar un libro (prestamo + descontar stock)
BEGIN;
INSERT INTO biblioteca.prestamos (socio_id, fecha_devolucion_esperada)
VALUES (1, CURRENT_DATE + 7);
INSERT INTO biblioteca.prestamo_libros (prestamo_id, libro_id)
VALUES (1, 1);
UPDATE biblioteca.libros SET cantidad_disponible = cantidad_disponible - 1 WHERE id = 1;
INSERT INTO biblioteca.recibos (prestamo_id, socio_id, tipo_recibo, monto, descripcion)
VALUES (1, 1, 'prestamo', 0, 'Préstamo de Don Quijote');
COMMIT;

-- Devolver un libro
BEGIN;
UPDATE biblioteca.prestamos SET estado = 'devuelto', fecha_devolucion_real = CURRENT_DATE
WHERE id = 1;
UPDATE biblioteca.libros SET cantidad_disponible = cantidad_disponible + 1
WHERE id = (SELECT libro_id FROM biblioteca.prestamo_libros WHERE prestamo_id = 1);
INSERT INTO biblioteca.recibos (prestamo_id, socio_id, tipo_recibo, monto, descripcion)
VALUES (1, 1, 'devolucion', 0, 'Devolución de Don Quijote');
COMMIT;

-- Ver préstamos activos
SELECT s.nombre, l.titulo, p.fecha_prestamo, p.fecha_devolucion_esperada
FROM biblioteca.prestamos p
JOIN biblioteca.socios s ON s.id = p.socio_id
JOIN biblioteca.prestamo_libros pl ON pl.prestamo_id = p.id
JOIN biblioteca.libros l ON l.id = pl.libro_id
WHERE p.estado = 'activo';

-- Historial de recibos de un socio
SELECT * FROM biblioteca.recibos WHERE socio_id = 1;
```

---

### Libros precargados (35 títulos)

La base se inicializa con libros en 4 categorías:

| Categoría | Ejemplos |
|---|---|
| Clásico Universal | Don Quijote, Cien Años de Soledad, 1984, Crimen y Castigo, La Odisea |
| Filosofía | La República, Ética a Nicómaco, Así Habló Zaratustra, El Príncipe |
| Literatura Contemporánea | El Nombre de la Rosa, La Sombra del Viento, El Alquimista |
| Poesía | La Divina Comedia, Las Flores del Mal |

---

### Conexiones entre máquinas

**Credenciales por defecto:**

| Variable | Valor |
|---|---|
| Usuario | `postgres` |
| Password | `postgres` |
| Base de datos | `postgres` |
| Puerto primary (Máq. A) | `5432` |
| Puerto replica (Máq. B) | `5433` |

**Cadena de conexión universal a la primaria:**

```
postgresql://postgres:postgres@192.168.20.72:5432/postgres
```

> Si no conecta desde Windows, desactivar temporalmente el firewall en macOS:
> **Preferencias del Sistema → Red → Firewall → Apagar**

---

### Detener y limpiar todo

**Opción A (una máquina):**

```bash
docker compose down -v
```

**Opción B:**

```cmd
REM Máquina A (macOS)
docker compose -f docker-compose.primary.yml down -v

REM Máquina B (Windows)
docker compose -f docker-compose.replica.yml down -v
```

`-v` elimina los volúmenes con datos. Si querés mantenerlos, omití `-v`.

---

### Medir lag de replicación (opcional)

```bash
# Lag en tiempo desde primary
docker compose exec primary psql -U postgres -c \
  "SELECT write_lag, flush_lag, replay_lag FROM pg_stat_replication;"

# Lag en bytes desde replica
docker compose exec replica psql -U postgres -c \
  "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(),
          pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn() AS lag_bytes;"
```

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
| `-R` | Crea `standby.signal` y escribe `primary_conninfo` en `postgresql.auto.conf` |
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
docker compose exec replica psql -U postgres -c "INSERT INTO biblioteca.libros (titulo, autor, categoria_id) VALUES ('Nuevo libro', 'Autor', 1);"

# 4. Para restaurar el setup original, limpiar y rebuild
docker compose down -v
docker compose up -d --build
```

---

## Troubleshooting

### La réplica en Windows no encuentra las tablas

La réplica se clonó antes de que existieran los scripts de la biblioteca. Forzar un clonado fresco:

```cmd
set PRIMARY_HOST=<IP-DE-MAQUINA-A>
docker compose -f docker-compose.replica.yml down -v
docker compose -f docker-compose.replica.yml up -d --build
```

### "relation 'libros' does not exist"

La tabla está en el schema `biblioteca`. Usar:

```sql
SELECT * FROM biblioteca.libros;
```

O fijar el schema por defecto:

```sql
SET search_path TO biblioteca;
SELECT * FROM libros;
```

### Error conectando desde Windows a la primaria

1. Verificar conectividad:

```cmd
curl -v telnet://<IP-MAQUINA-A>:5432
```

2. Si no conecta, desactivar firewall en macOS:
   **Preferencias del Sistema → Red → Firewall → Apagar**

3. Verificar que Docker está corriendo en la Máquina A:

```bash
docker compose ps
```

### La réplica no arranca (pg_basebackup falla)

El script `init-replica.sh` reintenta automáticamente. Si falla siempre, verificar:

- Que la Máquina A tenga el puerto 5432 accesible
- Que el usuario `replicator` exista en la primaria
- Que `PRIMARY_HOST` tenga la IP correcta

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
│       ├── 01-setup-replication.sql   # CREATE ROLE replicator + slot
│       ├── 02-schema.sql              # Schema biblioteca (tablas)
│       └── 03-seed-books.sql          # 35 libros precargados
└── replica/
    ├── Dockerfile                     # postgres:16 + entrypoint personalizado
    ├── config/
    │   ├── postgresql.conf            # hot_standby=on
    │   ├── pg_hba.conf                # solo trust localhost + scram-sha-256
    │   └── pg_ident.conf              # mapa de usuarios (vacio por defecto)
    └── init-replica.sh                # pg_basebackup al arrancar (usa $PRIMARY_HOST)
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
| `PRIMARY_HOST` | `pg-primary` | Host de la primaria (solo réplica) |

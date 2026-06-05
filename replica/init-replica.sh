#!/bin/bash
set -e

if [ ! -f "$PGDATA/PG_VERSION" ]; then
  echo "Replica data directory is empty. Initializing from primary..."
  PRIMARY_HOST=${PRIMARY_HOST:-pg-primary}
  until PGPASSWORD=$REPLICATION_PASSWORD pg_basebackup \
    -h $PRIMARY_HOST \
    -p 5432 \
    -U $REPLICATION_USER \
    -D "$PGDATA" \
    -Fp \
    -Xs \
    -R \
    -S replication_slot_1 \
    -P \
    -v
  do
    echo "Waiting for primary to become ready..."
    sleep 2
  done

  chown -R postgres:postgres "$PGDATA"
  echo "Replica initialization complete."
fi

exec docker-entrypoint.sh "$@"

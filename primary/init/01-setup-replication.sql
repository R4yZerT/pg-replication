CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl123';

SELECT pg_create_physical_replication_slot('replication_slot_1');

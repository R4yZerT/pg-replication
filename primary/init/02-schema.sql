CREATE SCHEMA IF NOT EXISTS biblioteca;

SET search_path TO biblioteca;

CREATE TABLE IF NOT EXISTS categorias (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT
);

CREATE TABLE IF NOT EXISTS libros (
    id SERIAL PRIMARY KEY,
    titulo VARCHAR(255) NOT NULL,
    autor VARCHAR(255) NOT NULL,
    categoria_id INTEGER REFERENCES categorias(id),
    editorial VARCHAR(150),
    anio_publicacion INTEGER,
    isbn VARCHAR(20) UNIQUE,
    cantidad_disponible INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS socios (
    id SERIAL PRIMARY KEY,
    cedula VARCHAR(20) NOT NULL UNIQUE,
    nombre VARCHAR(255) NOT NULL,
    telefono VARCHAR(20),
    email VARCHAR(150),
    direccion TEXT,
    fecha_registro TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS prestamos (
    id SERIAL PRIMARY KEY,
    socio_id INTEGER NOT NULL REFERENCES socios(id),
    fecha_prestamo DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_devolucion_esperada DATE NOT NULL,
    fecha_devolucion_real DATE,
    estado VARCHAR(20) NOT NULL DEFAULT 'activo'
        CHECK (estado IN ('activo', 'devuelto', 'vencido')),
    observaciones TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS prestamo_libros (
    id SERIAL PRIMARY KEY,
    prestamo_id INTEGER NOT NULL REFERENCES prestamos(id) ON DELETE CASCADE,
    libro_id INTEGER NOT NULL REFERENCES libros(id)
);

CREATE TABLE IF NOT EXISTS recibos (
    id SERIAL PRIMARY KEY,
    prestamo_id INTEGER NOT NULL REFERENCES prestamos(id),
    socio_id INTEGER NOT NULL REFERENCES socios(id),
    tipo_recibo VARCHAR(30) NOT NULL
        CHECK (tipo_recibo IN ('prestamo', 'devolucion', 'multa', 'renovacion')),
    monto NUMERIC(10, 2) NOT NULL DEFAULT 0,
    fecha_emision TIMESTAMPTZ NOT NULL DEFAULT now(),
    descripcion TEXT
);

CREATE INDEX IF NOT EXISTS idx_prestamos_socio ON prestamos(socio_id);
CREATE INDEX IF NOT EXISTS idx_prestamos_estado ON prestamos(estado);
CREATE INDEX IF NOT EXISTS idx_prestamo_libros_prestamo ON prestamo_libros(prestamo_id);
CREATE INDEX IF NOT EXISTS idx_prestamo_libros_libro ON prestamo_libros(libro_id);
CREATE INDEX IF NOT EXISTS idx_recibos_prestamo ON recibos(prestamo_id);
CREATE INDEX IF NOT EXISTS idx_libros_categoria ON libros(categoria_id);

SET search_path TO biblioteca;

INSERT INTO categorias (nombre, descripcion) VALUES
    ('Clásico Universal', 'Obras literarias universales consagradas por la crítica'),
    ('Filosofía', 'Obras filosóficas de todas las épocas'),
    ('Literatura Contemporánea', 'Obras modernas y contemporáneas'),
    ('Poesía', 'Obras poéticas universales')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO libros (titulo, autor, categoria_id, editorial, anio_publicacion, isbn, cantidad_disponible) VALUES
    -- Clásicos Universales
    ('Don Quijote de la Mancha', 'Miguel de Cervantes', 1, 'Real Academia Española', 1605, '978-84-670-2420-3', 3),
    ('Cien Años de Soledad', 'Gabriel García Márquez', 1, 'Editorial Sudamericana', 1967, '978-84-376-0494-7', 2),
    ('Orgullo y Prejuicio', 'Jane Austen', 1, 'Penguin Classics', 1813, '978-0-14-143951-8', 2),
    ('Crimen y Castigo', 'Fiódor Dostoyevski', 1, 'Alianza Editorial', 1866, '978-84-206-6930-8', 2),
    ('1984', 'George Orwell', 1, 'Secker & Warburg', 1949, '978-84-9759-743-8', 3),
    ('Matar a un Ruiseñor', 'Harper Lee', 1, 'J.B. Lippincott & Co.', 1960, '978-84-663-2997-3', 2),
    ('Ulises', 'James Joyce', 1, 'Shakespeare and Company', 1922, '978-84-376-0949-2', 1),
    ('La Ilíada', 'Homero', 1, 'Editorial Gredos', -750, '978-84-249-3530-2', 2),
    ('La Odisea', 'Homero', 1, 'Editorial Gredos', -720, '978-84-249-3531-9', 2),
    ('Guerra y Paz', 'León Tolstói', 1, 'Alianza Editorial', 1869, '978-84-206-7327-5', 1),
    ('Madame Bovary', 'Gustave Flaubert', 1, 'Revue de Paris', 1856, '978-84-376-0946-1', 2),
    ('El Gran Gatsby', 'F. Scott Fitzgerald', 1, 'Charles Scribner''s Sons', 1925, '978-84-376-0945-4', 2),
    ('En Busca del Tiempo Perdido', 'Marcel Proust', 1, 'Grasset', 1913, '978-84-376-0948-5', 1),
    ('Drácula', 'Bram Stoker', 1, 'Archibald Constable and Company', 1897, '978-84-376-0947-8', 2),
    ('Frankenstein', 'Mary Shelley', 1, 'Lackington, Hughes, Harding, Mavor & Jones', 1818, '978-84-376-0944-7', 2),

    -- Filosofía
    ('La República', 'Platón', 2, 'Editorial Gredos', -380, '978-84-249-3536-4', 3),
    ('Ética a Nicómaco', 'Aristóteles', 2, 'Editorial Gredos', -350, '978-84-249-3537-1', 2),
    ('El Mundo de Sofía', 'Jostein Gaarder', 2, 'Farrar, Straus and Giroux', 1991, '978-84-9759-744-5', 2),
    ('Así Habló Zaratustra', 'Friedrich Nietzsche', 2, 'Ernst Schmeitzner', 1883, '978-84-376-0938-6', 2),
    ('El Ser y el Tiempo', 'Martin Heidegger', 2, 'Max Niemeyer Verlag', 1927, '978-84-376-0940-9', 1),
    ('El Contrato Social', 'Jean-Jacques Rousseau', 2, 'Marc-Michel Rey', 1762, '978-84-376-0939-3', 2),
    ('Crítica de la Razón Pura', 'Immanuel Kant', 2, 'Johann Friedrich Hartknoch', 1781, '978-84-376-0941-6', 1),
    ('El Príncipe', 'Nicolás Maquiavelo', 2, 'Antonio Blado d''Asola', 1532, '978-84-376-0942-3', 2),
    ('El Mundo como Voluntad y Representación', 'Arthur Schopenhauer', 2, 'F.A. Brockhaus', 1819, '978-84-376-0943-0', 1),
    ('Meditaciones Metafísicas', 'René Descartes', 2, 'Michel Soly', 1641, '978-84-376-0937-9', 2),
    ('El Existencialismo es un Humanismo', 'Jean-Paul Sartre', 2, 'Nagel', 1946, '978-84-376-0936-2', 2),
    ('La Insoportable Levedad del Ser', 'Milan Kundera', 2, 'Harper & Row', 1984, '978-84-376-0935-5', 2),
    ('El Arte de la Guerra', 'Sun Tzu', 2, 'Desconocida', -500, '978-84-376-0934-8', 3),
    ('Meditaciones', 'Marco Aurelio', 2, 'Desconocida', 180, '978-84-376-0933-1', 2),
    ('El Banquete', 'Platón', 2, 'Editorial Gredos', -385, '978-84-249-3538-8', 2),

    -- Literatura Contemporánea
    ('El Nombre de la Rosa', 'Umberto Eco', 3, 'Bompiani', 1980, '978-84-376-0932-4', 2),
    ('La Sombra del Viento', 'Carlos Ruiz Zafón', 3, 'Planeta', 2001, '978-84-376-0931-7', 2),
    ('El Alquimista', 'Paulo Coelho', 3, 'HarperCollins', 1988, '978-84-376-0930-0', 3),

    -- Poesía
    ('La Divina Comedia', 'Dante Alighieri', 4, 'Desconocida', 1320, '978-84-376-0929-4', 2),
    ('Las Flores del Mal', 'Charles Baudelaire', 4, 'Auguste Poulet-Malassis', 1857, '978-84-376-0928-7', 2)
ON CONFLICT (isbn) DO NOTHING;

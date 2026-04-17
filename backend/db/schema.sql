CREATE TABLE IF NOT EXISTS exercises (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    muscle_group TEXT NOT NULL,
    difficulty TEXT NOT NULL,
    equipment TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO exercises (id, name, muscle_group, difficulty, equipment)
VALUES
    ('ex-001', 'Sentadilla goblet', 'piernas', 'principiante', 'mancuerna'),
    ('ex-002', 'Press banca con mancuernas', 'pecho', 'intermedio', 'mancuernas'),
    ('ex-003', 'Remo con polea baja', 'espalda', 'principiante', 'polea')
ON CONFLICT (id) DO NOTHING;

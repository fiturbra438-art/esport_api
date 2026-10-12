DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM tournaments
        GROUP BY LOWER(BTRIM(name))
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Tidak dapat menambahkan batas nama turnamen: terdapat nama duplikat. Periksa tabel tournaments terlebih dahulu.';
    END IF;
END;
$$;

CREATE UNIQUE INDEX uq_tournaments_name_normalized
    ON tournaments (LOWER(BTRIM(name)));

-- The backend hashes passwords before calling this procedure. Do not return
-- the stored hash in the procedure result or registration response.
DROP PROCEDURE IF EXISTS pr_register_user(TEXT, TEXT, INTEGER);

CREATE PROCEDURE pr_register_user(
    IN p_username TEXT,
    IN p_password TEXT,
    IN p_mmr_point INTEGER,
    OUT id INTEGER,
    OUT username VARCHAR,
    OUT mmr_point INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    SELECT
        registered_user.id,
        registered_user.username,
        registered_user.mmr_point
    INTO id, username, mmr_point
    FROM fn_register_user(p_username, p_password, p_mmr_point) AS registered_user;
END;
$$;

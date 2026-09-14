-- Function create dipanggil langsung dari handler dengan SELECT.
-- Procedure command tetap dipakai untuk operasi yang membutuhkan CALL.
DROP PROCEDURE IF EXISTS pr_create_team(TEXT, INTEGER);
DROP PROCEDURE IF EXISTS pr_create_tournament(TEXT);
DROP PROCEDURE IF EXISTS pr_create_match(INTEGER, INTEGER, INTEGER, INTEGER);

# Database migrations

SQLx runs these files in version order. Keep migration files in this directory
and do not move or renumber migrations that may already have been applied.
Unlike `database/`, this directory is a chronological change history, so it
should not be split into feature subdirectories.

## Migration history

| Version | File | Purpose |
| --- | --- | --- |
| 000 | `000_create_initial_tables.sql` | Create the core tables and indexes. |
| 001 | `001_add_match_schedule_and_teams.sql` | Add match scheduling and team-related schema. |
| 002 | `002_add_procedures_and_views.sql` | Add initial business routines and API views. |
| 003 | `003_remove_redundant_create_procedures.sql` | Remove create procedures that were no longer used. |
| 004 | `004_add_triggers.sql` | Add captain-membership and tournament-registration triggers. |
| 005 | `005_create_match_transaction_procedure.sql` | Add the match creation procedure. |
| 006 | `006_move_create_transactions_to_sql.sql` | Move team and tournament creation logic into SQL functions. |
| 007 | `007_add_create_transaction_procedures.sql` | Add procedures for create operations. |
| 008 | `008_add_procedure_indexes.sql` | Add indexes used by procedures and foreign-key lookups. |
| 009 | `009_lookup_ids_by_names.sql` | Add name-based lookups and procedure signatures. |
| 010 | `010_wrap_business_functions_with_procedures.sql` | Keep business logic in functions and expose it through procedures. |

## Current database definitions

The `database/` directory contains the organized, current SQL definitions:

- `database.sql` — tables and indexes.
- `function.sql` — business and lookup functions.
- `procedure.sql` — procedures called by the API.
- `trigger.sql` — trigger functions and triggers.
- `view.sql` — API read views.
- `dcl.sql` — database roles and privileges.

Edit an existing migration only before it has been applied/shared. For schema
changes after that, add a new, higher-numbered migration. Keep the current
definitions in `database/` aligned with the final migrated schema.

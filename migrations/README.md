# Database migrations

SQLx runs these files in version order. This compact baseline is intended for a
fresh or deliberately reset development database. Future changes should use
new, higher-numbered migrations; do not edit a baseline after applying it.

## Migration history

| Version | File | Purpose |
| --- | --- | --- |
| 1 | `0001_schema.sql` | Create tables, indexes, and constraints. |
| 2 | `0002_functions.sql` | Define database functions used by SQL procedures. |
| 3 | `0003_triggers.sql` | Define trigger functions and triggers. |
| 4 | `0004_views.sql` | Define API read views, team directory, and tournament entrants. |
| 5 | `0005_procedures.sql` | Define operations, authorization, profile/team lifecycle, account deletion, and match results. |
| 6 | `0006_procedure_commits.sql` | Replace procedure definitions with explicit commits for mutations. |

## Current database definitions

The `database/` directory contains the organized, current SQL definitions:

- `database.sql` — tables and indexes.
- `function.sql` — business and lookup functions.
- `procedure.sql` — procedures called by the API.
- `trigger.sql` — trigger functions and triggers.
- `view.sql` — API read views.
- `dcl.sql` — database roles and privileges.

The files are separated by database object type and dependency order.
Keep the current definitions in `database/` aligned with these migrations and
future changes. Mutating procedures issue `COMMIT` at the end and must be
invoked directly, outside an explicit transaction block. If a procedure raises
an error before its `COMMIT`, PostgreSQL aborts the `CALL` and rolls back its
changes.

This compacted baseline must be applied to a fresh or deliberately reset
development database. Databases that already recorded the pre-compaction
versions 000–016 or legacy versions 6–7 from the older migration sequence need
their schema and SQLx migration history reset before using this layout. This
repository does not reset databases automatically. Do not use this baseline on
a database whose data must be preserved.

`POST /api/tournaments` requires a positive `max_teams` value. Newly created
tournaments always have a finite limit.
Only users with the `admin` role can create or delete tournaments and manage
matches. Team membership and captain operations are restricted to the
authenticated user or team captain as appropriate. Stored procedures enforce
these rules; each mutating procedure commits its own successful operation.
Promote a trusted account manually after registration; see the root `README.md`.

Every new mutating endpoint invokes a stored procedure directly. Account
deletion requires one valid replacement captain for every team the account
captains. Deleting a team cascades to its tournament registrations and matches.

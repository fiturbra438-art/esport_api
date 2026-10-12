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
| 5 | `0005_procedures.sql` | Define transactional operations, authorization, profile/team lifecycle, account deletion, and match results. |

## Current database definitions

The `database/` directory contains the organized, current SQL definitions:

- `database.sql` — tables and indexes.
- `function.sql` — business and lookup functions.
- `procedure.sql` — procedures called by the API.
- `trigger.sql` — trigger functions and triggers.
- `view.sql` — API read views.
- `dcl.sql` — database roles and privileges.

The five files are separated by database object type and dependency order.
Keep the current definitions in `database/` aligned with these migrations and
future changes.

This compacted baseline must be applied to a fresh or deliberately reset
development database. Databases that already recorded old versions 000–016 or
the subsequently added versions 6–7 need their schema and SQLx migration
history reset before using this layout. This repository does not reset
databases automatically. Do not use this baseline on a database whose data
must be preserved.

`POST /api/tournaments` requires a positive `max_teams` value. Newly created
tournaments always have a finite limit.
Only users with the `admin` role can create or delete tournaments and manage
matches. Team membership and captain operations are restricted to the
authenticated user or team captain as appropriate. Stored procedures enforce
these rules; the API calls them within transactions.
Promote a trusted account manually after registration; see the root `README.md`.

Every new mutating endpoint invokes a stored procedure inside a SQLx
transaction. Account deletion requires one valid replacement captain for every
team the account captains. Deleting a team cascades to its tournament
registrations and matches.

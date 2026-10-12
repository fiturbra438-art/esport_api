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
| 4 | `0004_views.sql` | Define API read views. |
| 5 | `0005_procedures.sql` | Define transactional operations and authorization checks. |

## Current database definitions

The `database/` directory contains the organized, current SQL definitions:

- `database.sql` — tables and indexes.
- `function.sql` — business and lookup functions.
- `procedure.sql` — procedures called by the API.
- `trigger.sql` — trigger functions and triggers.
- `view.sql` — API read views.
- `dcl.sql` — database roles and privileges.

The five files are separated by database object type and dependency order.
Keep the current definitions in `database/` aligned with the baseline and
future migrations.

Before switching a database that has recorded the old migration versions
000–016, reset its development schema and data so SQLx can apply this new
baseline. This repository does not reset databases automatically. Do not use
this baseline on a database whose data must be preserved.

`POST /api/tournaments` requires a positive `max_teams` value. Newly created
tournaments always have a finite limit.
Only users with the `admin` role can create or delete tournaments and manage
matches. Team membership and captain operations are restricted to the
authenticated user or team captain as appropriate. Stored procedures enforce
these rules; the API calls them within transactions.
Promote a trusted account manually after registration; see the root `README.md`.

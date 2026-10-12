# Postman API tests

## Which collection should I use?

- **Esport API - Manual (VS Code)** is the cloud collection for sending
  individual requests. Use it when you only need to try selected endpoints.
- `esport-api.postman_collection.json` is the local sequential integration
  collection. Import it into Postman VS Code and run it when you want to test
  the full API flow, including cleanup of generated test data.

Do not run the cloud/manual collection as one sequence; its requests require
different setup and identities.

## Initial setup

1. Start PostgreSQL and the API using the local setup in the root `README.md`.
2. In Postman VS Code, use **Import** to import
   `postman/esport-api.postman_collection.json`. If VS Code shows a file picker,
   select that JSON file directly.
3. Set `baseUrl` to `http://127.0.0.1:8080` or the address where the API runs.
4. Set `adminUsername` and `adminPassword` in the active environment to an
   existing admin account. New registrations have the `user` role; promote an
   account to `admin` as described in the root `README.md` before running this
   flow. Mark `adminPassword` as a secret. The collection does not contain real
   admin credentials.
5. Run the full **Esport API - Local Integration Tests** collection in order
   using Postman's Collection Runner, then inspect **Test Results**.

The collection makes and saves distinct JWTs for the captain, member, third
user, and admin, so switching logins does not confuse the authenticated actor.
Its generated demo password is only for disposable local test accounts.

## What the integration flow tests

The collection checks health, registration and login, profile lookup by
username and username changes, team creation/profile lookup by name/directory,
joining and removing
members, captain transfer, leaving and deleting teams, tournament
creation/listing/registration/entrant listing/deletion, match
creation/listing/scheduling/result recording by tournament and one competing
team name, and account deletion. It also
checks selected invalid-token, duplicate, non-admin, full-capacity, and missing
resource cases.

## Cleanup and database safety

On a successful full run, the collection removes its tournament, both teams,
and all three generated users. The sequence transfers captaincy where needed
before deleting an account or team. If a run stops partway through, inspect
**Test Results** and the saved `captainUsername`, `memberUsername`,
`thirdUsername`, `teamAlpha`, `teamBeta`, and `tournamentName` collection
variables before cleaning up any leftover test records.

The flow only calls the API; it does not reset the database or run SQL
migrations. Do not use it against production data.

The **Esport API - Seed Data (8 Teams, 40 Users)** collection recreates the
original fixed demo data: 40 named users and teams `RRQ`, `EVOS`, `ONIC`, `NAVI`,
`AE`, `TLID`, `BTR`, and `DEWA`, with five users in each team. The collection
logs in as each account before joining it to its team and verifies every roster
before setting `seedStatus` to `completed`. Because it uses fixed names, run it
only after clearing conflicting demo data, and do not send it a second time
unless those records have been removed. Inspect `seedStatus` and Test Results
after sending; an error identifies the first step that failed. This collection
is intended only for a local/test database, never production.

## Sending requests manually

For the cloud/manual collection, set the active environment variables used by
the request (for example `baseUrl`, usernames, team/tournament names, and
credentials), then select the matching environment before sending. Name-based
GET requests look up the corresponding IDs in the backend, so you can use a
username, team name, or tournament name instead of entering its database ID.
Match scheduling and results accept `tournament_name` plus either competing
`team_name`; when that team has multiple matches in the tournament, the API
returns HTTP 409 rather than guessing.
Store
passwords as secret environment values, not in a collection or shared request.
The specialized tests use separate `captainToken`, `memberToken`, and
`adminToken` variables to preserve the authenticated identity. Tournament and
match administration requires an admin account; team registration requires
the authenticated team captain. The **Join team** body only needs
`{"team_name":"{{teamName}}"}`; the API adds the authenticated account from
the Bearer token automatically.

# Postman API tests

## Which collection should I use?

- **Esport API - Manual (VS Code)** is the cloud collection for sending individual
  requests. Its main folders group requests by Auth & Users, Teams, Tournaments,
  and Matches. Request scripts show the expected status and validate responses.
- `esport-api.postman_collection.json` is the local sequential integration
  collection. It creates test users and teams, exercises the API in order, and
  deletes its test tournament at the end. Import it into Postman only when you
  want to run the full integration flow.

For manual work, do not run the whole cloud collection as a single sequence:
some requests are examples or negative tests and require specific setup. Run
only the request you need after its prerequisites.

## Initial setup

1. Start PostgreSQL and the API using the local setup in the root `README.md`.
2. In Postman VS Code, select the **Esport API - Manual (VS Code)** collection
   and the **Esport API - Local (VS Code)** environment. Set `baseUrl` to
   `http://127.0.0.1:8080` (or the address where the API is running).
3. Create or select an environment for credentials. Set the variables needed
   by the requests you plan to run. Mark password variables as **secret**:

   | Variable | Used for |
   | --- | --- |
   | `loginUsername`, `loginPassword` | General login request |
   | `adminUsername`, `adminPassword` | Admin-only tournament operations |
   | `captainUsername`, `captainPassword` | Captain-only registration tests |
   | `memberUsername`, `memberPassword` | Non-captain authorization test |
   | `secondCaptainUsername`, `secondCaptainPassword` | Second team in capacity test |
   | `teamName` | Exact team name for the registration and captain tests |
   | `firstTeamName`, `secondTeamName` | Exact names for the two capacity-test teams |

   Keep credentials in the active environment; do not save real passwords in
   the collection or share them.
4. To create or delete tournaments, register an account and promote it to
   `admin` as documented in the root `README.md`. Registration itself assigns
   the `user` role.
5. Select the environment before sending requests. The **Login** request saves
   the access token to the collection variable `token` and the user's role to
   `loginRole`; protected requests use that token. The specialized captain and
   admin test logins save separate tokens (`captainToken`, `memberToken`, and
   `adminToken`) so switching test identities does not overwrite each other.

## Running requests manually

Use the folders as a guide:

- **Auth & Users**: check API health, register an account, log in, and retrieve
  a user profile.
- **Teams**: create a team, view it, add/remove members, or transfer the
  captaincy. Team names in request bodies must match the database.
- **Tournaments**: list tournaments; admins can create/delete them, while only
  the captain of a team can register that team. Tournament names and team names
  must match exactly.
- **Matches**: create a match between teams registered in the tournament, list
  its matches, and set a schedule.

Requests named `CAPTAIN TEST` and `Admin TEST` are an optional authorization
scenario. Set the account variables above and use a team whose captain and
regular member accounts are both available. Run the admin login and temporary
tournament creation before the captain's registration request, then run the
member request to verify HTTP 403. The test tournament is not automatically
deleted by this manual scenario; use the admin-only **Delete tournament**
request when finished. Before sending it, set the collection variable
`tournamentName` to the generated `captainTestTournament` value.

Requests prefixed `Capacity` and `Tournament - Reject duplicate name` are
optional negative tests. The current capacity helper requests are in the
**Teams** folder; use their `Capacity` names to identify them. Run the capacity
requests manually in this order:

1. Login as admin (CAPTAIN TEST 3), then **Capacity - Create one-slot
   tournament**.
2. Login as the first captain (CAPTAIN TEST 1), then **Capacity - Register
   first team (201)**. Use `firstTeamName`.
3. Send **Capacity - Login second captain**, then **Capacity - Reject
   registration when full (409)**. Use a different team in `secondTeamName`.
4. **Capacity - Reject max_teams=0 (400)** can be run while `adminToken` is
   available.
5. Finish with **Capacity - Delete test tournament** so test data is cleaned
   up.

A duplicate-name test must be sent after creating a tournament with the same
name. Duplicate registration and full capacity expect HTTP 409; invalid
`max_teams` expects HTTP 400.

## Running the local integration collection

1. Import `esport-api.postman_collection.json`.
2. Set `baseUrl` to the API address and set `adminUsername` and secret
   `adminPassword` in the active environment.
3. Run the full collection in order using the Collection Runner.
4. Review the **Test Results** tab.

The integration collection generates unique usernames and team/tournament
names. It creates two users and two teams that remain in the database because
the API has no user/team deletion endpoints. It creates a one-slot tournament,
tests successful, duplicate, and full-capacity registration, creates and
schedules a match, then deletes the temporary tournament. PostgreSQL cascades
that tournament deletion to its registrations and matches.

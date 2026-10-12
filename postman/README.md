# Postman API tests

## Run the collection

1. Start PostgreSQL and the API using the local setup in the root `README.md`.
2. Register and promote an admin account as documented in the root README.
   Set `adminUsername` and `adminPassword` in the active Postman environment;
   mark `adminPassword` as a secret variable.
3. Confirm the API responds at `http://127.0.0.1:8080/`.
4. In Postman, select **Import** and import `esport-api.postman_collection.json`.
5. Open the collection and use **Run** to run all requests in order.
6. Review the **Test Results** tab in the Collection Runner.

The collection uses `baseUrl` as a collection variable. Change it if the API is
running at a different address. Generated usernames and resource names include a
timestamp, so the collection can be run repeatedly.

Only `admin` accounts can create or delete tournaments. Tournament names are
unique ignoring letter case and surrounding spaces; duplicate names return
HTTP 409. The local integration collection tests this after creating a
tournament. Register the intended
admin account normally, promote it in pgAdmin using the SQL in the root
`README.md`, then log in with that account in Postman before sending the
tournament creation request. Registration always assigns the `user` role.

The tournament-creation request sets a one-team registration limit to verify
that the first team is accepted and another team's registration is rejected
when the tournament is full.

The **Esport API - Manual (VS Code)** collection also has a capacity workflow
made up of requests with the `Capacity test` prefix:

1. Create a one-slot tournament while logged in as an admin.
2. Replace `REPLACE_WITH_FIRST_TEAM_NAME` and register that captain's team.
3. Replace the username and password in the second-captain login request.
4. Replace `REPLACE_WITH_SECOND_TEAM_NAME` and confirm the registration returns
   HTTP 409 with `Kuota tim turnamen sudah penuh`.

The second team must be different from the first, and the logged-in user must
captain the team being registered. The test login updates the collection's
`token` variable, so log in again as the first captain before continuing with
other protected requests. An additional request checks that `max_teams: 0` is
rejected with HTTP 400.

## Quick tournament-registration workflow in Postman VS Code

Use the **Esport API - Pendaftaran Turnamen (VS Code)** collection from the
Postman workspace for a guided registration test. Select or create an
environment and set:

- `adminUsername` and secret `adminPassword` for an account with the `admin`
  role.
- `captainUsername` and secret `captainPassword` for the captain of the team
  being tested.
- `memberUsername` and secret `memberPassword` for a regular member of that
  same team.
- `teamName` to the exact name of that team.

Set these values in the active environment; passwords are not stored in the
collection. Set `baseUrl` there too if the API is not running at
`http://127.0.0.1:8080`. Select the environment and run the collection in order.
It creates a uniquely named tournament, tests successful and duplicate
registration plus non-captain rejection, checks the remaining capacity, then
deletes the temporary tournament. User and team records are not changed.

To manually test team registration in **Tournaments > Register team to
tournament**:

1. Make sure the tournament already exists and has an available slot. Set the
   collection's `tournamentName` variable to its exact name.
2. Send **Login** with the credentials of the captain of the team. The request
   saves the returned access token to the `token` collection variable.
3. In the registration request body, replace `Team Alpha` with the exact team
   name, then send the request. A successful registration returns HTTP 201.

Only that team's captain can register it (HTTP 403 otherwise). A team already
registered in the tournament or a full tournament returns HTTP 409. For a
second registration attempt, first ensure the first request succeeded; the
second attempt should return HTTP 409.

The tests cover API health, user registration/login/profile, password omission
from responses, rejection of protected mutations without a token and with an
invalid token, team
create/profile/join/duplicate join/captain transfer/member removal, tournament
create/list/register/duplicate-registration/capacity rejection/delete, match
create/list/scheduling, invalid schedule input, and a missing user profile.
Tournament capacity is set to one team in the test run, so registering a
different team's captain after the first registration must return HTTP 409.
A repeated tournament registration must also return HTTP 409; the failed
request is rolled back. The login test stores the JWT in the
collection's `token` variable; protected requests use it as a Bearer token.

The final request deletes the test tournament; PostgreSQL cascades this deletion
to its registrations and matches. The API has no team or user deletion
endpoints, so test users and teams remain in the database after each run.

## Run one request manually

Run requests in order. Later requests use IDs captured by earlier test scripts.
Running a request by itself before its setup requests will likely fail because
its required collection variables have not been set.

The request scripts use Postman's `pm.test` API to check status codes and JSON
shapes, and `pm.collectionVariables` to pass generated IDs between requests.
Keep requests in order so the login step can populate the token before protected
mutations run.

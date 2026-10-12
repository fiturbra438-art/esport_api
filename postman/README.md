# Postman API tests

## Run the collection

1. Start PostgreSQL and the API using the local setup in the root `README.md`.
2. Confirm the API responds at `http://127.0.0.1:8080/`.
3. In Postman, select **Import** and import `esport-api.postman_collection.json`.
4. Open the collection and use **Run** to run all requests in order.
5. Review the **Test Results** tab in the Collection Runner.

The collection uses `baseUrl` as a collection variable. Change it if the API is
running at a different address. Generated usernames and resource names include a
timestamp, so the collection can be run repeatedly.

The tournament-creation request sets a one-team registration limit to verify
that the first team is accepted and another team's registration is rejected
when the tournament is full.

The **Esport API - Manual (VS Code)** collection also has a capacity workflow
made up of requests with the `Capacity test` prefix (they are currently in the
**Teams** folder):

1. Create a one-slot tournament while logged in as a captain.
2. Replace `REPLACE_WITH_FIRST_TEAM_NAME` and register that captain's team.
3. Replace the username and password in the second-captain login request.
4. Replace `REPLACE_WITH_SECOND_TEAM_NAME` and confirm the registration returns
   HTTP 409 with `Kuota tim turnamen sudah penuh`.

The second team must be different from the first, and the logged-in user must
captain the team being registered. The test login updates the collection's
`token` variable, so log in again as the first captain before continuing with
other protected requests. An additional request checks that `max_teams: 0` is
rejected with HTTP 400.

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

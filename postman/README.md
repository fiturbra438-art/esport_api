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

The tests cover API health, user registration/login/profile, password omission
from responses, rejection of protected mutations without a token and with an
invalid token, team
create/profile/join/duplicate join/captain transfer/member removal, tournament
create/list/register/duplicate-registration/delete, match create/list/scheduling,
invalid schedule input, and a missing user profile. A repeated tournament
registration must return HTTP 409; the failed request is rolled back. The login
test stores the JWT in the
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

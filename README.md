# Esport API

REST API untuk mengelola player, tim, turnamen, dan jadwal pertandingan e-sport. API dibuat dengan Rust, Axum, SQLx, dan PostgreSQL.

## Fitur

- Registrasi dan profil player.
- Pembuatan tim, pengelolaan anggota, dan perpindahan kapten.
- Pembuatan turnamen dan pendaftaran tim.
- Pembuatan pertandingan serta pengaturan jadwal.
- Migrasi database otomatis saat aplikasi dijalankan.
- Pembuatan tim dan turnamen menggunakan stored procedure PostgreSQL dengan transaksi di sisi database.

## Persyaratan

- Rust stable 1.85 atau lebih baru.
- Docker dengan Docker Compose.
- SQLx CLI 0.7.4 untuk menjalankan migrasi secara manual.

## Menjalankan secara lokal

1. Jalankan PostgreSQL:

   ```powershell
   docker compose up -d db
   ```

2. Atur `DATABASE_URL` agar SQLx dapat memeriksa query saat compile. Sesuaikan username, password, dan nama database dengan PostgreSQL yang digunakan:

   ```powershell
   $env:DATABASE_URL = "postgres://postgres:fitur1206@localhost:5432/TOURNAMEN_ESPORT"
   ```

3. Pasang SQLx CLI jika belum tersedia, lalu jalankan migrasi sebelum build agar skema tersedia untuk pemeriksaan query SQLx:

   ```powershell
   cargo install sqlx-cli --version 0.7.4 --no-default-features --features postgres,rustls --locked
   sqlx migrate run
   ```

4. Samakan URL database hard-coded pada `src/main.rs` dengan nilai `DATABASE_URL` yang digunakan. Saat ini `docker-compose.yml` membuat database dengan user `admin`, sedangkan `src/main.rs` masih menggunakan user `postgres`.

5. Jalankan API:

   ```powershell
   cargo run
   ```

Server mendengarkan di `http://127.0.0.1:8080`. Migrasi juga dijalankan otomatis saat aplikasi mulai.

Jalankan pemeriksaan dan test dengan:

```powershell
cargo check
cargo test --locked
```

## Endpoint API

Semua body request menggunakan JSON.

| Method | Endpoint | Body |
| --- | --- | --- |
| `POST` | `/api/users` | `{"username":"player1","password":"secret","mmr_point":1000}` |
| `GET` | `/api/users/{id}` | - |
| `POST` | `/api/teams` | `{"name":"Team Alpha","captain_id":1}` |
| `GET` | `/api/teams/{id}` | - |
| `POST` | `/api/teams/join` | `{"team_id":1,"user_id":2}` |
| `DELETE` | `/api/teams/members` | `{"team_id":1,"user_id":2}` |
| `PUT` | `/api/teams/captain` | `{"team_id":1,"new_captain_id":2}` |
| `POST` | `/api/tournaments` | `{"name":"Summer Cup"}` |
| `GET` | `/api/tournaments` | - |
| `DELETE` | `/api/tournaments/{id}` | - |
| `POST` | `/api/tournaments/register` | `{"tournament_id":1,"team_id":1}` |
| `POST` | `/api/matches` | `{"tournament_id":1,"team1_id":1,"team2_id":2,"round_number":1}` |
| `GET` | `/api/tournaments/{id}/matches` | - |
| `PUT` | `/api/matches/{id}/schedule` | `{"schedule_time":"2026-10-01 19:30:00"}` |

Contoh membuat turnamen:

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri http://127.0.0.1:8080/api/tournaments `
  -ContentType 'application/json' `
  -Body '{"name":"Summer Cup"}'
```

## Database

File migrasi di `migrations/` dijalankan berurutan. Saat API dijalankan, SQLx menerapkan migrasi yang belum terpasang. Untuk menjalankannya secara manual gunakan `sqlx migrate run`.

Stored procedure `pr_create_team` dan `pr_create_tournament` menjalankan `COMMIT` di database setelah insert berhasil. Endpoint API memanggil procedure tersebut melalui `CALL`.

## CI

GitHub Actions menjalankan PostgreSQL sebagai service, menerapkan migrasi, lalu menjalankan `cargo build` dan `cargo test` pada push atau pull request ke branch `master`.
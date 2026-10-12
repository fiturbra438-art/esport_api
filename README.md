# Esport API

REST API untuk mengelola player, tim, turnamen, dan jadwal pertandingan e-sport. API dibuat dengan Rust, Axum, SQLx, dan PostgreSQL.

## Fitur

- Registrasi dan profil player.
- Login dengan JWT Bearer untuk semua operasi yang mengubah data.
- Validasi input dan password hashing Argon2.
- Pembuatan tim, pengelolaan anggota, dan perpindahan kapten.
- Pembuatan turnamen dan pendaftaran tim.
- Pembuatan pertandingan serta pengaturan jadwal.
- Migrasi database otomatis saat aplikasi dijalankan.
- Operasi tulis pengguna, tim, turnamen, dan pertandingan menggunakan stored procedure PostgreSQL.

## Persyaratan

- Rust stable 1.85 atau lebih baru.
- Docker dengan Docker Compose.
- SQLx CLI 0.7.4 untuk menjalankan migrasi secara manual.

## Menjalankan secara lokal

1. Jika `.env` belum ada, buat dari `.env.example`; jika sudah ada, jangan
   menimpanya dan tambahkan konfigurasi yang belum ada. Isi `POSTGRES_PASSWORD`
   dan `JWT_SECRET` dengan nilai acak yang berbeda. Salin password yang sama ke
   bagian password pada `DATABASE_URL`; gunakan karakter hex agar aman dalam
   URL. Jalankan perintah ini dua kali untuk membuat dua nilai berbeda:

   ```powershell
   if (-not (Test-Path .env)) { Copy-Item .env.example .env }
   [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
   ```

   `JWT_SECRET` harus minimal 32 byte dan hanya disimpan di environment atau
   `.env` (yang diabaikan Git). Jangan commit file `.env`.
   Compose memerlukan `POSTGRES_USER`, `POSTGRES_PASSWORD`, dan `POSTGRES_DB`.
   `DATABASE_URL` dipakai oleh endpoint API dan sebaiknya memakai role terbatas
   seperti `esport_app`. `DATABASE_MIGRATOR_URL` dipakai hanya saat startup
   untuk migrasi, dan harus memakai akun pemilik database/schema. Keduanya juga
   harus menggunakan host dan nama database yang sama. `JWT_SECRET` diperlukan
   untuk token login. Tambahkan `DATABASE_MIGRATOR_URL` ke `.env` dengan
   kredensial pemilik database, contohnya:

   ```text
   DATABASE_MIGRATOR_URL=postgres://<pemilik>:<password-pemilik>@localhost:5432/TOURNAMEN_ESPORT
   ```

2. Jalankan PostgreSQL:

   ```powershell
   docker compose up -d db
   ```

3. Atur `DATABASE_URL` agar SQLx dapat memeriksa query saat compile. Sesuaikan
   nilai ini dengan konfigurasi di `.env`:

   ```powershell
   $env:DATABASE_URL = "postgres://postgres:fitur1206@localhost:5432/TOURNAMEN_ESPORT"
   ```

4. Pasang SQLx CLI jika belum tersedia. SQLx CLI memakai `DATABASE_URL`, jadi
   arahkan sementara ke akun pemilik database saat menjalankan migrasi manual.
   API juga menjalankan migrasi otomatis melalui `DATABASE_MIGRATOR_URL` saat
   startup:

   ```powershell
   cargo install sqlx-cli --version 0.7.4 --no-default-features --features postgres,rustls --locked
   $env:DATABASE_URL = "<samakan dengan DATABASE_MIGRATOR_URL>"
   sqlx migrate run
   $env:DATABASE_URL = "<samakan dengan DATABASE_URL untuk role aplikasi>"
   ```

5. Pastikan kedua URL database mengarah ke database yang sama. Jika memakai
   role aplikasi terpisah, jalankan `database/dcl.sql` sebagai pemilik database
   setelah migrasi pertama agar role tersebut mendapat izin atas tabel,
   sequence, dan prosedur.

6. Jalankan API:

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
| `POST` | `/api/users` | `{"username":"player1","password":"contoh-password-kuat","mmr_point":1000}` |
| `POST` | `/api/auth/login` | `{"username":"player1","password":"contoh-password-kuat"}` |
| `GET` | `/api/users/{id}` | - |
| `POST` | `/api/teams` | `{"name":"Team Alpha","captain_username":"player1"}` |
| `GET` | `/api/teams/{id}` | - |
| `POST` | `/api/teams/join` | `{"team_name":"Team Alpha","username":"player2"}` |
| `DELETE` | `/api/teams/members` | `{"team_name":"Team Alpha","username":"player2"}` |
| `PUT` | `/api/teams/captain` | `{"team_name":"Team Alpha","new_captain_username":"player2"}` |
| `POST` | `/api/tournaments` | `{"name":"Summer Cup","max_teams":8}` |
| `GET` | `/api/tournaments` | - |
| `DELETE` | `/api/tournaments/{name}` | - |
| `POST` | `/api/tournaments/register` | `{"tournament_name":"Summer Cup","team_name":"Team Alpha"}` |
| `POST` | `/api/matches` | `{"tournament_name":"Summer Cup","team1_name":"Team Alpha","team2_name":"Team Beta","round_number":1}` |
| `GET` | `/api/tournaments/{id}/matches` | - |
| `PUT` | `/api/matches/{id}/schedule` | `{"schedule_time":"2026-10-01 19:30:00"}` |

Contoh membuat turnamen:

```powershell
$login = Invoke-RestMethod `
  -Method Post `
  -Uri http://127.0.0.1:8080/api/auth/login `
  -ContentType 'application/json' `
  -Body '{"username":"player1","password":"contoh-password-kuat"}'
$token = $login.access_token

Invoke-RestMethod `
  -Method Post `
  -Uri http://127.0.0.1:8080/api/tournaments `
  -ContentType 'application/json' `
  -Headers @{ Authorization = "Bearer $token" } `
  -Body '{"name":"Summer Cup","max_teams":8}'
```

Registrasi dan login bersifat publik. Semua endpoint yang mengubah data
(pembuatan/pengelolaan tim, turnamen, pertandingan) memerlukan header
`Authorization: Bearer <access_token>`. Token JWT berlaku selama satu jam.
Endpoint GET tetap publik. Pendaftaran tim ke turnamen hanya dapat dilakukan
oleh kapten tim yang sedang didaftarkan. Backend mengambil ID pengguna dari JWT,
mengunci baris tim selama pemeriksaan dan pendaftaran, serta mengembalikan HTTP
403 jika pengguna bukan kapten.

Username registrasi dibatasi 3-32 karakter (huruf, angka, `_`, `-`), password
12-128 byte, MMR 0-100000, nama resource 1-100 karakter, dan nomor ronde serta
ID harus positif. `max_teams` wajib berupa bilangan bulat positif. Pendaftaran
ditolak dengan HTTP 409 ketika kuota turnamen penuh. Error database dicatat di
log server dan respons hanya berisi pesan umum, bukan detail SQL.

Kata sandi akun lama yang tersimpan sebagai plaintext tidak dapat login setelah
hash Argon2 diberlakukan. Saat ini belum ada endpoint reset password, sehingga
akun tersebut harus dipulihkan secara terkontrol sebelum dapat login; backend
tidak menerima plaintext sebagai fallback.

## Cara kerja JSON di backend

Axum membaca request dengan extractor `Json<T>`, lalu Serde memetakan field JSON
ke struct DTO seperti `CreateUserDto`. Backend memvalidasi dan memproses nilainya,
kemudian SQLx mengirim data ke PostgreSQL melalui parameter bind dan stored
procedure. Nilai balasan dibuat sebagai struct response atau `serde_json::json!`,
lalu Axum/Serde mengubahnya menjadi JSON untuk client. Contohnya, registrasi
menerima `username`, `password`, dan `mmr_point`, tetapi respons hanya mengirim
`id`, `username`, dan `mmr_point`.

JSON adalah format pertukaran data, bukan mekanisme enkripsi atau validasi.
Karena itu backend meng-hash password dengan Argon2id sebelum menyimpannya;
password asli dan hash-nya tidak disertakan dalam response. Gunakan HTTPS saat
mengirim JSON agar request terlindungi selama perjalanan melalui jaringan.

## Uji API dengan Postman

Import collection [`postman/esport-api.postman_collection.json`](./postman/esport-api.postman_collection.json)
ke Postman, lalu jalankan semua request dengan Collection Runner secara berurutan.
Collection membuat user, tim, turnamen, dan pertandingan uji secara otomatis,
memeriksa status HTTP serta bentuk JSON, lalu menghapus turnamen uji di akhir.
User dan tim uji tetap tersimpan karena API belum memiliki endpoint hapusnya.
Petunjuk lengkap ada di [`postman/README.md`](./postman/README.md).

## Database

File migrasi di `migrations/` dijalankan berurutan. Folder tetap flat agar kompatibel dengan SQLx; indeks dan ringkasan migrasi tersedia di [`migrations/README.md`](./migrations/README.md). Saat API dijalankan, SQLx menerapkan migrasi yang belum terpasang. Untuk menjalankannya secara manual gunakan `sqlx migrate run`.

Jika memakai role database terpisah, buat role dengan `CREATE ROLE esport_app LOGIN;`,
lalu atur password secara interaktif dengan `\password esport_app` di `psql` sebelum menjalankan
[`database/dcl.sql`](./database/dcl.sql). File tersebut hanya memberikan grants
dan tidak lagi menetapkan password bawaan.

Migrasi `008_add_procedure_indexes.sql` menambahkan indeks untuk pencarian jadwal pertandingan dan kolom foreign key yang digunakan saat mengelola anggota, pendaftaran, serta penghapusan data terkait. Constraint unik pada pasangan anggota tim dan pendaftaran turnamen tetap menjadi perlindungan terakhir untuk mencegah duplikasi. Migrasi `009_lookup_ids_by_names.sql` menambahkan indeks nama turnamen dan mengubah prosedur terkait agar menerima username/nama alih-alih ID. Migrasi `010_wrap_business_functions_with_procedures.sql` mempertahankan fungsi bisnis dan membungkusnya dengan stored procedure, termasuk prosedur registrasi pengguna. Migrasi `012_move_duplicate_registration_check_to_function.sql` memindahkan pemeriksaan pendaftaran ganda ke function registrasi, yang tetap dipanggil oleh procedure; endpoint menjalankan pemanggilan procedure dalam transaksi dan membatalkan transaksi jika terjadi error. Trigger lain tetap dipakai untuk sinkronisasi anggota kapten dan penghitung pendaftaran.

## CI

GitHub Actions menjalankan PostgreSQL sebagai service, menerapkan migrasi, lalu menjalankan `cargo build` dan `cargo test` pada push atau pull request ke branch `master`.
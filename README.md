# Esport API

REST API untuk mengelola player, tim, turnamen, dan jadwal pertandingan e-sport. API dibuat dengan Rust, Axum, SQLx, dan PostgreSQL.

## Fitur

- Role `user` dan `admin`; hanya admin dapat mengelola turnamen dan pertandingan.
- Registrasi dan profil player.
- Login dengan JWT Bearer untuk semua operasi yang mengubah data.
- Validasi input dan password hashing Argon2.
- Pembuatan tim, pengelolaan anggota, dan perpindahan kapten.
- Direktori tim, keluar tim, penghapusan tim, serta penggantian kapten saat kapten keluar.
- Pembuatan turnamen dan pendaftaran tim.
- Daftar peserta turnamen, pembuatan pertandingan, pengaturan jadwal, dan pencatatan pemenang.
- Perubahan username dan penghapusan akun sendiri.
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
| `GET` | `/api/users/by-username/{username}` | - |
| `PUT` | `/api/users/me` | `{"username":"username_baru"}` |
| `DELETE` | `/api/users/me` | `{"captain_replacements":[{"team_id":1,"new_captain_username":"player2"}]}` |
| `POST` | `/api/teams` | `{"name":"Team Alpha","captain_username":"player1"}` |
| `GET` | `/api/teams/list` | - |
| `GET` | `/api/teams/{id}` | - |
| `GET` | `/api/teams/by-name/{team_name}` | - |
| `POST` | `/api/teams/join` | `{"team_name":"Team Alpha"}` |
| `POST` | `/api/teams/leave` | `{"team_name":"Team Alpha","new_captain_username":"player2"}` |
| `DELETE` | `/api/teams/members` | `{"team_name":"Team Alpha","username":"player2"}` |
| `PUT` | `/api/teams/captain` | `{"team_name":"Team Alpha","new_captain_username":"player2"}` |
| `DELETE` | `/api/teams/delete` | `{"team_name":"Team Alpha"}` |
| `POST` | `/api/tournaments` | `{"name":"Summer Cup","max_teams":8}` |
| `GET` | `/api/tournaments` | - |
| `GET` | `/api/tournaments/{id}/teams` | - |
| `GET` | `/api/tournaments/by-name/{tournament_name}/teams` | - |
| `DELETE` | `/api/tournaments/{name}` | - |
| `POST` | `/api/tournaments/register` | `{"tournament_name":"Summer Cup","team_name":"Team Alpha"}` |
| `POST` | `/api/matches` | `{"tournament_name":"Summer Cup","team1_name":"Team Alpha","team2_name":"Team Beta","round_number":1}` |
| `GET` | `/api/tournaments/{id}/matches` | - |
| `GET` | `/api/tournaments/by-name/{tournament_name}/matches` | - |
| `PUT` | `/api/matches/{id}/schedule` | `{"schedule_time":"2026-10-01 19:30:00"}` |
| `PUT` | `/api/matches/by-name/schedule` | `{"tournament_name":"Summer Cup","team_name":"Team Alpha","schedule_time":"2026-10-01 19:30:00"}` |
| `PUT` | `/api/matches/{id}/result` | `{"winner_team_name":"Team Alpha"}` |
| `PUT` | `/api/matches/by-name/result` | `{"tournament_name":"Summer Cup","team_name":"Team Alpha","winner_team_name":"Team Alpha"}` |

`POST /api/teams/join` menambahkan akun yang sedang login ke tim; username
anggota diambil dari token Bearer dan tidak perlu dikirim di body.
Endpoint GET yang berakhiran `by-name` atau `by-username` menerima nama pada
URL dan mencari ID melalui prosedur lookup database. Endpoint GET lama yang
menerima ID tetap tersedia.
Jadwal dan hasil pertandingan juga dapat diperbarui melalui nama turnamen dan
salah satu nama tim yang bertanding. Jika tim tersebut memiliki beberapa match
di turnamen yang sama, endpoint mengembalikan HTTP 409 agar match yang salah
tidak terpilih; gunakan endpoint berbasis ID untuk kasus ambigu.
`POST /api/teams/join` menambahkan akun yang sedang login berdasarkan token
Bearer; username anggota tidak perlu dikirim di body.
`PUT /api/users/me` hanya mengubah username akun yang sedang login; MMR tidak
bisa diubah lewat profil. Penghapusan akun hanya berlaku untuk akun sendiri.
Jika akun memimpin beberapa tim, request harus menyertakan seorang anggota
pengganti untuk setiap tim. Seluruh operasi gagal tanpa perubahan jika ada satu
pengganti yang tidak valid. `DELETE /api/teams/delete` hanya dapat dipakai
kapten; penghapusan tim juga menghapus pendaftaran turnamen dan pertandingan
yang terkait. Saat keluar dari tim, anggota biasa cukup mengirim `team_name`;
kapten wajib mengirim `new_captain_username` yang merupakan anggota tim lain.
Pencatatan hasil pertandingan hanya dapat dilakukan admin, menetapkan pemenang
dari salah satu tim yang bertanding, dan mengubah status menjadi `completed`.
Skor pertandingan belum disimpan.

### Menyiapkan akun admin

Daftarkan akun lewat `POST /api/users` seperti pengguna biasa, lalu promosikan
akun yang dipercaya melalui pgAdmin Query Tool. Pastikan API sudah dijalankan
setelah baseline database diterapkan agar kolom `role` tersedia:

```sql
UPDATE users
SET role = 'admin'
WHERE username = 'username_admin_yang_dipilih'
RETURNING id, username, role;
```

Pastikan query mengembalikan tepat satu akun dengan `role = 'admin'`. Registrasi
publik selalu membuat akun sebagai `user`; role tidak dapat diatur lewat body
registrasi. Setelah promosi, login ulang agar Postman menggunakan akun admin.
Untuk mencabut hak admin, ubah role kembali menjadi `user`.

### Membuat turnamen

Pembuatan turnamen hanya bisa dilakukan dengan token akun admin:

```powershell
$login = Invoke-RestMethod `
  -Method Post `
  -Uri http://127.0.0.1:8080/api/auth/login `
  -ContentType 'application/json' `
  -Body '{"username":"username_admin_yang_dipilih","password":"password-admin"}'
$token = $login.access_token

Invoke-RestMethod `
  -Method Post `
  -Uri http://127.0.0.1:8080/api/tournaments `
  -ContentType 'application/json' `
  -Headers @{ Authorization = "Bearer $token" } `
  -Body '{"name":"Summer Cup","max_teams":8}'
```

Nama turnamen tidak boleh duplikat. Perbandingan mengabaikan huruf besar/kecil
dan spasi di awal/akhir; contoh `Summer Cup` dan ` summer cup ` dianggap sama.
Request duplikat menerima HTTP 409. Database menegakkan batas ini dengan unique
index sehingga request bersamaan juga tidak dapat membuat nama yang sama.

Registrasi dan login bersifat publik. Semua endpoint yang mengubah data
(pembuatan/pengelolaan tim, turnamen, pertandingan) memerlukan header
`Authorization: Bearer <access_token>`. Token JWT berlaku selama satu jam.
Endpoint GET tetap publik. Pembuatan dan penghapusan turnamen serta pengelolaan pertandingan hanya bisa
dilakukan role `admin`; pengguna biasa menerima HTTP 403. Pembuatan tim
menetapkan pengguna yang sedang login sebagai kapten, dan endpoint gabung tim
hanya dapat mendaftarkan akun yang sedang login. Penghapusan anggota dan
perpindahan kapten hanya dapat dilakukan oleh kapten tim; pengguna lain
menerima HTTP 403. Pendaftaran tim ke turnamen juga hanya dapat dilakukan oleh
kapten tim yang sedang didaftarkan.
API meneruskan ID pengguna dari JWT ke stored procedure. Procedure memeriksa
role admin atau kapten sebelum mutasi, mengunci baris tim selama operasi yang
memerlukan pemeriksaan kapten, dan mengembalikan HTTP 403 bila akses ditolak.

Username registrasi dibatasi 3-32 karakter (huruf, angka, `_`, `-`), password
12-128 byte, MMR 0-100000, nama resource 1-100 karakter, dan nomor ronde serta
ID harus positif. `max_teams` wajib berupa bilangan bulat positif. Pendaftaran
ditolak dengan HTTP 409 ketika kuota turnamen penuh. Error database dicatat di
log server dan respons hanya berisi pesan umum, bukan detail SQL.
Setiap endpoint tulis menjalankan satu `CALL` langsung melalui koneksi pool,
tanpa mengelola transaksi di backend. Procedure yang mengubah data menjalankan
`COMMIT` eksplisit di akhir; jika error terjadi sebelum itu, PostgreSQL
membatalkan perubahan dalam `CALL`. Karena itu, mutating procedure harus
dipanggil sebagai `CALL` langsung, bukan di dalam transaksi eksplisit yang
dibuka pemanggil. Proses pendaftaran turnamen, termasuk pemeriksaan kapten,
pendaftaran, dan perubahan kuota oleh trigger, berada dalam satu `CALL`.

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
Collection belum menjalankan endpoint hapus akun atau tim, jadi user dan tim
uji yang dibuatnya tetap tersimpan.
Petunjuk lengkap ada di [`postman/README.md`](./postman/README.md).

## Database

Folder `migrations/` berisi migrasi SQLx modular yang dijalankan saat API mulai.
Baseline ini untuk database baru atau database development yang memang akan
di-reset. Database yang sudah memakai migrasi versi lama 000–016 atau versi
tambahan 6–7 perlu di-reset sebelum memakai susunan yang digabung ini, karena
SQLx menyimpan checksum setiap migrasi. Untuk menjalankan migrasi manual gunakan
`sqlx migrate run`; detail ada di [`migrations/README.md`](./migrations/README.md).

Jika memakai role database terpisah, buat role dengan `CREATE ROLE esport_app LOGIN;`,
lalu atur password secara interaktif dengan `\password esport_app` di `psql` sebelum menjalankan
[`database/dcl.sql`](./database/dcl.sql). File tersebut hanya memberikan grants
dan tidak lagi menetapkan password bawaan.

Baseline dibagi menjadi beberapa file pendek sesuai jenis objek database:
schema, functions, triggers, views, lalu procedures. Fitur tambahan dibuat
sebagai migrasi baru dengan versi lebih tinggi. API memanggil prosedur untuk
mutasi database tanpa mengelola transaksi; atomisitas tiap `CALL` ditangani
PostgreSQL. Pembacaan daftar menggunakan view.

## CI

GitHub Actions menjalankan PostgreSQL sebagai service, menerapkan migrasi, lalu menjalankan `cargo build` dan `cargo test` pada push atau pull request ke branch `master`.
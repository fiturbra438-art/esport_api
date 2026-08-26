use axum::{routing::get, Router};
use sqlx::postgres::PgPoolOptions;

mod handlers;

#[tokio::main]
async fn main() {
    // 1. URL Koneksi ke PostgreSQL yang ada di Docker kamu
    let database_url = "postgres://admin:admin1206@localhost:5432/TOURNAMEN_ESPORT";

    // 2. Membuka koneksi pool ke database
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(database_url)
        .await
        .expect("❌ Gagal terhubung ke database! Pastikan Docker menyala.");

    println!("✅ Berhasil terhubung ke database TOURNAMEN_ESPORT!");

    // 3. Menyiapkan rute API dasar
    let app = Router::new()
        .route("/", get(|| async { "API Turnamen E-Sport Berjalan Mantap!" }))
        .route("/api/users", axum::routing::post(handlers::register_user))  
        .with_state(pool);

    // 4. Menyalakan server di port 8080
    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080").await.unwrap();
    println!("🚀 Server siap menerima request di http://127.0.0.1:8080");
    
    axum::serve(listener, app).await.unwrap();
}
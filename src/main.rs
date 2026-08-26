use axum::{routing::get, Router};
use sqlx::postgres::PgPoolOptions;

mod handlers;

#[tokio::main]
async fn main() {
    let database_url: &str = "postgres://admin:admin1206@localhost:5432/TOURNAMEN_ESPORT";

    let pool: sqlx::Pool<sqlx::Postgres> = PgPoolOptions::new()
        .max_connections(5)
        .connect(database_url)
        .await
        .expect("❌ Gagal terhubung ke database! Pastikan Docker menyala.");

    println!("✅ Berhasil terhubung ke database TOURNAMEN_ESPORT!");

    let app = Router::new()
        .route("/", get(|| async { "API Turnamen E-Sport Berjalan Mantap!" }))
        .route("/api/users", axum::routing::post(handlers::register_user))  
        .with_state(pool);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080").await.unwrap();
    println!("🚀 Server siap menerima request di http://127.0.0.1:8080");
    
    axum::serve(listener, app).await.unwrap();
}
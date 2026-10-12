use axum::{
    Extension, Router, middleware,
    routing::{delete, get, post, put},
};
use dotenvy::dotenv;
use sqlx::postgres::PgPoolOptions;
use std::env;
use tracing_subscriber::EnvFilter;

mod auth;
mod handlers;

#[tokio::main]
async fn main() {
    dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();
    let database_url = env::var("DATABASE_URL")
        .expect("❌ DATABASE_URL tidak ditemukan di environment atau file .env");
    let jwt_secret = env::var("JWT_SECRET")
        .expect("❌ JWT_SECRET wajib diatur melalui environment atau file .env");
    if jwt_secret.len() < 32 {
        panic!("❌ JWT_SECRET harus memiliki panjang minimal 32 byte");
    }
    let jwt_config = auth::JwtConfig::new(jwt_secret);

    let pool: sqlx::Pool<sqlx::Postgres> = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("❌ Gagal terhubung ke database! Pastikan Docker menyala.");

    sqlx::migrate!()
        .run(&pool)
        .await
        .expect("❌ Gagal menjalankan migrasi database!");

    println!("✅ Berhasil terhubung ke database TOURNAMEN_ESPORT!");

    let protected_routes = Router::new()
        .route("/api/teams", post(handlers::create_team))
        .route("/api/teams/join", post(handlers::join_team))
        .route("/api/teams/members", delete(handlers::remove_team_member))
        .route("/api/teams/captain", put(handlers::transfer_captain))
        .route("/api/tournaments", post(handlers::create_tournament))
        .route(
            "/api/tournaments/:name",
            delete(handlers::delete_tournament),
        )
        .route(
            "/api/tournaments/register",
            post(handlers::register_tournament),
        )
        .route("/api/matches", post(handlers::create_match))
        .route(
            "/api/matches/:id/schedule",
            put(handlers::update_match_schedule),
        )
        .route_layer(middleware::from_fn(auth::require_auth));

    let app = Router::new()
        .route("/", get(|| async { "API Turnamen E-Sport Berjalan cukkk" }))
        .route("/api/users", post(handlers::register_user))
        .route("/api/auth/login", post(handlers::login))
        .route("/api/users/:id", get(handlers::get_user_profile))
        .route("/api/teams/:id", get(handlers::get_team_profile))
        .route("/api/tournaments", get(handlers::get_tournaments))
        .route(
            "/api/tournaments/:id/matches",
            get(handlers::get_tournament_matches),
        )
        .merge(protected_routes)
        .layer(Extension(jwt_config))
        .with_state(pool);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080")
        .await
        .unwrap();
    println!("🚀 Server siap menerima request di http://127.0.0.1:8080");

    axum::serve(listener, app).await.unwrap();
}

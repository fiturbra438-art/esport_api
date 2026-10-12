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
    let migration_database_url = env::var("DATABASE_MIGRATOR_URL").expect(
        "❌ DATABASE_MIGRATOR_URL wajib diatur ke koneksi pemilik database untuk menjalankan migrasi",
    );
    let jwt_secret = env::var("JWT_SECRET")
        .expect("❌ JWT_SECRET wajib diatur melalui environment atau file .env");
    if jwt_secret.len() < 32 {
        panic!("❌ JWT_SECRET harus memiliki panjang minimal 32 byte");
    }
    let jwt_config = auth::JwtConfig::new(jwt_secret);

    let migration_pool = PgPoolOptions::new()
        .max_connections(1)
        .connect(&migration_database_url)
        .await
        .expect("❌ Gagal terhubung ke database dengan akun migrasi");

    sqlx::migrate!()
        .run(&migration_pool)
        .await
        .expect("❌ Gagal menjalankan migrasi database dengan akun migrasi!");

    migration_pool.close().await;

    let pool: sqlx::Pool<sqlx::Postgres> = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .expect("❌ Gagal terhubung ke database! Pastikan Docker menyala.");

    println!("✅ Berhasil terhubung ke database TOURNAMEN_ESPORT!");

    let protected_routes = Router::new()
        .route(
            "/api/users/me",
            put(handlers::update_username).delete(handlers::delete_account),
        )
        .route("/api/teams", post(handlers::create_team))
        .route("/api/teams/delete", delete(handlers::delete_team))
        .route("/api/teams/join", post(handlers::join_team))
        .route("/api/teams/leave", post(handlers::leave_team))
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
            "/api/matches/by-name/result",
            put(handlers::set_match_result_by_names),
        )
        .route(
            "/api/matches/by-name/schedule",
            put(handlers::update_match_schedule_by_names),
        )
        .route("/api/matches/:id/result", put(handlers::set_match_result))
        .route(
            "/api/matches/:id/schedule",
            put(handlers::update_match_schedule),
        )
        .route_layer(middleware::from_fn(auth::require_auth));

    let app = Router::new()
        .route("/", get(|| async { "API Turnamen E-Sport Berjalan cukkk" }))
        .route("/api/users", post(handlers::register_user))
        .route("/api/auth/login", post(handlers::login))
        .route(
            "/api/users/by-username/:username",
            get(handlers::get_user_profile_by_username),
        )
        .route("/api/users/:id", get(handlers::get_user_profile))
        .route("/api/teams/list", get(handlers::get_teams))
        .route(
            "/api/teams/by-name/:team_name",
            get(handlers::get_team_profile_by_name),
        )
        .route("/api/teams/:id", get(handlers::get_team_profile))
        .route("/api/tournaments", get(handlers::get_tournaments))
        .route(
            "/api/tournaments/by-name/:tournament_name/teams",
            get(handlers::get_tournament_teams_by_name),
        )
        .route(
            "/api/tournaments/by-name/:tournament_name/matches",
            get(handlers::get_tournament_matches_by_name),
        )
        .route(
            "/api/tournaments/:id/teams",
            get(handlers::get_tournament_teams),
        )
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

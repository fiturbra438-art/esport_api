use axum::{
    Router,
    routing::{delete, get, post, put},
};
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

    sqlx::migrate!()
        .run(&pool)
        .await
        .expect("❌ Gagal menjalankan migrasi database!");

    println!("✅ Berhasil terhubung ke database TOURNAMEN_ESPORT!");

    let app = Router::new()
        .route(
            "/",
            get(|| async { "API Turnamen E-Sport Berjalan Mantap!" }),
        )
        .route("/api/users", axum::routing::post(handlers::register_user))
        .route("/api/users/:id", get(handlers::get_user_profile))
        .route("/api/teams", post(handlers::create_team))
        .route("/api/teams/join", post(handlers::join_team))
        .route("/api/teams/members", delete(handlers::remove_team_member))
        .route("/api/teams/captain", put(handlers::transfer_captain))
        .route("/api/teams/:id", get(handlers::get_team_profile))
        .route("/api/tournaments",post(handlers::create_tournament).get(handlers::get_tournaments),)
        .route("/api/tournaments/:id", delete(handlers::delete_tournament))
        .route("/api/tournaments/register",post(handlers::register_tournament),)
        .route("/api/tournaments/:id/matches",get(handlers::get_tournament_matches),)
        .route("/api/matches", post(handlers::create_match))
        .route("/api/matches/:id/schedule",put(handlers::update_match_schedule),)
        .with_state(pool);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:8080")
        .await
        .unwrap();
    println!("🚀 Server siap menerima request di http://127.0.0.1:8080");

    axum::serve(listener, app).await.unwrap();
}

use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use super::response::{error_response, message};

#[derive(Deserialize)]
pub struct CreateTournamentDto {
    pub name: String,
}

#[derive(Serialize)]
pub struct TournamentResponse {
    pub id: i32,
    pub name: String,
    pub status: Option<String>,
}

pub async fn create_tournament(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateTournamentDto>,
) -> impl IntoResponse {
    match sqlx::query_as!(
        TournamentResponse,
        "INSERT INTO tournaments (name, status) VALUES ($1, 'open') RETURNING id, name, status",
        payload.name
    )
    .fetch_one(&pool)
    .await
    {
        Ok(tournament) => (
            StatusCode::CREATED,
            Json(serde_json::json!({"message": "Turnamen berhasil dibuat dan siap menerima pendaftaran!", "data": tournament})),
        ).into_response(),
        Err(error) => error_response(StatusCode::INTERNAL_SERVER_ERROR, format!("Gagal membuat turnamen: {error}")),
    }
}

pub async fn get_tournaments(State(pool): State<PgPool>) -> impl IntoResponse {
    match sqlx::query_as!(TournamentResponse, "SELECT id, name, status FROM tournaments")
        .fetch_all(&pool)
        .await
    {
        Ok(tournaments) => (
            StatusCode::OK,
            Json(serde_json::json!({"message": "Berhasil mengambil daftar turnamen", "data": tournaments})),
        ).into_response(),
        Err(error) => error_response(StatusCode::INTERNAL_SERVER_ERROR, format!("Gagal mengambil data turnamen: {error}")),
    }
}

#[derive(Deserialize)]
pub struct RegisterTournamentDto {
    pub tournament_id: i32,
    pub team_id: i32,
}

pub async fn register_tournament(
    State(pool): State<PgPool>,
    Json(payload): Json<RegisterTournamentDto>,
) -> impl IntoResponse {
    match sqlx::query!(
        "INSERT INTO tournament_registrations (tournament_id, team_id) VALUES ($1, $2)",
        payload.tournament_id,
        payload.team_id
    )
    .execute(&pool)
    .await
    {
        Ok(_) => message(
            StatusCode::CREATED,
            "Tim berhasil didaftarkan ke turnamen dan siap bertanding!",
        ),
        Err(error) => error_response(
            StatusCode::BAD_REQUEST,
            format!(
                "Gagal mendaftar. Pastikan turnamen/tim ada, atau tim ini mungkin sudah terdaftar. Detail: {error}"
            ),
        ),
    }
}

pub async fn delete_tournament(
    State(pool): State<PgPool>,
    Path(tournament_id): Path<i32>,
) -> impl IntoResponse {
    match sqlx::query!("DELETE FROM tournaments WHERE id = $1", tournament_id)
        .execute(&pool)
        .await
    {
        Ok(result) if result.rows_affected() > 0 => message(
            StatusCode::OK,
            "Turnamen beserta seluruh data pendaftarannya berhasil dihapus!",
        ),
        Ok(_) => error_response(StatusCode::NOT_FOUND, "Turnamen tidak ditemukan."),
        Err(error) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Gagal menghapus turnamen: {error}"),
        ),
    }
}

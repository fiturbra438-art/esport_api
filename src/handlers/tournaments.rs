use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use super::response::{error_response, log_error, message};

fn valid_name(value: &str) -> bool {
    let value = value.trim();
    !value.is_empty() && value.chars().count() <= 100
}

#[derive(Deserialize)]
pub struct CreateTournamentDto {
    pub name: String,
}

#[derive(Serialize, sqlx::FromRow)]
pub struct TournamentResponse {
    pub id: i32,
    pub name: String,
    pub status: Option<String>,
}

pub async fn create_tournament(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateTournamentDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama turnamen wajib diisi (maksimal 100 karakter)",
        );
    }
    let tournament = match sqlx::query_as::<_, TournamentResponse>(
        "CALL pr_create_tournament($1, NULL, NULL, NULL)",
    )
    .bind(payload.name)
    .fetch_one(&pool)
    .await
    {
        Err(error) => {
            log_error("create_tournament", error);
            return error_response(StatusCode::BAD_REQUEST, "Gagal membuat turnamen");
        }
        Ok(tournament) => tournament,
    };

    (
        StatusCode::CREATED,
        Json(serde_json::json!({"message": "Turnamen berhasil dibuat dan siap menerima pendaftaran!", "data": tournament})),
    ).into_response()
}

pub async fn get_tournaments(State(pool): State<PgPool>) -> impl IntoResponse {
    match sqlx::query_as!(TournamentResponse, "SELECT id AS \"id!\", name AS \"name!\", status FROM vw_tournaments")
        .fetch_all(&pool)
        .await
    {
        Ok(tournaments) => (
            StatusCode::OK,
            Json(serde_json::json!({"message": "Berhasil mengambil daftar turnamen", "data": tournaments})),
        ).into_response(),
        Err(error) => {
            log_error("get_tournaments", error);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil data turnamen")
        }
    }
}

#[derive(Deserialize)]
pub struct RegisterTournamentDto {
    pub tournament_name: String,
    pub team_name: String,
}

pub async fn register_tournament(
    State(pool): State<PgPool>,
    Json(payload): Json<RegisterTournamentDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.tournament_name) || !valid_name(&payload.team_name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama turnamen dan tim wajib diisi (maksimal 100 karakter)",
        );
    }
    match sqlx::query("CALL pr_register_team_to_tournament($1, $2)")
        .bind(payload.tournament_name)
        .bind(payload.team_name)
        .execute(&pool)
        .await
    {
        Ok(_) => message(
            StatusCode::CREATED,
            "Tim berhasil didaftarkan ke turnamen dan siap bertanding!",
        ),
        Err(error) => {
            log_error("register_tournament", error);
            error_response(
                StatusCode::BAD_REQUEST,
                "Gagal mendaftarkan tim ke turnamen",
            )
        }
    }
}

pub async fn delete_tournament(
    State(pool): State<PgPool>,
    Path(tournament_name): Path<String>,
) -> impl IntoResponse {
    if !valid_name(&tournament_name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama turnamen wajib diisi (maksimal 100 karakter)",
        );
    }
    match sqlx::query("CALL pr_delete_tournament($1)")
        .bind(tournament_name)
        .execute(&pool)
        .await
    {
        Ok(_) => message(
            StatusCode::OK,
            "Turnamen beserta seluruh data pendaftarannya berhasil dihapus!",
        ),
        Err(error) => {
            log_error("delete_tournament", error);
            error_response(StatusCode::NOT_FOUND, "Gagal menghapus turnamen")
        }
    }
}

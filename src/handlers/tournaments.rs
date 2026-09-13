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
    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Gagal memulai transaksi: {error}"),
            );
        }
    };

    if let Err(error) = sqlx::query!("CALL pr_create_tournament($1)", payload.name)
        .execute(&mut *transaction)
        .await
    {
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Gagal membuat turnamen: {error}"),
        );
    }

    let tournament = match sqlx::query_as!(
        TournamentResponse,
        "SELECT id AS \"id!\", name AS \"name!\", status FROM vw_tournaments WHERE name = $1 ORDER BY id DESC LIMIT 1",
        payload.name
    )
    .fetch_one(&mut *transaction)
    .await
    {
        Ok(tournament) => tournament,
        Err(error) => return error_response(StatusCode::INTERNAL_SERVER_ERROR, format!("Turnamen dibuat tetapi gagal mengambil datanya: {error}")),
    };

    if let Err(error) = transaction.commit().await {
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Gagal commit transaksi: {error}"),
        );
    }

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
        "CALL pr_register_team_to_tournament($1, $2)",
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
    match sqlx::query!("CALL pr_delete_tournament($1)", tournament_id)
        .execute(&pool)
        .await
    {
        Ok(_) => message(
            StatusCode::OK,
            "Turnamen beserta seluruh data pendaftarannya berhasil dihapus!",
        ),
        Err(error) => error_response(
            StatusCode::NOT_FOUND,
            format!("Gagal menghapus turnamen: {error}"),
        ),
    }
}

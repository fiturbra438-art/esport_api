use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use time::PrimitiveDateTime;

use super::response::{error_response, message};

#[derive(Deserialize)]
pub struct CreateMatchDto {
    pub tournament_id: i32,
    pub team1_id: Option<i32>,
    pub team2_id: Option<i32>,
    pub round_number: i32,
}

pub async fn create_match(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateMatchDto>,
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

    if let Err(error) = sqlx::query!(
        "CALL pr_create_match($1, $2, $3, $4)",
        payload.tournament_id,
        payload.team1_id,
        payload.team2_id,
        payload.round_number
    )
    .execute(&mut *transaction)
    .await
    {
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Gagal membuat pertandingan: {error}"),
        );
    }

    if let Err(error) = transaction.commit().await {
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Gagal commit transaksi: {error}"),
        );
    }

    message(
        StatusCode::CREATED,
        "Jadwal pertandingan/breket berhasil ditambahkan!",
    )
}

#[derive(Serialize)]
pub struct MatchResponse {
    pub id: i32,
    pub round_number: Option<i32>,
    pub team1_name: Option<String>,
    pub team2_name: Option<String>,
}

pub async fn get_tournament_matches(
    State(pool): State<PgPool>,
    Path(tournament_id): Path<i32>,
) -> impl IntoResponse {
    match sqlx::query_as!(
        MatchResponse,
        "SELECT id AS \"id!\", round_number, team1_name, team2_name FROM vw_match_schedule WHERE tournament_id = $1 ORDER BY round_number ASC, id ASC",
        tournament_id
    )
    .fetch_all(&pool)
    .await
    {
        Ok(matches) => (
            StatusCode::OK,
            Json(serde_json::json!({"message": "Berhasil mengambil jadwal pertandingan", "data": matches})),
        ).into_response(),
        Err(error) => error_response(StatusCode::INTERNAL_SERVER_ERROR, format!("Gagal mengambil data pertandingan: {error}")),
    }
}

#[derive(Deserialize)]
pub struct UpdateScheduleDto {
    pub schedule_time: String,
}

pub async fn update_match_schedule(
    State(pool): State<PgPool>,
    Path(match_id): Path<i32>,
    Json(payload): Json<UpdateScheduleDto>,
) -> impl IntoResponse {
    let schedule_time = match PrimitiveDateTime::parse(
        &payload.schedule_time,
        &time::macros::format_description!("[year]-[month]-[day] [hour]:[minute]:[second]"),
    ) {
        Ok(schedule_time) => schedule_time,
        Err(error) => {
            return error_response(
                StatusCode::BAD_REQUEST,
                format!(
                    "Gagal mengatur jadwal. Pastikan format waktu benar (YYYY-MM-DD HH:MM:SS). Detail: {error}"
                ),
            );
        }
    };

    let result = sqlx::query!(
        "CALL pr_update_match_schedule($1, $2)",
        match_id,
        schedule_time
    )
    .execute(&pool)
    .await;

    match result {
        Ok(_) => message(
            StatusCode::OK,
            "Jadwal pertandingan berhasil ditentukan/diperbarui!",
        ),
        Err(error) => error_response(
            StatusCode::BAD_REQUEST,
            format!(
                "Gagal mengatur jadwal. Pastikan format waktu benar (YYYY-MM-DD HH:MM:SS). Detail: {error}"
            ),
        ),
    }
}

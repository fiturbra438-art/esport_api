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
    match sqlx::query!(
        "INSERT INTO matches (tournament_id, team1_id, team2_id, round_number) VALUES ($1, $2, $3, $4)",
        payload.tournament_id,
        payload.team1_id,
        payload.team2_id,
        payload.round_number
    )
    .execute(&pool)
    .await
    {
        Ok(_) => message(StatusCode::CREATED, "Jadwal pertandingan/breket berhasil ditambahkan!"),
        Err(error) => error_response(StatusCode::INTERNAL_SERVER_ERROR, format!("Gagal membuat pertandingan: {error}")),
    }
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
        "SELECT matches.id, matches.round_number, t1.name AS team1_name, t2.name AS team2_name FROM matches LEFT JOIN teams t1 ON matches.team1_id = t1.id LEFT JOIN teams t2 ON matches.team2_id = t2.id WHERE matches.tournament_id = $1 ORDER BY matches.round_number ASC, matches.id ASC",
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
    match sqlx::query!(
        "UPDATE matches SET schedule_time = $1::TIMESTAMP WHERE id = $2",
        payload.schedule_time,
        match_id
    )
    .execute(&pool)
    .await
    {
        Ok(result) if result.rows_affected() > 0 => message(
            StatusCode::OK,
            "Jadwal pertandingan berhasil ditentukan/diperbarui!",
        ),
        Ok(_) => error_response(StatusCode::NOT_FOUND, "Pertandingan tidak ditemukan."),
        Err(error) => error_response(
            StatusCode::BAD_REQUEST,
            format!(
                "Gagal mengatur jadwal. Pastikan format waktu benar (YYYY-MM-DD HH:MM:SS). Detail: {error}"
            ),
        ),
    }
}

use axum::{
    Extension, Json,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use sqlx::Row;
use time::PrimitiveDateTime;

use crate::auth::Claims;

use super::response::{error_response, log_error, message};

fn valid_name(value: &str) -> bool {
    let value = value.trim();
    !value.is_empty() && value.chars().count() <= 100
}

#[derive(Deserialize)]
pub struct CreateMatchDto {
    pub tournament_name: String,
    pub team1_name: Option<String>,
    pub team2_name: Option<String>,
    pub round_number: i32,
}

pub async fn create_match(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Json(payload): Json<CreateMatchDto>,
) -> impl IntoResponse {
    let actor_id = match claims.sub.parse::<i32>() {
        Ok(user_id) if user_id > 0 => user_id,
        _ => {
            return error_response(
                StatusCode::UNAUTHORIZED,
                "Identitas pengguna pada token tidak valid",
            );
        }
    };
    if !valid_name(&payload.tournament_name)
        || payload
            .team1_name
            .as_deref()
            .is_some_and(|name| !valid_name(name))
        || payload
            .team2_name
            .as_deref()
            .is_some_and(|name| !valid_name(name))
        || payload.round_number <= 0
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Turnamen wajib diisi, nama tim maksimal 100 karakter, dan round_number harus positif",
        );
    }
    if let Err(error) = sqlx::query("CALL pr_create_match($1, $2, $3, $4, $5)")
        .bind(actor_id)
        .bind(payload.tournament_name)
        .bind(payload.team1_name)
        .bind(payload.team2_name)
        .bind(payload.round_number)
        .execute(&pool)
        .await
    {
        let forbidden = error
            .as_database_error()
            .and_then(|database_error| database_error.code())
            .is_some_and(|code| code == "42501");
        log_error("create_match", error);
        return if forbidden {
            error_response(
                StatusCode::FORBIDDEN,
                "Hanya admin yang dapat mengelola pertandingan",
            )
        } else {
            error_response(StatusCode::BAD_REQUEST, "Gagal membuat pertandingan")
        };
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
    pub schedule_time: Option<String>,
    pub status: Option<String>,
    pub winner_name: Option<String>,
}

pub async fn get_tournament_matches(
    State(pool): State<PgPool>,
    Path(tournament_id): Path<i32>,
) -> impl IntoResponse {
    if tournament_id <= 0 {
        return error_response(StatusCode::BAD_REQUEST, "ID turnamen harus positif");
    }

    let mut tx = match pool.begin().await {
        Ok(tx) => tx,
        Err(error) => {
            log_error("get_tournament_matches_begin", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil jadwal pertandingan");
        }
    };

    if let Err(error) = sqlx::query(
        "CALL pr_get_tournament_matches($1, 'matches_cursor')",
    )
    .bind(tournament_id)
    .execute(&mut *tx)
    .await
    {
        log_error("get_tournament_matches_call", error);
        let _ = tx.rollback().await;
        return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil jadwal pertandingan");
    }

    let rows = match sqlx::query("FETCH ALL FROM matches_cursor")
        .fetch_all(&mut *tx)
        .await
    {
        Ok(rows) => rows,
        Err(error) => {
            log_error("get_tournament_matches_fetch", error);
            let _ = tx.rollback().await;
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil jadwal pertandingan");
        }
    };

    let _ = tx.commit().await;

    let matches: Vec<MatchResponse> = rows
        .into_iter()
        .map(|row| MatchResponse {
            id: row.get("id"),
            round_number: row.get("round_number"),
            team1_name: row.get("team1_name"),
            team2_name: row.get("team2_name"),
            schedule_time: row.get("schedule_time"),
            status: row.get("status"),
            winner_name: row.get("winner_name"),
        })
        .collect();

    (
        StatusCode::OK,
        Json(serde_json::json!({"message": "Berhasil mengambil jadwal pertandingan", "data": matches})),
    ).into_response()
}

pub async fn get_tournament_matches_by_name(
    State(pool): State<PgPool>,
    Path(tournament_name): Path<String>,
) -> axum::response::Response {
    if !valid_name(&tournament_name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama turnamen wajib diisi (maksimal 100 karakter)",
        );
    }

    match sqlx::query_as::<_, (i32,)>("CALL pr_get_tournament_id_by_name($1, NULL)")
        .bind(&tournament_name)
        .fetch_one(&pool)
        .await
    {
        Ok((tournament_id,)) => get_tournament_matches(State(pool), Path(tournament_id))
            .await
            .into_response(),
        Err(error) => {
            let not_found = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .is_some_and(|code| code == "P0001");
            log_error("get_tournament_id_for_matches", error);
            if not_found {
                error_response(StatusCode::NOT_FOUND, "Turnamen tidak ditemukan")
            } else {
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Gagal mencari turnamen berdasarkan nama",
                )
            }
        }
    }
}

#[derive(Deserialize)]
pub struct SetMatchResultDto {
    pub winner_team_name: String,
}

#[derive(Deserialize)]
pub struct SetMatchResultByNamesDto {
    pub tournament_name: String,
    pub team_name: String,
    pub winner_team_name: String,
}

#[derive(Deserialize)]
pub struct UpdateScheduleByNamesDto {
    pub tournament_name: String,
    pub team_name: String,
    pub schedule_time: String,
}

async fn find_match_id_by_tournament_and_team(
    pool: &PgPool,
    actor_id: i32,
    tournament_name: &str,
    team_name: &str,
) -> Result<i32, axum::response::Response> {
    match sqlx::query_as::<_, (i32,)>(
        "CALL pr_get_match_id_by_tournament_and_team($1, $2, $3, NULL)",
    )
    .bind(actor_id)
    .bind(tournament_name)
    .bind(team_name)
    .fetch_one(pool)
    .await
    {
        Ok((match_id,)) => Ok(match_id),
        Err(error) => {
            let code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("find_match_id_by_tournament_and_team", error);
            Err(match code.as_deref() {
                Some("42501") => error_response(
                    StatusCode::FORBIDDEN,
                    "Hanya admin yang dapat mengelola pertandingan",
                ),
                Some("P0001") | Some("P0002") => {
                    error_response(StatusCode::NOT_FOUND, "Pertandingan tidak ditemukan")
                }
                Some("P0003") => error_response(
                    StatusCode::CONFLICT,
                    "Tim memiliki lebih dari satu pertandingan di turnamen ini; gunakan ID pertandingan",
                ),
                _ => error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Gagal mencari pertandingan berdasarkan nama",
                ),
            })
        }
    }
}

pub async fn set_match_result_by_names(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Json(payload): Json<SetMatchResultByNamesDto>,
) -> axum::response::Response {
    if !valid_name(&payload.tournament_name)
        || !valid_name(&payload.team_name)
        || !valid_name(&payload.winner_team_name)
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama turnamen, tim yang bertanding, dan pemenang wajib diisi",
        );
    }
    let actor_id = match claims.sub.parse::<i32>() {
        Ok(user_id) if user_id > 0 => user_id,
        _ => {
            return error_response(
                StatusCode::UNAUTHORIZED,
                "Identitas pengguna pada token tidak valid",
            );
        }
    };
    let match_id = match find_match_id_by_tournament_and_team(
        &pool,
        actor_id,
        &payload.tournament_name,
        &payload.team_name,
    )
    .await
    {
        Ok(match_id) => match_id,
        Err(response) => return response,
    };

    set_match_result(
        State(pool),
        Extension(claims),
        Path(match_id),
        Json(SetMatchResultDto {
            winner_team_name: payload.winner_team_name,
        }),
    )
    .await
    .into_response()
}

pub async fn set_match_result(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Path(match_id): Path<i32>,
    Json(payload): Json<SetMatchResultDto>,
) -> impl IntoResponse {
    let actor_id = match claims.sub.parse::<i32>() {
        Ok(user_id) if user_id > 0 => user_id,
        _ => {
            return error_response(
                StatusCode::UNAUTHORIZED,
                "Identitas pengguna pada token tidak valid",
            );
        }
    };
    if match_id <= 0 || !valid_name(&payload.winner_team_name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "ID pertandingan harus positif dan nama tim pemenang wajib diisi",
        );
    }

    let result = sqlx::query("CALL pr_set_match_result($1, $2, $3)")
        .bind(actor_id)
        .bind(match_id)
        .bind(payload.winner_team_name)
        .execute(&pool)
        .await;

    match result {
        Ok(_) => message(StatusCode::OK, "Hasil pertandingan berhasil disimpan"),
        Err(error) => {
            let code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("set_match_result", error);
            match code.as_deref() {
                Some("42501") => error_response(
                    StatusCode::FORBIDDEN,
                    "Hanya admin yang dapat mengelola pertandingan",
                ),
                Some("P0002") => {
                    error_response(StatusCode::NOT_FOUND, "Pertandingan tidak ditemukan")
                }
                Some("22023") | Some("P0001") => error_response(
                    StatusCode::BAD_REQUEST,
                    "Tim pemenang harus merupakan tim yang bertanding",
                ),
                _ => error_response(
                    StatusCode::BAD_REQUEST,
                    "Gagal menyimpan hasil pertandingan",
                ),
            }
        }
    }
}

#[derive(Deserialize)]
pub struct UpdateScheduleDto {
    pub schedule_time: String,
}

pub async fn update_match_schedule_by_names(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Json(payload): Json<UpdateScheduleByNamesDto>,
) -> axum::response::Response {
    if !valid_name(&payload.tournament_name) || !valid_name(&payload.team_name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama turnamen dan tim yang bertanding wajib diisi",
        );
    }
    let actor_id = match claims.sub.parse::<i32>() {
        Ok(user_id) if user_id > 0 => user_id,
        _ => {
            return error_response(
                StatusCode::UNAUTHORIZED,
                "Identitas pengguna pada token tidak valid",
            );
        }
    };
    let match_id = match find_match_id_by_tournament_and_team(
        &pool,
        actor_id,
        &payload.tournament_name,
        &payload.team_name,
    )
    .await
    {
        Ok(match_id) => match_id,
        Err(response) => return response,
    };

    update_match_schedule(
        State(pool),
        Extension(claims),
        Path(match_id),
        Json(UpdateScheduleDto {
            schedule_time: payload.schedule_time,
        }),
    )
    .await
    .into_response()
}

pub async fn update_match_schedule(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Path(match_id): Path<i32>,
    Json(payload): Json<UpdateScheduleDto>,
) -> impl IntoResponse {
    let actor_id = match claims.sub.parse::<i32>() {
        Ok(user_id) if user_id > 0 => user_id,
        _ => {
            return error_response(
                StatusCode::UNAUTHORIZED,
                "Identitas pengguna pada token tidak valid",
            );
        }
    };
    if match_id <= 0 {
        return error_response(StatusCode::BAD_REQUEST, "ID pertandingan harus positif");
    }
    let schedule_time = match PrimitiveDateTime::parse(
        &payload.schedule_time,
        &time::macros::format_description!("[year]-[month]-[day] [hour]:[minute]:[second]"),
    ) {
        Ok(schedule_time) => schedule_time,
        Err(_) => {
            return error_response(
                StatusCode::BAD_REQUEST,
                "Format waktu harus YYYY-MM-DD HH:MM:SS",
            );
        }
    };

    let result = sqlx::query("CALL pr_update_match_schedule($1, $2, $3)")
        .bind(actor_id)
        .bind(match_id)
        .bind(schedule_time)
        .execute(&pool)
        .await;

    match result {
        Ok(_) => message(
            StatusCode::OK,
            "Jadwal pertandingan berhasil ditentukan/diperbarui!",
        ),
        Err(error) => {
            let forbidden = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .is_some_and(|code| code == "42501");
            log_error("update_match_schedule", error);
            if forbidden {
                error_response(
                    StatusCode::FORBIDDEN,
                    "Hanya admin yang dapat mengelola pertandingan",
                )
            } else {
                error_response(
                    StatusCode::BAD_REQUEST,
                    "Gagal memperbarui jadwal pertandingan",
                )
            }
        }
    }
}

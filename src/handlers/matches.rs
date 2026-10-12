use axum::{
    Extension, Json,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
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
    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("create_match_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi pembuatan pertandingan",
            );
        }
    };
    if let Err(error) = sqlx::query("CALL pr_create_match($1, $2, $3, $4, $5)")
        .bind(actor_id)
        .bind(payload.tournament_name)
        .bind(payload.team1_name)
        .bind(payload.team2_name)
        .bind(payload.round_number)
        .execute(&mut *transaction)
        .await
    {
        let forbidden = error
            .as_database_error()
            .and_then(|database_error| database_error.code())
            .is_some_and(|code| code == "42501");
        log_error("create_match", error);
        if let Err(rollback_error) = transaction.rollback().await {
            log_error("create_match_rollback", rollback_error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Pembuatan pertandingan gagal dan transaksi tidak dapat dibatalkan",
            );
        }
        return if forbidden {
            error_response(
                StatusCode::FORBIDDEN,
                "Hanya admin yang dapat mengelola pertandingan",
            )
        } else {
            error_response(StatusCode::BAD_REQUEST, "Gagal membuat pertandingan")
        };
    }
    if let Err(error) = transaction.commit().await {
        log_error("create_match_commit", error);
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            "Gagal menyimpan pertandingan",
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
    if tournament_id <= 0 {
        return error_response(StatusCode::BAD_REQUEST, "ID turnamen harus positif");
    }
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
        Err(error) => {
            log_error("get_tournament_matches", error);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil jadwal pertandingan")
        }
    }
}

#[derive(Deserialize)]
pub struct UpdateScheduleDto {
    pub schedule_time: String,
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

    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("update_match_schedule_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi pembaruan jadwal",
            );
        }
    };
    let result = sqlx::query("CALL pr_update_match_schedule($1, $2, $3)")
        .bind(actor_id)
        .bind(match_id)
        .bind(schedule_time)
        .execute(&mut *transaction)
        .await;

    match result {
        Ok(_) => match transaction.commit().await {
            Ok(()) => message(
                StatusCode::OK,
                "Jadwal pertandingan berhasil ditentukan/diperbarui!",
            ),
            Err(error) => {
                log_error("update_match_schedule_commit", error);
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Gagal menyimpan pembaruan jadwal",
                )
            }
        },
        Err(error) => {
            let forbidden = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .is_some_and(|code| code == "42501");
            log_error("update_match_schedule", error);
            if let Err(rollback_error) = transaction.rollback().await {
                log_error("update_match_schedule_rollback", rollback_error);
                return error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Pembaruan jadwal gagal dan transaksi tidak dapat dibatalkan",
                );
            }
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

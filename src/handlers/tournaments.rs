use axum::{
    Extension, Json,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::auth::Claims;

use super::response::{error_response, log_error, message};

fn valid_name(value: &str) -> bool {
    let value = value.trim();
    !value.is_empty() && value.chars().count() <= 100
}

fn valid_max_teams(max_teams: i32) -> bool {
    max_teams > 0
}

#[derive(Deserialize)]
pub struct CreateTournamentDto {
    pub name: String,
    pub max_teams: i32,
}

#[derive(Serialize, sqlx::FromRow)]
pub struct TournamentResponse {
    pub id: i32,
    pub name: String,
    pub status: Option<String>,
    pub total_slots: i32,
    pub available_slots: i32,
}

pub async fn create_tournament(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Json(payload): Json<CreateTournamentDto>,
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
    if !valid_name(&payload.name) || !valid_max_teams(payload.max_teams) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama turnamen wajib diisi (maksimal 100 karakter) dan max_teams harus lebih dari 0",
        );
    }
    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("create_tournament_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi pembuatan turnamen",
            );
        }
    };
    let tournament = match sqlx::query_as::<_, TournamentResponse>(
        "CALL pr_create_tournament($1, $2, $3, NULL, NULL, NULL, NULL, NULL)",
    )
    .bind(actor_id)
    .bind(payload.name.trim())
    .bind(payload.max_teams)
    .fetch_one(&mut *transaction)
    .await
    {
        Err(error) => {
            let duplicate = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .is_some_and(|code| code == "23505");
            let forbidden = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .is_some_and(|code| code == "42501");
            log_error("create_tournament", error);
            if let Err(rollback_error) = transaction.rollback().await {
                log_error("create_tournament_rollback", rollback_error);
                return error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Pembuatan turnamen gagal dan transaksi tidak dapat dibatalkan",
                );
            }
            return if forbidden {
                error_response(
                    StatusCode::FORBIDDEN,
                    "Hanya admin yang dapat mengelola turnamen",
                )
            } else if duplicate {
                error_response(StatusCode::CONFLICT, "Nama turnamen sudah digunakan")
            } else {
                error_response(StatusCode::BAD_REQUEST, "Gagal membuat turnamen")
            };
        }
        Ok(tournament) => tournament,
    };
    if let Err(error) = transaction.commit().await {
        log_error("create_tournament_commit", error);
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            "Gagal menyimpan turnamen",
        );
    }

    (
        StatusCode::CREATED,
        Json(serde_json::json!({"message": "Turnamen berhasil dibuat dan siap menerima pendaftaran!", "data": tournament})),
    ).into_response()
}

pub async fn get_tournaments(State(pool): State<PgPool>) -> impl IntoResponse {
    match sqlx::query_as::<_, TournamentResponse>(
        "SELECT id, name, status, total_slots, available_slots FROM vw_tournaments",
    )
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
    Extension(claims): Extension<Claims>,
    Json(payload): Json<RegisterTournamentDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.tournament_name) || !valid_name(&payload.team_name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama turnamen dan tim wajib diisi (maksimal 100 karakter)",
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

    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("register_tournament_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi pendaftaran",
            );
        }
    };

    let result = sqlx::query("CALL pr_register_team_to_tournament($1, $2, $3)")
        .bind(actor_id)
        .bind(&payload.tournament_name)
        .bind(&payload.team_name)
        .execute(&mut *transaction)
        .await;

    if let Err(error) = result {
        let database_code = error
            .as_database_error()
            .and_then(|database_error| database_error.code())
            .map(|code| code.into_owned());
        let duplicate = database_code.as_deref() == Some("23505");
        let full = database_code.as_deref() == Some("23514");
        let forbidden = database_code.as_deref() == Some("42501");
        let team_missing = database_code.as_deref() == Some("P0002");
        log_error("register_tournament", error);
        if let Err(rollback_error) = transaction.rollback().await {
            log_error("register_tournament_rollback", rollback_error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Pendaftaran gagal dan transaksi tidak dapat dibatalkan",
            );
        }
        return if forbidden {
            error_response(
                StatusCode::FORBIDDEN,
                "Hanya kapten tim yang dapat mendaftarkan tim ini",
            )
        } else if team_missing {
            error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan")
        } else if duplicate {
            error_response(
                StatusCode::CONFLICT,
                "Tim sudah terdaftar pada turnamen ini",
            )
        } else if full {
            error_response(StatusCode::CONFLICT, "Kuota tim turnamen sudah penuh")
        } else {
            error_response(
                StatusCode::BAD_REQUEST,
                "Gagal mendaftarkan tim ke turnamen",
            )
        };
    }

    match transaction.commit().await {
        Ok(()) => message(
            StatusCode::CREATED,
            "Tim berhasil didaftarkan ke turnamen dan siap bertanding!",
        ),
        Err(error) => {
            log_error("register_tournament_commit", error);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal menyimpan pendaftaran",
            )
        }
    }
}

pub async fn delete_tournament(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Path(tournament_name): Path<String>,
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
    if !valid_name(&tournament_name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama turnamen wajib diisi (maksimal 100 karakter)",
        );
    }
    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("delete_tournament_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi penghapusan turnamen",
            );
        }
    };
    match sqlx::query("CALL pr_delete_tournament($1, $2)")
        .bind(actor_id)
        .bind(tournament_name)
        .execute(&mut *transaction)
        .await
    {
        Ok(_) => match transaction.commit().await {
            Ok(()) => message(
                StatusCode::OK,
                "Turnamen beserta seluruh data pendaftarannya berhasil dihapus!",
            ),
            Err(error) => {
                log_error("delete_tournament_commit", error);
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Gagal menyimpan penghapusan turnamen",
                )
            }
        },
        Err(error) => {
            let database_code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("delete_tournament", error);
            if let Err(rollback_error) = transaction.rollback().await {
                log_error("delete_tournament_rollback", rollback_error);
                return error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Penghapusan turnamen gagal dan transaksi tidak dapat dibatalkan",
                );
            }
            if database_code.as_deref() == Some("42501") {
                error_response(
                    StatusCode::FORBIDDEN,
                    "Hanya admin yang dapat mengelola turnamen",
                )
            } else {
                error_response(StatusCode::NOT_FOUND, "Gagal menghapus turnamen")
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::valid_max_teams;

    #[test]
    fn tournament_capacity_must_be_positive() {
        assert!(valid_max_teams(1));
        assert!(valid_max_teams(i32::MAX));
        assert!(!valid_max_teams(0));
        assert!(!valid_max_teams(-1));
    }
}

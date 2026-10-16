use axum::{
    Extension, Json,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use sqlx::Row;

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
    let tournament = match sqlx::query_as::<_, TournamentResponse>(
        "CALL pr_create_tournament($1, $2, $3, NULL, NULL, NULL, NULL, NULL)",
    )
    .bind(actor_id)
    .bind(payload.name.trim())
    .bind(payload.max_teams)
    .fetch_one(&pool)
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

    (
        StatusCode::CREATED,
        Json(serde_json::json!({"message": "Turnamen berhasil dibuat dan siap menerima pendaftaran!", "data": tournament})),
    ).into_response()
}

pub async fn get_tournaments(State(pool): State<PgPool>) -> impl IntoResponse {
    let mut tx = match pool.begin().await {
        Ok(tx) => tx,
        Err(error) => {
            log_error("get_tournaments_begin", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil data turnamen");
        }
    };

    if let Err(error) = sqlx::query("CALL pr_get_tournaments('tournaments_cursor')")
        .execute(&mut *tx)
        .await
    {
        log_error("get_tournaments_call", error);
        return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil data turnamen");
    }

    let rows = match sqlx::query("FETCH ALL FROM tournaments_cursor")
        .fetch_all(&mut *tx)
        .await
    {
        Ok(rows) => rows,
        Err(error) => {
            log_error("get_tournaments_fetch", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil data turnamen");
        }
    };

    let _ = tx.commit().await;

    let tournaments: Vec<TournamentResponse> = rows
        .into_iter()
        .map(|row| TournamentResponse {
            id: row.get("id"),
            name: row.get("name"),
            status: row.get("status"),
            total_slots: row.get("total_slots"),
            available_slots: row.get("available_slots"),
        })
        .collect();

    (
        StatusCode::OK,
        Json(serde_json::json!({"message": "Berhasil mengambil daftar turnamen", "data": tournaments})),
    ).into_response()
}

#[derive(Serialize, sqlx::FromRow)]
pub struct TournamentTeamResponse {
    pub team_id: i32,
    pub team_name: String,
    pub captain_id: Option<i32>,
    pub captain_username: Option<String>,
    pub registered_at: String,
}

pub async fn get_tournament_teams(
    State(pool): State<PgPool>,
    Path(tournament_id): Path<i32>,
) -> impl IntoResponse {
    if tournament_id <= 0 {
        return error_response(StatusCode::BAD_REQUEST, "ID turnamen harus positif");
    }

    let mut tx = match pool.begin().await {
        Ok(tx) => tx,
        Err(error) => {
            log_error("get_tournament_teams_begin", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil daftar tim turnamen");
        }
    };

    if let Err(error) = sqlx::query(
        "CALL pr_get_tournament_teams($1, 'tournament_teams_cursor')",
    )
    .bind(tournament_id)
    .execute(&mut *tx)
    .await
    {
        let not_found = error
            .as_database_error()
            .and_then(|e| e.code())
            .is_some_and(|code| code == "P0002");
        if !not_found {
            log_error("get_tournament_teams_call", error);
        }
        let _ = tx.rollback().await;
        return if not_found {
            error_response(StatusCode::NOT_FOUND, "Turnamen tidak ditemukan")
        } else {
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil daftar tim turnamen")
        };
    }

    let rows = match sqlx::query("FETCH ALL FROM tournament_teams_cursor")
        .fetch_all(&mut *tx)
        .await
    {
        Ok(rows) => rows,
        Err(error) => {
            log_error("get_tournament_teams_fetch", error);
            let _ = tx.rollback().await;
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil daftar tim turnamen");
        }
    };

    let _ = tx.commit().await;

    let teams: Vec<TournamentTeamResponse> = rows
        .into_iter()
        .map(|row| TournamentTeamResponse {
            team_id: row.get("team_id"),
            team_name: row.get("team_name"),
            captain_id: row.get("captain_id"),
            captain_username: row.get("captain_username"),
            registered_at: row.get("registered_at"),
        })
        .collect();

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "message": "Berhasil mengambil daftar tim turnamen",
            "data": teams
        })),
    )
        .into_response()
}

pub async fn get_tournament_teams_by_name(
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
        Ok((tournament_id,)) => get_tournament_teams(State(pool), Path(tournament_id))
            .await
            .into_response(),
        Err(error) => {
            let not_found = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .is_some_and(|code| code == "P0001");
            log_error("get_tournament_id_for_teams", error);
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

    let result = sqlx::query("CALL pr_register_team_to_tournament($1, $2, $3)")
        .bind(actor_id)
        .bind(&payload.tournament_name)
        .bind(&payload.team_name)
        .execute(&pool)
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

    message(
        StatusCode::CREATED,
        "Tim berhasil didaftarkan ke turnamen dan siap bertanding!",
    )
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
    match sqlx::query("CALL pr_delete_tournament($1, $2)")
        .bind(actor_id)
        .bind(tournament_name)
        .execute(&pool)
        .await
    {
        Ok(_) => message(
            StatusCode::OK,
            "Turnamen beserta seluruh data pendaftarannya berhasil dihapus!",
        ),
        Err(error) => {
            let database_code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("delete_tournament", error);
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

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

#[derive(Serialize, sqlx::FromRow)]
pub struct TeamSummary {
    pub id: i32,
    pub name: String,
    pub captain_id: Option<i32>,
    pub captain_username: Option<String>,
    pub member_count: i32,
}

pub async fn get_teams(State(pool): State<PgPool>) -> impl IntoResponse {
    let mut tx = match pool.begin().await {
        Ok(tx) => tx,
        Err(error) => {
            log_error("get_teams_begin", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil daftar tim");
        }
    };

    if let Err(error) = sqlx::query("CALL pr_get_teams('teams_cursor')")
        .execute(&mut *tx)
        .await
    {
        log_error("get_teams_call", error);
        return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil daftar tim");
    }

    let rows = match sqlx::query("FETCH ALL FROM teams_cursor")
        .fetch_all(&mut *tx)
        .await
    {
        Ok(rows) => rows,
        Err(error) => {
            log_error("get_teams_fetch", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil daftar tim");
        }
    };

    let _ = tx.commit().await;

    let teams: Vec<TeamSummary> = rows
        .into_iter()
        .map(|row| TeamSummary {
            id: row.get("id"),
            name: row.get("name"),
            captain_id: row.get("captain_id"),
            captain_username: row.get("captain_username"),
            member_count: row.get("member_count"),
        })
        .collect();

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "message": "Berhasil mengambil daftar tim",
            "data": teams
        })),
    )
        .into_response()
}

#[derive(Deserialize)]
pub struct CreateTeamDto {
    pub name: String,
    pub captain_username: String,
}

#[derive(Serialize, sqlx::FromRow)]
pub struct TeamResponse {
    pub id: i32,
    pub name: String,
    pub captain_id: Option<i32>,
}

pub async fn create_team(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Json(payload): Json<CreateTeamDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.name) || !valid_name(&payload.captain_username) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim dan username kapten wajib diisi (maksimal 100 karakter)",
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
    let team = match sqlx::query_as::<_, TeamResponse>(
        "CALL pr_create_team($1, $2, $3, NULL, NULL, NULL)",
    )
    .bind(actor_id)
    .bind(payload.name)
    .bind(payload.captain_username)
    .fetch_one(&pool)
    .await
    {
        Ok(team) => team,
        Err(error) => {
            let forbidden = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .is_some_and(|code| code == "42501");
            log_error("create_team", error);
            return if forbidden {
                error_response(
                    StatusCode::FORBIDDEN,
                    "Kapten tim harus merupakan pengguna yang sedang login",
                )
            } else {
                error_response(StatusCode::BAD_REQUEST, "Gagal membuat tim")
            };
        }
    };
    (
        StatusCode::CREATED,
        Json(serde_json::json!({
            "message": "Tim berhasil dibuat dan kapten otomatis terdaftar di roster!",
            "data": team
        })),
    )
        .into_response()
}

#[derive(Deserialize)]
pub struct JoinTeamDto {
    pub team_name: String,
}

pub async fn join_team(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Json(payload): Json<JoinTeamDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.team_name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim wajib diisi (maksimal 100 karakter)",
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
    let result = sqlx::query("CALL pr_add_team_member($1, $2)")
        .bind(actor_id)
        .bind(payload.team_name)
        .execute(&pool)
        .await;

    match result {
        Ok(_) => message(
            StatusCode::CREATED,
            "Player berhasil bergabung ke dalam tim!",
        ),
        Err(error) => {
            let database_code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            let forbidden = database_code.as_deref() == Some("42501");
            let already_member = database_code.as_deref() == Some("23505");
            if !forbidden && !already_member {
                log_error("join_team", error);
            }
            if forbidden {
                error_response(StatusCode::FORBIDDEN, "Pengguna pada token tidak valid")
            } else if already_member {
                error_response(StatusCode::CONFLICT, "Kamu sudah menjadi anggota tim ini")
            } else {
                error_response(StatusCode::BAD_REQUEST, "Gagal menambahkan anggota ke tim")
            }
        }
    }
}

#[derive(Deserialize)]
pub struct LeaveTeamDto {
    pub team_name: String,
    pub new_captain_username: Option<String>,
}

pub async fn leave_team(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Json(payload): Json<LeaveTeamDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.team_name)
        || payload
            .new_captain_username
            .as_deref()
            .is_some_and(|username| !valid_name(username))
    {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim dan username kapten pengganti harus valid",
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
    let result = sqlx::query("CALL pr_leave_team($1, $2, $3)")
        .bind(actor_id)
        .bind(payload.team_name)
        .bind(payload.new_captain_username)
        .execute(&pool)
        .await;

    match result {
        Ok(_) => message(StatusCode::OK, "Berhasil keluar dari tim"),
        Err(error) => {
            let code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("leave_team", error);
            match code.as_deref() {
                Some("P0002") => error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan"),
                Some("P0001") => {
                    error_response(StatusCode::CONFLICT, "Kamu bukan anggota tim tersebut")
                }
                Some("23514") => error_response(
                    StatusCode::BAD_REQUEST,
                    "Kapten harus memilih anggota tim lain sebagai pengganti",
                ),
                _ => error_response(StatusCode::BAD_REQUEST, "Gagal keluar dari tim"),
            }
        }
    }
}

#[derive(Deserialize)]
pub struct DeleteTeamDto {
    pub team_name: String,
}

pub async fn delete_team(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Json(payload): Json<DeleteTeamDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.team_name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim wajib diisi (maksimal 100 karakter)",
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
    let result = sqlx::query("CALL pr_delete_team($1, $2)")
        .bind(actor_id)
        .bind(payload.team_name)
        .execute(&pool)
        .await;

    match result {
        Ok(_) => message(
            StatusCode::OK,
            "Tim dan data pendaftarannya berhasil dihapus",
        ),
        Err(error) => {
            let code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("delete_team", error);
            match code.as_deref() {
                Some("42501") => error_response(
                    StatusCode::FORBIDDEN,
                    "Hanya kapten tim yang dapat menghapus tim",
                ),
                Some("P0002") => error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan"),
                _ => error_response(StatusCode::BAD_REQUEST, "Gagal menghapus tim"),
            }
        }
    }
}

#[derive(Serialize)]
pub struct TeamMemberInfo {
    pub username: String,
    pub status: Option<String>,
}

#[derive(Serialize)]
pub struct TeamProfileResponse {
    pub id: i32,
    pub name: String,
    pub captain_id: Option<i32>,
    pub members: Vec<TeamMemberInfo>,
}

pub async fn get_team_profile(
    State(pool): State<PgPool>,
    Path(team_id): Path<i32>,
) -> impl IntoResponse {
    if team_id <= 0 {
        return error_response(StatusCode::BAD_REQUEST, "ID tim harus positif");
    }

    let mut tx = match pool.begin().await {
        Ok(tx) => tx,
        Err(error) => {
            log_error("get_team_profile_begin", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil profil tim");
        }
    };

    if let Err(error) = sqlx::query(
        "CALL pr_get_team_profile($1, 'team_cursor', 'member_cursor')",
    )
    .bind(team_id)
    .execute(&mut *tx)
    .await
    {
        let not_found = error
            .as_database_error()
            .and_then(|e| e.code())
            .is_some_and(|code| code == "P0002");
        if !not_found {
            log_error("get_team_profile_call", error);
        }
        let _ = tx.rollback().await;
        return if not_found {
            error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan")
        } else {
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil profil tim")
        };
    }

    let team_row = match sqlx::query("FETCH ALL FROM team_cursor")
        .fetch_optional(&mut *tx)
        .await
    {
        Ok(Some(row)) => row,
        Ok(None) => {
            let _ = tx.rollback().await;
            return error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan");
        }
        Err(error) => {
            log_error("get_team_profile_fetch_team", error);
            let _ = tx.rollback().await;
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil profil tim");
        }
    };

    let member_rows = match sqlx::query("FETCH ALL FROM member_cursor")
        .fetch_all(&mut *tx)
        .await
    {
        Ok(rows) => rows,
        Err(error) => {
            log_error("get_team_profile_fetch_members", error);
            let _ = tx.rollback().await;
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil anggota tim");
        }
    };

    let _ = tx.commit().await;

    let members: Vec<TeamMemberInfo> = member_rows
        .into_iter()
        .map(|row| TeamMemberInfo {
            username: row.get("username"),
            status: row.get("status"),
        })
        .collect();

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "message": "Berhasil mengambil profil tim",
            "data": TeamProfileResponse {
                id: team_row.get("id"),
                name: team_row.get("name"),
                captain_id: team_row.get("captain_id"),
                members
            }
        })),
    )
        .into_response()
}

pub async fn get_team_profile_by_name(
    State(pool): State<PgPool>,
    Path(team_name): Path<String>,
) -> axum::response::Response {
    if !valid_name(&team_name) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim wajib diisi (maksimal 100 karakter)",
        );
    }

    match sqlx::query_as::<_, (i32,)>("CALL pr_get_team_id_by_name($1, NULL)")
        .bind(&team_name)
        .fetch_one(&pool)
        .await
    {
        Ok((team_id,)) => get_team_profile(State(pool), Path(team_id))
            .await
            .into_response(),
        Err(error) => {
            let not_found = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .is_some_and(|code| code == "P0001");
            log_error("get_team_id_by_name", error);
            if not_found {
                error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan")
            } else {
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Gagal mencari tim berdasarkan nama",
                )
            }
        }
    }
}

#[derive(Deserialize)]
pub struct RemoveMemberDto {
    pub team_name: String,
    pub username: String,
}

pub async fn remove_team_member(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Json(payload): Json<RemoveMemberDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.team_name) || !valid_name(&payload.username) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim dan username wajib diisi (maksimal 100 karakter)",
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
    let result = sqlx::query("CALL pr_remove_team_member($1, $2, $3)")
        .bind(actor_id)
        .bind(payload.team_name)
        .bind(payload.username)
        .execute(&pool)
        .await;

    match result {
        Ok(_) => message(StatusCode::OK, "Player berhasil keluar/dihapus dari tim!"),
        Err(error) => {
            let database_code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("remove_team_member", error);
            if database_code.as_deref() == Some("42501") {
                error_response(
                    StatusCode::FORBIDDEN,
                    "Hanya kapten tim yang dapat menghapus anggota",
                )
            } else if database_code.as_deref() == Some("P0002") {
                error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan")
            } else {
                error_response(StatusCode::BAD_REQUEST, "Gagal menghapus anggota tim")
            }
        }
    }
}

#[derive(Deserialize)]
pub struct TransferCaptainDto {
    pub team_name: String,
    pub new_captain_username: String,
}

pub async fn transfer_captain(
    State(pool): State<PgPool>,
    Extension(claims): Extension<Claims>,
    Json(payload): Json<TransferCaptainDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.team_name) || !valid_name(&payload.new_captain_username) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim dan username kapten baru wajib diisi (maksimal 100 karakter)",
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
    let result = sqlx::query("CALL pr_transfer_captain($1, $2, $3)")
        .bind(actor_id)
        .bind(payload.team_name)
        .bind(payload.new_captain_username)
        .execute(&pool)
        .await;

    match result {
        Ok(_) => message(
            StatusCode::OK,
            "Jabatan ketua tim berhasil dipindahkan ke player baru!",
        ),
        Err(error) => {
            let database_code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("transfer_captain", error);
            if database_code.as_deref() == Some("42501") {
                error_response(
                    StatusCode::FORBIDDEN,
                    "Hanya kapten tim yang dapat memindahkan jabatan kapten",
                )
            } else if database_code.as_deref() == Some("P0002") {
                error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan")
            } else {
                error_response(StatusCode::BAD_REQUEST, "Gagal memindahkan kapten tim")
            }
        }
    }
}

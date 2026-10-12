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

#[derive(Serialize, sqlx::FromRow)]
pub struct TeamSummary {
    pub id: i32,
    pub name: String,
    pub captain_id: Option<i32>,
    pub captain_username: Option<String>,
    pub member_count: i32,
}

pub async fn get_teams(State(pool): State<PgPool>) -> impl IntoResponse {
    match sqlx::query_as::<_, TeamSummary>(
        "SELECT id, name, captain_id, captain_username, member_count FROM vw_teams ORDER BY name, id",
    )
    .fetch_all(&pool)
    .await
    {
        Ok(teams) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "message": "Berhasil mengambil daftar tim",
                "data": teams
            })),
        )
            .into_response(),
        Err(error) => {
            log_error("get_teams", error);
            error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil daftar tim")
        }
    }
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
    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("create_team_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi pembuatan tim",
            );
        }
    };
    let team = match sqlx::query_as::<_, TeamResponse>(
        "CALL pr_create_team($1, $2, $3, NULL, NULL, NULL)",
    )
    .bind(actor_id)
    .bind(payload.name)
    .bind(payload.captain_username)
    .fetch_one(&mut *transaction)
    .await
    {
        Ok(team) => team,
        Err(error) => {
            let forbidden = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .is_some_and(|code| code == "42501");
            log_error("create_team", error);
            if let Err(rollback_error) = transaction.rollback().await {
                log_error("create_team_rollback", rollback_error);
                return error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Pembuatan tim gagal dan transaksi tidak dapat dibatalkan",
                );
            }
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
    if let Err(error) = transaction.commit().await {
        log_error("create_team_commit", error);
        return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal menyimpan tim");
    }

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
    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("join_team_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi penambahan anggota",
            );
        }
    };
    let result = sqlx::query("CALL pr_add_team_member($1, $2)")
        .bind(actor_id)
        .bind(payload.team_name)
        .execute(&mut *transaction)
        .await;

    match result {
        Ok(_) => match transaction.commit().await {
            Ok(()) => message(
                StatusCode::CREATED,
                "Player berhasil bergabung ke dalam tim!",
            ),
            Err(error) => {
                log_error("join_team_commit", error);
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Gagal menyimpan penambahan anggota",
                )
            }
        },
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
            if let Err(rollback_error) = transaction.rollback().await {
                log_error("join_team_rollback", rollback_error);
                return error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Penambahan anggota gagal dan transaksi tidak dapat dibatalkan",
                );
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
    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("leave_team_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi keluar tim",
            );
        }
    };
    let result = sqlx::query("CALL pr_leave_team($1, $2, $3)")
        .bind(actor_id)
        .bind(payload.team_name)
        .bind(payload.new_captain_username)
        .execute(&mut *transaction)
        .await;

    match result {
        Ok(_) => match transaction.commit().await {
            Ok(()) => message(StatusCode::OK, "Berhasil keluar dari tim"),
            Err(error) => {
                log_error("leave_team_commit", error);
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Gagal menyimpan perubahan keluar tim",
                )
            }
        },
        Err(error) => {
            let code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("leave_team", error);
            if let Err(rollback_error) = transaction.rollback().await {
                log_error("leave_team_rollback", rollback_error);
                return error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Keluar tim gagal dan transaksi tidak dapat dibatalkan",
                );
            }
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
    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("delete_team_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi penghapusan tim",
            );
        }
    };
    let result = sqlx::query("CALL pr_delete_team($1, $2)")
        .bind(actor_id)
        .bind(payload.team_name)
        .execute(&mut *transaction)
        .await;

    match result {
        Ok(_) => match transaction.commit().await {
            Ok(()) => message(
                StatusCode::OK,
                "Tim dan data pendaftarannya berhasil dihapus",
            ),
            Err(error) => {
                log_error("delete_team_commit", error);
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Gagal menyimpan penghapusan tim",
                )
            }
        },
        Err(error) => {
            let code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("delete_team", error);
            if let Err(rollback_error) = transaction.rollback().await {
                log_error("delete_team_rollback", rollback_error);
                return error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Penghapusan tim gagal dan transaksi tidak dapat dibatalkan",
                );
            }
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
    let team = match sqlx::query!(
        "SELECT team_id AS \"id!\", team_name AS \"name!\", captain_id FROM vw_team_members WHERE team_id = $1 LIMIT 1",
        team_id
    )
    .fetch_optional(&pool)
    .await
    {
        Ok(Some(team)) => team,
        Ok(None) => return error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan"),
        Err(error) => {
            log_error("get_team_profile", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil profil tim");
        }
    };

    let members = match sqlx::query_as!(
        TeamMemberInfo,
        "SELECT username AS \"username!\", status FROM vw_team_members WHERE team_id = $1 AND user_id IS NOT NULL",
        team_id
    )
    .fetch_all(&pool)
    .await
    {
        Ok(members) => members,
        Err(error) => {
            log_error("get_team_members", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal mengambil anggota tim");
        }
    };

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "message": "Berhasil mengambil profil tim",
            "data": TeamProfileResponse { id: team.id, name: team.name, captain_id: team.captain_id, members }
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
    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("remove_team_member_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi penghapusan anggota",
            );
        }
    };
    let result = sqlx::query("CALL pr_remove_team_member($1, $2, $3)")
        .bind(actor_id)
        .bind(payload.team_name)
        .bind(payload.username)
        .execute(&mut *transaction)
        .await;

    match result {
        Ok(_) => match transaction.commit().await {
            Ok(()) => message(StatusCode::OK, "Player berhasil keluar/dihapus dari tim!"),
            Err(error) => {
                log_error("remove_team_member_commit", error);
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Gagal menyimpan penghapusan anggota",
                )
            }
        },
        Err(error) => {
            let database_code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("remove_team_member", error);
            if let Err(rollback_error) = transaction.rollback().await {
                log_error("remove_team_member_rollback", rollback_error);
                return error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Penghapusan anggota gagal dan transaksi tidak dapat dibatalkan",
                );
            }
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
    let mut transaction = match pool.begin().await {
        Ok(transaction) => transaction,
        Err(error) => {
            log_error("transfer_captain_begin_transaction", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal memulai transaksi perpindahan kapten",
            );
        }
    };
    let result = sqlx::query("CALL pr_transfer_captain($1, $2, $3)")
        .bind(actor_id)
        .bind(payload.team_name)
        .bind(payload.new_captain_username)
        .execute(&mut *transaction)
        .await;

    match result {
        Ok(_) => match transaction.commit().await {
            Ok(()) => message(
                StatusCode::OK,
                "Jabatan ketua tim berhasil dipindahkan ke player baru!",
            ),
            Err(error) => {
                log_error("transfer_captain_commit", error);
                error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Gagal menyimpan perpindahan kapten",
                )
            }
        },
        Err(error) => {
            let database_code = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .map(|code| code.into_owned());
            log_error("transfer_captain", error);
            if let Err(rollback_error) = transaction.rollback().await {
                log_error("transfer_captain_rollback", rollback_error);
                return error_response(
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Perpindahan kapten gagal dan transaksi tidak dapat dibatalkan",
                );
            }
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

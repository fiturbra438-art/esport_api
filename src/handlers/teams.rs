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
    Json(payload): Json<CreateTeamDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.name) || !valid_name(&payload.captain_username) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim dan username kapten wajib diisi (maksimal 100 karakter)",
        );
    }
    let team =
        match sqlx::query_as::<_, TeamResponse>("CALL pr_create_team($1, $2, NULL, NULL, NULL)")
            .bind(payload.name)
            .bind(payload.captain_username)
            .fetch_one(&pool)
            .await
        {
            Ok(team) => team,
            Err(error) => {
                log_error("create_team", error);
                return error_response(StatusCode::BAD_REQUEST, "Gagal membuat tim");
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
    pub username: String,
}

pub async fn join_team(
    State(pool): State<PgPool>,
    Json(payload): Json<JoinTeamDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.team_name) || !valid_name(&payload.username) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim dan username wajib diisi (maksimal 100 karakter)",
        );
    }
    let result = sqlx::query("CALL pr_add_team_member($1, $2)")
        .bind(payload.team_name)
        .bind(payload.username)
        .execute(&pool)
        .await;

    match result {
        Ok(_) => message(
            StatusCode::CREATED,
            "Player berhasil bergabung ke dalam tim!",
        ),
        Err(error) => {
            log_error("join_team", error);
            error_response(StatusCode::BAD_REQUEST, "Gagal menambahkan anggota ke tim")
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

#[derive(Deserialize)]
pub struct RemoveMemberDto {
    pub team_name: String,
    pub username: String,
}

pub async fn remove_team_member(
    State(pool): State<PgPool>,
    Json(payload): Json<RemoveMemberDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.team_name) || !valid_name(&payload.username) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim dan username wajib diisi (maksimal 100 karakter)",
        );
    }
    let result = sqlx::query("CALL pr_remove_team_member($1, $2)")
        .bind(payload.team_name)
        .bind(payload.username)
        .execute(&pool)
        .await;

    match result {
        Ok(_) => message(StatusCode::OK, "Player berhasil keluar/dihapus dari tim!"),
        Err(error) => {
            log_error("remove_team_member", error);
            error_response(StatusCode::BAD_REQUEST, "Gagal menghapus anggota tim")
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
    Json(payload): Json<TransferCaptainDto>,
) -> impl IntoResponse {
    if !valid_name(&payload.team_name) || !valid_name(&payload.new_captain_username) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "Nama tim dan username kapten baru wajib diisi (maksimal 100 karakter)",
        );
    }
    let result = sqlx::query("CALL pr_transfer_captain($1, $2)")
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
            log_error("transfer_captain", error);
            error_response(StatusCode::BAD_REQUEST, "Gagal memindahkan kapten tim")
        }
    }
}

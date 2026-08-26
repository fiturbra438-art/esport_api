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
pub struct CreateTeamDto {
    pub name: String,
    pub captain_id: i32,
}

#[derive(Serialize)]
pub struct TeamResponse {
    pub id: i32,
    pub name: String,
    pub captain_id: i32,
}

pub async fn create_team(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateTeamDto>,
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

    let team = match sqlx::query_as!(
        TeamResponse,
        "INSERT INTO teams (name, captain_id) VALUES ($1, $2) RETURNING id, name, captain_id",
        payload.name,
        payload.captain_id
    )
    .fetch_one(&mut *transaction)
    .await
    {
        Ok(team) => team,
        Err(error) => {
            return error_response(
                StatusCode::BAD_REQUEST,
                format!("Gagal membuat tim (mungkin nama tim sudah dipakai): {error}"),
            );
        }
    };

    if let Err(error) = sqlx::query!(
        "INSERT INTO team_members (team_id, user_id, status) VALUES ($1, $2, 'active')",
        team.id,
        team.captain_id
    )
    .execute(&mut *transaction)
    .await
    {
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Gagal memasukkan kapten ke roster: {error}"),
        );
    }

    if let Err(error) = transaction.commit().await {
        return error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Gagal commit transaksi: {error}"),
        );
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
    pub team_id: i32,
    pub user_id: i32,
}

pub async fn join_team(
    State(pool): State<PgPool>,
    Json(payload): Json<JoinTeamDto>,
) -> impl IntoResponse {
    match sqlx::query!(
        "INSERT INTO team_members (team_id, user_id, status) VALUES ($1, $2, 'active')",
        payload.team_id,
        payload.user_id
    )
    .execute(&pool)
    .await
    {
        Ok(_) => message(
            StatusCode::CREATED,
            "Player berhasil bergabung ke dalam tim!",
        ),
        Err(error) => error_response(
            StatusCode::BAD_REQUEST,
            format!("Gagal bergabung, mungkin player sudah ada di tim ini. Detail: {error}"),
        ),
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
    pub captain_id: i32,
    pub members: Vec<TeamMemberInfo>,
}

pub async fn get_team_profile(
    State(pool): State<PgPool>,
    Path(team_id): Path<i32>,
) -> impl IntoResponse {
    let team = match sqlx::query!(
        "SELECT id, name, captain_id FROM teams WHERE id = $1",
        team_id
    )
    .fetch_optional(&pool)
    .await
    {
        Ok(Some(team)) => team,
        Ok(None) => return error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan"),
        Err(error) => {
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Database error: {error}"),
            );
        }
    };

    let members = match sqlx::query_as!(
        TeamMemberInfo,
        "SELECT users.username, team_members.status FROM team_members JOIN users ON team_members.user_id = users.id WHERE team_members.team_id = $1",
        team_id
    )
    .fetch_all(&pool)
    .await
    {
        Ok(members) => members,
        Err(error) => return error_response(StatusCode::INTERNAL_SERVER_ERROR, format!("Gagal mengambil anggota tim: {error}")),
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
    pub team_id: i32,
    pub user_id: i32,
}

pub async fn remove_team_member(
    State(pool): State<PgPool>,
    Json(payload): Json<RemoveMemberDto>,
) -> impl IntoResponse {
    match sqlx::query!(
        "DELETE FROM team_members WHERE team_id = $1 AND user_id = $2",
        payload.team_id,
        payload.user_id
    )
    .execute(&pool)
    .await
    {
        Ok(result) if result.rows_affected() > 0 => {
            message(StatusCode::OK, "Player berhasil keluar/dihapus dari tim!")
        }
        Ok(_) => error_response(
            StatusCode::NOT_FOUND,
            "Player tidak ditemukan di dalam tim tersebut.",
        ),
        Err(error) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Gagal memproses request: {error}"),
        ),
    }
}

#[derive(Deserialize)]
pub struct TransferCaptainDto {
    pub team_id: i32,
    pub new_captain_id: i32,
}

pub async fn transfer_captain(
    State(pool): State<PgPool>,
    Json(payload): Json<TransferCaptainDto>,
) -> impl IntoResponse {
    match sqlx::query!(
        "UPDATE teams SET captain_id = $1 WHERE id = $2",
        payload.new_captain_id,
        payload.team_id
    )
    .execute(&pool)
    .await
    {
        Ok(result) if result.rows_affected() > 0 => message(
            StatusCode::OK,
            "Jabatan ketua tim berhasil dipindahkan ke player baru!",
        ),
        Ok(_) => error_response(StatusCode::NOT_FOUND, "Tim tidak ditemukan."),
        Err(error) => error_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Gagal memindahkan ketua tim: {error}"),
        ),
    }
}

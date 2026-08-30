use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

#[derive(Deserialize)]
pub struct CreateUserDto {
    pub username: String,
    pub password: String,
    pub mmr_point: Option<i32>,
}

#[derive(Serialize)]
pub struct UserResponse {
    pub id: i32,
    pub username: String,
    pub password: Option<String>,
    pub mmr_point: Option<i32>,
}

pub async fn register_user(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateUserDto>,
) -> impl IntoResponse {
    println!(
        "📥 Ada pendaftar baru! Username: {}, Password: {}, MMR: {}",
        payload.username,
        payload.password,
        payload.mmr_point.unwrap_or(0)
    );
    let result = sqlx::query_as!(
        UserResponse,
        "INSERT INTO users (username, password, mmr_point) VALUES ($1, $2, $3) RETURNING id, username, password, mmr_point",
        payload.username,
        payload.password,
        payload.mmr_point.unwrap_or(0)
    )
    .fetch_one(&pool)
    .await;

    match result {
        Ok(user) => (
            StatusCode::CREATED,
            Json(serde_json::json!({
                "message": "Registrasi user berhasil!",
                "data": user
            })),
        )
            .into_response(),
        Err(error) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({
                "error": format!("Gagal mendaftarkan user: {error}")
            })),
        )
            .into_response(),
    }
}

#[derive(Serialize)]
pub struct UserProfileResponse {
    pub id: i32,
    pub username: String,
    pub mmr_point: Option<i32>,
}

pub async fn get_user_profile(
    State(pool): State<PgPool>,
    Path(user_id): Path<i32>,
) -> impl IntoResponse {
    match sqlx::query_as!(
        UserProfileResponse,
        "SELECT id, username, mmr_point FROM users WHERE id = $1",
        user_id
    )
    .fetch_optional(&pool)
    .await
    {
        Ok(Some(user)) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "message": "Berhasil mengambil profil player",
                "data": user
            })),
        )
            .into_response(),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "Player tidak ditemukan"})),
        )
            .into_response(),
        Err(error) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {error}")})),
        )
            .into_response(),
    }
}

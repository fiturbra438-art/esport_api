use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

// Struct untuk menerima data JSON dari client (request body)
#[derive(Deserialize)]
pub struct CreateUserDto {
    pub username: String,
}

// Struct untuk format data yang dikembalikan ke client (response body)
#[derive(Serialize)]
pub struct UserResponse {
    pub id: i32,
    pub username: String,
    pub mmr_point: Option<i32>,
}

// Fungsi Handler untuk registrasi user baru
pub async fn register_user(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateUserDto>,
) -> impl IntoResponse {
    // Menjalankan query SQL untuk memasukkan data user baru
    let result = sqlx::query_as!(
        UserResponse,
        r#"
        INSERT INTO users (username) 
        VALUES ($1) 
        RETURNING id, username, mmr_point
        "#,
        payload.username
    )
    .fetch_one(&pool)
    .await;

    match result {
        Ok(user) => (StatusCode::CREATED, Json(serde_json::json!({
            "message": "Registrasi user berhasil!",
            "data": user
        }))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({
            "error": format!("Gagal mendaftarkan user: {}", e)
        }))).into_response(),
    }
}
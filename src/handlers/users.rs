use argon2::password_hash::{PasswordHash, PasswordVerifier};
use argon2::{
    Argon2,
    password_hash::{PasswordHasher, SaltString, rand_core::OsRng},
};
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::auth::JwtConfig;

use super::response::{error_response, log_error};

#[derive(Deserialize)]
pub struct CreateUserDto {
    pub username: String,
    pub password: String,
    pub mmr_point: Option<i32>,
}

#[derive(Serialize, sqlx::FromRow)]
pub struct UserResponse {
    pub id: i32,
    pub username: String,
    pub mmr_point: Option<i32>,
}

fn hash_password(password: &str) -> Result<String, argon2::password_hash::Error> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|hash| hash.to_string())
}

pub(crate) fn validate_username(username: &str) -> Result<(), &'static str> {
    if !(3..=32).contains(&username.len())
        || !username
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-')
    {
        return Err("Username harus 3-32 karakter dan hanya berisi huruf, angka, _ atau -");
    }
    Ok(())
}

pub(crate) fn validate_password(password: &str) -> Result<(), &'static str> {
    if !(12..=128).contains(&password.len()) {
        return Err("Password harus memiliki panjang 12-128 byte");
    }
    Ok(())
}

pub async fn register_user(
    State(pool): State<PgPool>,
    Json(payload): Json<CreateUserDto>,
) -> impl IntoResponse {
    let CreateUserDto {
        username,
        password,
        mmr_point,
    } = payload;

    if let Err(error) = validate_username(&username) {
        return error_response(StatusCode::BAD_REQUEST, error);
    }
    if let Err(error) = validate_password(&password) {
        return error_response(StatusCode::BAD_REQUEST, error);
    }
    if mmr_point.is_some_and(|mmr| !(0..=100_000).contains(&mmr)) {
        return error_response(
            StatusCode::BAD_REQUEST,
            "MMR harus berada di antara 0 dan 100000",
        );
    }

    let password = match tokio::task::spawn_blocking(move || hash_password(&password)).await {
        Ok(Ok(password_hash)) => password_hash,
        Ok(Err(error)) => {
            log_error("password_hash", error);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Gagal mengamankan password"})),
            )
                .into_response();
        }
        Err(error) => {
            log_error("password_hash_task", error);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Gagal mengamankan password"})),
            )
                .into_response();
        }
    };

    let result =
        sqlx::query_as::<_, UserResponse>("CALL pr_register_user($1, $2, $3, NULL, NULL, NULL)")
            .bind(username)
            .bind(password)
            .bind(mmr_point.unwrap_or(0))
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
        Err(error) => {
            let duplicate = error
                .as_database_error()
                .and_then(|database_error| database_error.code())
                .is_some_and(|code| code == "23505");
            log_error("register_user", error);
            let status = if duplicate {
                StatusCode::CONFLICT
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            };
            error_response(
                status,
                if duplicate {
                    "Username sudah digunakan"
                } else {
                    "Gagal mendaftarkan user"
                },
            )
        }
    }
}

#[derive(Deserialize)]
pub struct LoginDto {
    pub username: String,
    pub password: String,
}

pub async fn login(
    State(pool): State<PgPool>,
    axum::extract::Extension(jwt): axum::extract::Extension<JwtConfig>,
    Json(payload): Json<LoginDto>,
) -> impl IntoResponse {
    if let Err(error) = validate_username(&payload.username) {
        return error_response(StatusCode::BAD_REQUEST, error);
    }
    if let Err(error) = validate_password(&payload.password) {
        return error_response(StatusCode::BAD_REQUEST, error);
    }

    let account = match sqlx::query_as::<_, (i32, String, Option<String>)>(
        "SELECT id, username, password FROM users WHERE username = $1",
    )
    .bind(&payload.username)
    .fetch_optional(&pool)
    .await
    {
        Ok(Some(account)) => account,
        Ok(None) => {
            return error_response(StatusCode::UNAUTHORIZED, "Username atau password salah");
        }
        Err(error) => {
            log_error("login_lookup", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal memproses login");
        }
    };

    let password = payload.password;
    let Some(stored_hash) = account.2 else {
        return error_response(StatusCode::UNAUTHORIZED, "Username atau password salah");
    };
    let verified = match tokio::task::spawn_blocking(move || {
        let parsed_hash = PasswordHash::new(&stored_hash).ok()?;
        Argon2::default()
            .verify_password(password.as_bytes(), &parsed_hash)
            .ok()
    })
    .await
    {
        Ok(Some(())) => true,
        Ok(None) => false,
        Err(error) => {
            log_error("password_verify_task", error);
            return error_response(StatusCode::INTERNAL_SERVER_ERROR, "Gagal memproses login");
        }
    };

    if !verified {
        return error_response(StatusCode::UNAUTHORIZED, "Username atau password salah");
    }

    let token = match jwt.issue_token(account.0) {
        Ok(token) => token,
        Err(error) => {
            log_error("issue_jwt", error);
            return error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal membuat token akses",
            );
        }
    };

    (
        StatusCode::OK,
        Json(serde_json::json!({
            "access_token": token,
            "token_type": "Bearer",
            "expires_in": crate::auth::TOKEN_TTL_SECONDS,
            "user": { "id": account.0, "username": account.1 }
        })),
    )
        .into_response()
}

#[cfg(test)]
mod tests {
    use super::*;
    use argon2::password_hash::{PasswordHash, PasswordVerifier};

    #[test]
    fn password_hash_is_salted_and_verifiable() {
        let first_hash = hash_password("contoh-password-aman").unwrap();
        let second_hash = hash_password("contoh-password-aman").unwrap();
        let parsed_hash = PasswordHash::new(&first_hash).unwrap();

        assert_ne!(first_hash, second_hash);
        assert!(
            Argon2::default()
                .verify_password("contoh-password-aman".as_bytes(), &parsed_hash)
                .is_ok()
        );
        assert!(
            Argon2::default()
                .verify_password("password-salah".as_bytes(), &parsed_hash)
                .is_err()
        );
    }

    #[test]
    fn registration_input_validation_enforces_limits() {
        assert!(validate_username("player_123").is_ok());
        assert!(validate_username("ab").is_err());
        assert!(validate_username("player name").is_err());
        assert!(validate_password("a-strong-password").is_ok());
        assert!(validate_password("short").is_err());
        assert!(validate_password(&"x".repeat(129)).is_err());
    }

    #[test]
    fn registration_response_does_not_serialize_password() {
        let response = UserResponse {
            id: 1,
            username: "player1".to_owned(),
            mmr_point: Some(1000),
        };

        let json = serde_json::to_value(response).unwrap();

        assert!(json.get("password").is_none());
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
    if user_id <= 0 {
        return error_response(StatusCode::BAD_REQUEST, "ID player harus positif");
    }
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
        Err(error) => {
            log_error("get_user_profile", error);
            error_response(
                StatusCode::INTERNAL_SERVER_ERROR,
                "Gagal mengambil profil player",
            )
        }
    }
}

use axum::{
    body::Body,
    extract::Extension,
    http::{Request, StatusCode, header::AUTHORIZATION},
    middleware::Next,
    response::{IntoResponse, Response},
};
use jsonwebtoken::{Algorithm, DecodingKey, Validation, decode};
use serde::{Deserialize, Serialize};

pub const TOKEN_TTL_SECONDS: u64 = 3600;

#[derive(Clone)]
pub struct JwtConfig {
    secret: String,
}

impl JwtConfig {
    pub fn new(secret: String) -> Self {
        Self { secret }
    }

    pub fn issue_token(&self, user_id: i32) -> Result<String, jsonwebtoken::errors::Error> {
        let claims = Claims {
            sub: user_id.to_string(),
            exp: (std::time::SystemTime::now() + std::time::Duration::from_secs(TOKEN_TTL_SECONDS))
                .duration_since(std::time::UNIX_EPOCH)
                .expect("token expiration must be after Unix epoch")
                .as_secs() as usize,
        };
        jsonwebtoken::encode(
            &jsonwebtoken::Header::new(Algorithm::HS256),
            &claims,
            &jsonwebtoken::EncodingKey::from_secret(self.secret.as_bytes()),
        )
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Claims {
    pub sub: String,
    pub exp: usize,
}

pub async fn require_auth(
    Extension(config): Extension<JwtConfig>,
    mut request: Request<Body>,
    next: Next,
) -> Response {
    let token = request
        .headers()
        .get(AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .filter(|token| !token.is_empty());

    let Some(token) = token else {
        return (
            StatusCode::UNAUTHORIZED,
            axum::Json(serde_json::json!({"error": "Token Bearer diperlukan"})),
        )
            .into_response();
    };

    let claims = match decode::<Claims>(
        token,
        &DecodingKey::from_secret(config.secret.as_bytes()),
        &Validation::new(Algorithm::HS256),
    ) {
        Ok(token) => token.claims,
        Err(_) => {
            return (
                StatusCode::UNAUTHORIZED,
                axum::Json(
                    serde_json::json!({"error": "Token tidak valid atau sudah kedaluwarsa"}),
                ),
            )
                .into_response();
        }
    };

    request.extensions_mut().insert(claims);
    next.run(request).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn issued_token_is_signed_and_expires() {
        let config = JwtConfig::new("a sufficiently long test secret value".to_owned());
        let token = config.issue_token(42).unwrap();
        let claims = decode::<Claims>(
            &token,
            &DecodingKey::from_secret(config.secret.as_bytes()),
            &Validation::new(Algorithm::HS256),
        )
        .unwrap()
        .claims;

        assert_eq!(claims.sub, "42");
        assert!(claims.exp > 0);
    }

    #[test]
    fn token_cannot_be_verified_with_another_secret() {
        let config = JwtConfig::new("a sufficiently long test secret value".to_owned());
        let token = config.issue_token(42).unwrap();
        let result = decode::<Claims>(
            &token,
            &DecodingKey::from_secret(b"a different sufficiently long secret"),
            &Validation::new(Algorithm::HS256),
        );

        assert!(result.is_err());
    }
}

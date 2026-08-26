use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};

pub(crate) fn message(status: StatusCode, text: &str) -> Response {
    (status, Json(serde_json::json!({"message": text}))).into_response()
}

pub(crate) fn error_response(status: StatusCode, text: impl Into<String>) -> Response {
    (status, Json(serde_json::json!({"error": text.into()}))).into_response()
}

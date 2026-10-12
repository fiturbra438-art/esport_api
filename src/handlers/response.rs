use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use std::fmt::Display;

pub(crate) fn message(status: StatusCode, text: &str) -> Response {
    (status, Json(serde_json::json!({"message": text}))).into_response()
}

pub(crate) fn error_response(status: StatusCode, text: impl Into<String>) -> Response {
    (status, Json(serde_json::json!({"error": text.into()}))).into_response()
}

pub(crate) fn log_error(context: &'static str, error: impl Display) {
    tracing::error!(context, %error, "Request operation failed");
}

use thiserror::Error;

/// Kinds the glasses bunker may sign (G-W3).
pub const ALLOWED_EVENT_KINDS: [u16; 2] = [9, 22242];

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SignPolicyError {
    #[error("kind {0} is not in the bunker allowlist")]
    DisallowedKind(u16),
}

pub fn is_allowed_event_kind(kind: u16) -> bool {
    ALLOWED_EVENT_KINDS.contains(&kind)
}

pub fn require_allowed_kind(kind: u16) -> Result<(), SignPolicyError> {
    if is_allowed_event_kind(kind) {
        Ok(())
    } else {
        Err(SignPolicyError::DisallowedKind(kind))
    }
}

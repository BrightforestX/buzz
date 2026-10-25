//! NIP-46 bunker policy for glasses → Buzz voice bridge (G-W3).
//!
//! Desktop holds the owner key; Mentra holds only an ephemeral client key.

mod policy;

pub use policy::{is_allowed_event_kind, SignPolicyError, ALLOWED_EVENT_KINDS};

use nostr::prelude::*;
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum BunkerSignError {
    #[error("event kind {0} not allowed")]
    KindNotAllowed(u16),
    #[error("client pubkey not allowlisted")]
    ClientNotAllowed,
    #[error("invalid unsigned event: {0}")]
    InvalidEvent(String),
    #[error("signing failed: {0}")]
    SignFailed(String),
}

/// JSON-RPC `sign_event` params (NIP-46 subset used by Mentra bunker).
#[derive(Debug, Clone, Deserialize)]
pub struct SignEventParams {
    pub event: UnsignedEventJson,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnsignedEventJson {
    pub kind: u16,
    pub content: String,
    pub tags: Vec<Vec<String>>,
    pub created_at: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedEventJson {
    pub id: String,
    pub pubkey: String,
    pub created_at: u64,
    pub kind: u16,
    pub tags: Vec<Vec<String>>,
    pub content: String,
    pub sig: String,
}

pub fn build_event_from_json(json: &UnsignedEventJson) -> Result<EventBuilder, BunkerSignError> {
    if !is_allowed_event_kind(json.kind) {
        return Err(BunkerSignError::KindNotAllowed(json.kind));
    }
    let tags: Vec<Tag> = json
        .tags
        .iter()
        .map(|parts| {
            Tag::parse(parts.iter().map(String::as_str))
                .map_err(|e| BunkerSignError::InvalidEvent(e.to_string()))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let mut builder = EventBuilder::new(Kind::Custom(json.kind), json.content.clone()).tags(tags);
    if let Some(created_at) = json.created_at {
        builder = builder.custom_created_at(Timestamp::from(created_at));
    }
    Ok(builder)
}

pub fn sign_unsigned_json(
    keys: &Keys,
    json: &UnsignedEventJson,
    client_allowed: bool,
) -> Result<SignedEventJson, BunkerSignError> {
    if !client_allowed {
        return Err(BunkerSignError::ClientNotAllowed);
    }
    let builder = build_event_from_json(json)?;
    let signed = builder
        .sign_with_keys(keys)
        .map_err(|e| BunkerSignError::SignFailed(e.to_string()))?;
    Ok(signed_event_to_json(&signed))
}

pub fn signed_event_to_json(event: &Event) -> SignedEventJson {
    SignedEventJson {
        id: event.id.to_hex(),
        pubkey: event.pubkey.to_hex(),
        created_at: event.created_at.as_secs(),
        kind: event.kind.as_u16(),
        tags: event.tags.iter().map(|t| t.clone().to_vec()).collect(),
        content: event.content.clone(),
        sig: event.sig.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_kind_nine_and_auth() {
        assert!(is_allowed_event_kind(9));
        assert!(is_allowed_event_kind(22242));
        assert!(!is_allowed_event_kind(1));
        assert!(!is_allowed_event_kind(0));
    }

    #[test]
    fn denies_disallowed_kind_before_sign() {
        let keys = Keys::generate();
        let json = UnsignedEventJson {
            kind: 1,
            content: "note".into(),
            tags: vec![],
            created_at: None,
        };
        let err = sign_unsigned_json(&keys, &json, true).unwrap_err();
        assert_eq!(err, BunkerSignError::KindNotAllowed(1));
    }

    #[test]
    fn signs_kind_nine_when_client_allowed() {
        let keys = Keys::generate();
        let json = UnsignedEventJson {
            kind: 9,
            content: "hello".into(),
            tags: vec![
                vec!["h".into(), "chan".into()],
                vec!["p".into(), "ab".repeat(32)],
            ],
            created_at: None,
        };
        let signed = sign_unsigned_json(&keys, &json, true).expect("sign");
        assert_eq!(signed.kind, 9);
        assert_eq!(signed.pubkey, keys.public_key().to_hex());
    }

    #[test]
    fn denies_when_client_not_allowlisted() {
        let keys = Keys::generate();
        let json = UnsignedEventJson {
            kind: 9,
            content: "hello".into(),
            tags: vec![],
            created_at: None,
        };
        let err = sign_unsigned_json(&keys, &json, false).unwrap_err();
        assert_eq!(err, BunkerSignError::ClientNotAllowed);
    }
}

// Connect tickets, the target's half.
//
// A ticket is minted by the Worker when a console opens a session, delivered
// to the target machine in the `tickets` member of the `/agent/batch` answer,
// and handed by this daemon to the `--server` process that answers logins,
// over the main IPC channel `""` (0600 on Linux and macOS; on Windows the same
// LocalSystem `--server`). `--server` keeps a claim-once map keyed by the
// controller's peer id (`src/server/connection.rs`, beside
// `PENDING_SWITCH_SIDES_UUID`), and a login from that peer presenting
// `sha256(H || salt)` claims it exactly once. Nothing about a ticket is stored
// on disk here: it lives 120 s and a daemon restart simply loses it, which the
// Worker answers by minting another with the next session.
//
// `H` is `sha256Hex(secret)` in the Worker's terms (`src/worker/crypto.ts`,
// SHA-256 over the UTF-8 bytes of the string). The delivery carries `H` itself
// when the row already holds it, and the plaintext only when the Worker chose
// to send that instead; `secret_hash` takes either, so the two lanes cannot
// disagree about which one arrived.

use hbb_common::{bail, log, sodiumoxide::crypto::hash::sha256, ResultType};
use serde_derive::Deserialize;

/// One ticket as the batch answer carries it.
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Ticket {
    pub id: String,
    pub secret: String,
    pub controller_peer_id: String,
    pub expires_at: i64,
}

/// The `tickets` member of a batch answer. Absent is empty; an entry that
/// does not parse is skipped, because the rest are still owed to `--server`.
pub fn tickets_in(text: &str) -> Vec<Ticket> {
    let Ok(answer) = serde_json::from_str::<serde_json::Value>(text) else {
        return Vec::new();
    };
    answer["tickets"]
        .as_array()
        .map(|entries| {
            entries
                .iter()
                .filter_map(|entry| match serde_json::from_value::<Ticket>(entry.clone()) {
                    Ok(ticket) => Some(ticket),
                    Err(err) => {
                        log::warn!("[ticket] Skipping a ticket the answer mis-shaped: {}", err);
                        None
                    }
                })
                .collect()
        })
        .unwrap_or_default()
}

/// `H`: the delivered value when it already is a SHA-256 hex digest, else
/// the digest of the delivered string's bytes.
pub fn secret_hash(delivered: &str) -> String {
    if delivered.len() == 64 && delivered.bytes().all(|b| b.is_ascii_hexdigit()) {
        return delivered.to_ascii_lowercase();
    }
    hex::encode(sha256::hash(delivered.as_bytes()).0)
}

/// Hand one ticket to the `--server` that answers logins on this machine.
///
/// Linux and macOS: the daemon is root and `--server` runs as the seat0 user,
/// whose main channel is under that user's runtime directory, so the connect
/// names the uid. Windows: one named pipe, served by the LocalSystem
/// `--server`.
pub async fn deliver(ticket: &Ticket) -> ResultType<()> {
    let data = crate::ipc::Data::ConnectTicket {
        id: ticket.id.clone(),
        controller_peer_id: ticket.controller_peer_id.clone(),
        secret_hash: secret_hash(&ticket.secret),
        expires_at: ticket.expires_at,
    };
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    let mut conn = {
        let uid = crate::platform::get_active_userid();
        let Ok(uid) = uid.trim().parse::<u32>() else {
            bail!("no active user to deliver ticket {} to", ticket.id);
        };
        crate::ipc::connect_for_uid(1000, uid, "").await?
    };
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    let mut conn = crate::ipc::connect(1000, "").await?;
    conn.send(&data).await?;
    // `--server` answers `Empty` once the map holds the ticket, so a delivery
    // that was refused or dropped is an error here rather than a silent gap.
    match conn.next_timeout(1000).await? {
        Some(crate::ipc::Data::Empty) => Ok(()),
        _ => bail!("no answer from --server for ticket {}", ticket.id),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_tickets_member_is_read_by_name() {
        let tickets = tickets_in(
            r#"{"ok":true,"jobs":[],"tickets":[
                {"id":"t1","secret":"c2VjcmV0","controllerPeerId":"1935956186","expiresAt":1788480243},
                {"id":"bad"}
            ]}"#,
        );
        assert_eq!(
            tickets,
            vec![Ticket {
                id: "t1".into(),
                secret: "c2VjcmV0".into(),
                controller_peer_id: "1935956186".into(),
                expires_at: 1788480243,
            }]
        );
        assert!(tickets_in(r#"{"ok":true}"#).is_empty());
        assert!(tickets_in("nope").is_empty());
    }

    /// The Worker's `sha256Hex` is SHA-256 over the UTF-8 bytes of the
    /// string, hex encoded. The same input must give the same `H` here, and a
    /// value that already is an `H` must pass through untouched.
    #[test]
    fn the_secret_hash_matches_the_workers_sha256hex() {
        assert_eq!(
            secret_hash("secret"),
            "2bb80d537b1da3e38bd30361aa855686bde0eacd7162fef6a25fe97bf527a25b"
        );
        let h = "2BB80D537B1DA3E38BD30361AA855686BDE0EACD7162FEF6A25FE97BF527A25B";
        assert_eq!(secret_hash(h), h.to_ascii_lowercase());
        // Sixty four characters that are not all hex are a secret, not a hash.
        let not_hex = "zz".repeat(32);
        assert_ne!(secret_hash(&not_hex), not_hex);
        assert_eq!(secret_hash(&not_hex).len(), 64);
    }
}

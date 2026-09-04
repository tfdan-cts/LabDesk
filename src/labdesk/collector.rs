// The always-on telemetry collector.
//
// This runs in the `--service` daemon and nowhere else. That placement is the whole point:
// on Linux `--server` is launched through `run_as_user` as the desktop user
// (src/platform/linux.rs:713-717) while `res/rustdesk.service` runs `--service` as root,
// and on macOS `_service.plist` is installed under /Library/LaunchDaemons against
// `_server.plist` under /Library/LaunchAgents (src/platform/macos.rs:190-195, :339-343).
// On Windows `sc create ... binpath= "{exe} --service"` carries no `obj=`, so the service
// is LocalSystem. Only `--service` is root/SYSTEM on all three, and a collector in the
// user process could neither read disk health nor keep running while nobody is logged in.
//
// The loop itself is deliberately small. It samples on a tick, writes one line per sample
// to the spool, and flushes the spool on a slower tick. Every decision worth getting wrong
// -- the hard cap, what a batch carries, what a status code means for the history on disk,
// how long to wait after a failure -- lives in `super::spool` as a pure function with
// tests. What is left here is the plumbing those functions are wired into.

use super::identity::{uplink_signed_msg, AgentIdentity};
use super::spool::{
    ack_for, backoff_seconds, batch_window, flush_jitter_seconds, Ack, Spool, MAX_BATCH_BYTES,
    MAX_BATCH_LINES,
};
use hbb_common::{
    bail,
    config::Config,
    log,
    sysinfo::{Disks, Networks, System},
    tokio::time::{sleep, Instant},
    ResultType,
};
use std::time::Duration;

const SPOOL_FILE: &str = "agent-spool.jsonl";
const BATCH_PATH: &str = "/agent/batch";
/// How often an un-enrolled daemon looks again. `labdesk --enrol` runs in a separate
/// process and writes the machine id into the identity file, so the only way this one
/// learns about it is to re-read the file.
const ENROLMENT_POLL: Duration = Duration::from_secs(60);
const UPLINK_TIMEOUT: Duration = Duration::from_secs(20);

/// Start the collector on its own thread with its own runtime.
///
/// `Builder::new().spawn` rather than `thread::spawn`: the latter panics when a thread
/// cannot be created, and that panic would unwind out of `start_os_service` and take the
/// whole service down. Losing telemetry must never cost the machine its remote access.
pub fn start() {
    if let Err(err) = std::thread::Builder::new()
        .name("labdesk-collector".to_owned())
        .spawn(|| {
            let runtime = match hbb_common::tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(runtime) => runtime,
                Err(err) => {
                    log::error!("[collector] Failed to build the runtime: {}", err);
                    return;
                }
            };
            runtime.block_on(run());
        })
    {
        log::warn!("[collector] Failed to spawn the collector thread: {}", err);
    }
}

async fn run() {
    let mut identity = match wait_for_enrolment().await {
        Some(identity) => identity,
        None => return,
    };
    let spool = Spool::new(Config::path(SPOOL_FILE));
    let mut sampler = Sampler::new();
    let mut sample_seconds = identity.sample_seconds();

    // The offset is why five hundred agents installed from one image do not all arrive in
    // the same second. It delays the first flush only; every later one follows the cadence.
    let jitter = flush_jitter_seconds(identity.machine_id(), identity.flush_seconds());
    let mut next_sample = Instant::now() + Duration::from_secs(sample_seconds);
    let mut next_flush = Instant::now() + Duration::from_secs(jitter);
    let mut failures = 0u32;
    log::info!(
        "[collector] Started: sampling every {}s, flushing every {}s offset by {}s",
        sample_seconds,
        identity.flush_seconds(),
        jitter
    );

    loop {
        let deadline = next_sample.min(next_flush);
        let now = Instant::now();
        if deadline > now {
            sleep(deadline - now).await;
        }

        let now = Instant::now();
        if now >= next_sample {
            next_sample = now + Duration::from_secs(sample_seconds);
            if let Err(err) = spool.append(&sampler.sample()) {
                log::warn!("[collector] Failed to spool a sample: {}", err);
            }
        }

        if now >= next_flush {
            match flush(&mut identity, &spool, &sampler, sample_seconds).await {
                Ok(Some(Ack::Accepted)) | Ok(None) => failures = 0,
                Ok(Some(Ack::Revoked)) => {
                    // The org has revoked this machine. Stop collecting and take the
                    // history with us: what is on that disk is inventory about a customer
                    // who has said they are no longer a customer.
                    log::info!("[collector] This machine is revoked; deleting the spool");
                    if let Err(err) = spool.clear() {
                        log::warn!("[collector] Failed to delete the spool: {}", err);
                    }
                    return;
                }
                Ok(Some(Ack::Retry)) => failures = failures.saturating_add(1),
                Err(err) => {
                    log::warn!("[collector] Uplink failed: {}", err);
                    failures = failures.saturating_add(1);
                }
            }
            // Both cadences are server controlled and an accepted batch may have just
            // moved them. Reading them back here rather than caching them at start is
            // what lets a fleet already in the field be slowed down without every machine
            // having to be re-enrolled.
            let adopted = identity.sample_seconds();
            if adopted != sample_seconds {
                log::info!(
                    "[collector] The sample cadence moved from {}s to {}s",
                    sample_seconds,
                    adopted
                );
                sample_seconds = adopted;
                next_sample = Instant::now() + Duration::from_secs(sample_seconds);
            }
            let wait = backoff_seconds(identity.flush_seconds(), failures);
            next_flush = Instant::now() + Duration::from_secs(wait);
        }
    }
}

/// Load the agent identity, waiting for an administrator to run `--enrol` if need be.
///
/// Returns `None` only when the identity file itself cannot be used, which is a state a
/// retry loop cannot fix and which `AgentIdentity` deliberately refuses to paper over by
/// generating a second key.
async fn wait_for_enrolment() -> Option<AgentIdentity> {
    loop {
        match AgentIdentity::load_or_create() {
            Ok(identity) if !identity.machine_id().is_empty() => return Some(identity),
            Ok(_) => {}
            Err(err) => {
                log::error!("[collector] No usable agent identity: {}", err);
                return None;
            }
        }
        sleep(ENROLMENT_POLL).await;
    }
}

/// One flush attempt. `Ok(None)` means nothing was owed to the server, which is not a
/// failure and must not push the backoff out.
async fn flush(
    identity: &mut AgentIdentity,
    spool: &Spool,
    sampler: &Sampler,
    sample_seconds: u64,
) -> ResultType<Option<Ack>> {
    let lines = spool.read()?;
    let window = batch_window(&lines, MAX_BATCH_LINES, MAX_BATCH_BYTES);
    if window.dropped > 0 {
        log::warn!(
            "[collector] Dropping {} spool line(s) too large to ever send",
            window.dropped
        );
    }
    if window.sent == 0 {
        spool.drop_front(window.dropped)?;
        return Ok(None);
    }

    let sent = &lines[window.dropped..window.consumed()];
    let body = match batch_body(sampler.machine(), sent, sample_seconds) {
        Ok(body) => body,
        Err(err) => {
            // Nothing in this window can be turned into a batch. Drop it for the same
            // reason an oversized line is dropped: left at the front it would wedge every
            // later sample behind it forever.
            log::warn!(
                "[collector] Discarding {} unusable spool line(s): {}",
                window.sent,
                err
            );
            spool.drop_front(window.consumed())?;
            return Ok(None);
        }
    };
    let (status, text) = post_signed(identity, BATCH_PATH, &body).await?;
    let ack = ack_for(status);
    match ack {
        Ack::Accepted => {
            // Only now. Everything before this point leaves the spool exactly as it was,
            // which is what lets a machine survive a week of failed sends.
            spool.drop_front(window.consumed())?;
            adopt_cadences(identity, &text);
        }
        Ack::Revoked | Ack::Retry => {
            log::warn!("[collector] The server refused the batch: {} {}", status, text);
        }
    }
    Ok(Some(ack))
}

/// The cadences the server named, as `(sampleSeconds, flushSeconds)`.
///
/// Zero means "not named". Both members are optional in the response and a member the
/// server leaves out must leave the agent on the cadence it already had rather than
/// snapping it back to a default, which is why absence and zero are the same answer here.
fn asked_cadences(text: &str) -> (u64, u64) {
    let Ok(response) = serde_json::from_str::<serde_json::Value>(text) else {
        return (0, 0);
    };
    (
        response["sampleSeconds"].as_u64().unwrap_or(0),
        response["flushSeconds"].as_u64().unwrap_or(0),
    )
}

/// Which cadences to persist, given what the server `asked` for and the `current` pair.
///
/// `None` means nothing moved and the identity file must not be rewritten: a five minute
/// flush must not rewrite a credential file 288 times a day.
fn adopted_cadences(asked: (u64, u64), current: (u64, u64)) -> Option<(u64, u64)> {
    let wanted = (
        if asked.0 == 0 { current.0 } else { asked.0 },
        if asked.1 == 0 { current.1 } else { asked.1 },
    );
    (wanted != current).then_some(wanted)
}

/// Adopt the cadences an accepted batch echoed back.
///
/// The identity is re-read from disk rather than written back from the copy this daemon
/// loaded at start. `--enrol` is a separate process (identity.rs:88-97) and may have
/// re-enrolled this machine since, while `store` writes sk, pk, machine_id and both
/// cadences together (identity.rs:204-226) -- so writing a start-of-day snapshot back
/// would put a stale machine id over a freshly enrolled one. `machine_agent_pk_uidx` is
/// globally unique, so that is not recoverable from the agent side.
///
/// Nothing here returns an error. The server has already taken the batch and the spool
/// has already been truncated; charging the agent a doubling backoff because a file could
/// not be rewritten would make a transient disk fault look like an unreachable server.
fn adopt_cadences(identity: &mut AgentIdentity, text: &str) {
    let asked = asked_cadences(text);
    if asked == (0, 0) {
        return;
    }
    let mut fresh = match AgentIdentity::load_or_create() {
        Ok(fresh) if !fresh.machine_id().is_empty() => fresh,
        // An identity with no machine id means the file went away underneath us and a
        // fresh key was generated. Keep signing with the credential the server actually
        // holds rather than adopting one it has never seen.
        Ok(_) => {
            log::warn!("[collector] The identity file holds no enrolment; keeping the loaded one");
            return;
        }
        Err(err) => {
            log::warn!("[collector] Failed to re-read the agent identity: {}", err);
            return;
        }
    };
    // Measured against the file, not against the copy this daemon started with, so a
    // cadence that a re-enrolment has just written is not immediately undone.
    if let Some((sample_seconds, flush_seconds)) =
        adopted_cadences(asked, (fresh.sample_seconds(), fresh.flush_seconds()))
    {
        log::info!(
            "[collector] Adopting the server cadences: sample {}s, flush {}s",
            sample_seconds,
            flush_seconds
        );
        // `set_enrolment` is the only setter carrying both cadences. It writes the machine
        // id it is handed, which is the one just read off that same file.
        let machine_id = fresh.machine_id().to_owned();
        if let Err(err) = fresh.set_enrolment(&machine_id, sample_seconds, flush_seconds) {
            log::warn!("[collector] Failed to persist the server cadences: {}", err);
        }
    }
    *identity = fresh;
}

/// Build the request body from spool lines of the form
/// `[at, cpuPct, memPct, fsWorstPct, netRx, netTx]`.
///
/// The leading timestamp is the spool's own, not the wire's: the batch carries `from` and
/// `to` once and the samples themselves are the five readings, packed positionally.
fn batch_body(
    machine: serde_json::Value,
    lines: &[String],
    step: u64,
) -> ResultType<String> {
    // `Option` rather than a zero sentinel: the batch window is what the server
    // de-duplicates on, so a machine whose clock reads the epoch must report the epoch
    // rather than silently take the timestamp of a later sample.
    let mut from = None;
    let mut to = 0u64;
    let mut samples = Vec::with_capacity(lines.len());
    for line in lines {
        // A line that will not parse is skipped rather than allowed to fail the whole
        // batch: it still leaves the spool with the rest, so one bad line cannot wedge
        // every sample behind it.
        let Ok(serde_json::Value::Array(values)) = serde_json::from_str(line) else {
            log::warn!("[collector] Skipping an unreadable spool line");
            continue;
        };
        let Some(at) = values.first().and_then(|at| at.as_u64()) else {
            continue;
        };
        from.get_or_insert(at);
        to = at;
        samples.push(serde_json::Value::Array(values[1..].to_vec()));
    }
    if samples.is_empty() {
        bail!("No readable samples in the batch");
    }
    Ok(serde_json::json!({
        "machine": machine,
        "batch": { "from": from, "to": to, "step": step, "samples": samples },
    })
    .to_string())
}

/// POST a signed body to an `/agent/*` path.
///
/// The three headers are the uplink contract from the architecture: the machine id the
/// server looks the key up by, the timestamp it bounds replay with, and the detached
/// Ed25519 signature over the method, path, timestamp and body hash.
async fn post_signed(
    identity: &AgentIdentity,
    path: &str,
    body: &str,
) -> ResultType<(u16, String)> {
    let api_server = crate::ui_interface::get_api_server();
    if api_server.is_empty() || crate::is_public(&api_server) {
        bail!("No API server is configured!");
    }
    let ts = (hbb_common::get_time() / 1000).to_string();
    let signature = identity.sign(&uplink_signed_msg("POST", path, &ts, body.as_bytes()))?;
    let url = format!("{}{}", api_server, path);
    // The strict client refuses anything but HTTPS. An uplink carries a machine's whole
    // inventory, so cleartext is not a configuration we quietly accept.
    let response = crate::hbbs_http::create_http_client_async_with_url_strict(&url)
        .await?
        .post(&url)
        .header("Content-Type", "application/json")
        .header("X-LD-Machine", identity.machine_id())
        .header("X-LD-Ts", &ts)
        .header("X-LD-Sig", signature)
        .timeout(UPLINK_TIMEOUT)
        .body(body.to_owned())
        .send()
        .await?;
    let status = response.status().as_u16();
    Ok((status, response.text().await?))
}

/// The 60 s cadence: everything cheap enough to read once a minute forever.
struct Sampler {
    system: System,
    networks: Networks,
    disks: Disks,
}

impl Sampler {
    fn new() -> Self {
        let mut system = System::new();
        // CPU usage is a delta between two refreshes, so the first one here is what makes
        // the first sample -- a whole cadence later -- a real reading rather than a zero.
        system.refresh_cpu();
        system.refresh_memory();
        // The disk and interface lists are deliberately left empty. `sample` enumerates
        // both from scratch every time, so there is nothing for a constructor to seed.
        Self {
            system,
            networks: Networks::new(),
            disks: Disks::new(),
        }
    }

    /// One spool line: `[at, cpuPct, memPct, fsWorstPct, netRx, netTx]`.
    ///
    /// A figure we could not read is `null`, never zero. The console renders absence as
    /// `--`; a zero would render as a healthy reading of a machine we did not measure.
    fn sample(&mut self) -> String {
        self.system.refresh_cpu();
        self.system.refresh_memory();
        // `refresh_list`, never `refresh`. In the vendored fork `Disks::refresh` walks only
        // the disks already listed (sysinfo src/common.rs:2155-2159, whose own warning is
        // "if a disk is added or removed, this method won't take it into account") and
        // `NetworksInner::refresh` walks only the interfaces already mapped
        // (src/unix/linux/network.rs:129-135, src/windows/network.rs:154-159). A service
        // starts at boot, before BitLocker unlock and before most data volumes attach, so
        // a sampler that froze its lists there would be permanently blind to the very disk
        // that later fills, and would never count an overlay, VPN or dock interface that
        // came up afterwards.
        self.networks.refresh_list();
        self.disks.refresh_list();

        let at = hbb_common::get_time() / 1000;
        let cpu = self.system.global_cpu_info().cpu_usage().round() as u64;
        let total_memory = self.system.total_memory();
        let memory =
            (total_memory > 0).then(|| percent(self.system.used_memory(), total_memory));
        // The fullest fixed mount. Removable media is excluded: a full USB stick is not a
        // machine about to stop working.
        let fullest = self
            .disks
            .list()
            .iter()
            .filter(|disk| !disk.is_removable() && disk.total_space() > 0)
            .map(|disk| {
                percent(
                    disk.total_space().saturating_sub(disk.available_space()),
                    disk.total_space(),
                )
            })
            .max();
        // The kernel's own since-interface-up totals, summed over the interfaces present
        // right now: `total_received` returns `/sys/class/net/<if>/statistics/rx_bytes`
        // verbatim on Linux (sysinfo src/unix/linux/network.rs:181-184, :227-229) and
        // `MIB_IF_ROW2.InOctets` on Windows (src/windows/network.rs:103, :210-212).
        // Restarting this daemon therefore does NOT reset the sum; a reboot or an interface
        // flap does, and so does an interface going away, since `refresh_list` drops the
        // ones that are gone. Whoever differences this into a rate must read any decrease
        // as a reset rather than as negative traffic.
        let (received, transmitted) =
            self.networks
                .list()
                .values()
                .fold((0u64, 0u64), |acc, data| {
                    (
                        acc.0.saturating_add(data.total_received()),
                        acc.1.saturating_add(data.total_transmitted()),
                    )
                });
        pack(&Reading {
            at,
            cpu,
            memory,
            fullest,
            received,
            transmitted,
        })
    }

    /// The `machine` member every batch carries.
    ///
    /// `conns` is deliberately absent: live connection counts live in the unprivileged
    /// `--server` processes and this daemon has no IPC call that answers for all of them,
    /// so there is no honest number to put here yet. Absence renders `--`; a zero would
    /// claim we had measured an idle machine.
    fn machine(&self) -> serde_json::Value {
        serde_json::json!({
            "hostname": crate::hostname(),
            "os": self.system.long_os_version().unwrap_or_default(),
            "agentVersion": crate::VERSION,
            "uptimeS": self.system.uptime(),
            "loggedInUser": crate::platform::get_active_username(),
        })
    }
}

/// Pack one reading into a spool line.
///
/// The order is the wire contract. The batch strips the leading timestamp and sends the
/// remaining five positionally as `[cpu, memPct, fsWorstPct, netRx, netTx]`, which is the
/// order the console's columns and every health rule are read out of, so a transposition
/// here would render a filesystem percentage as memory on every chart. That is why this is
/// a named function pinned by a test on the exact string rather than a `json!` line inside
/// the sampler where nothing could see it.
fn pack(reading: &Reading) -> String {
    serde_json::json!([
        reading.at,
        reading.cpu,
        reading.memory,
        reading.fullest,
        reading.received,
        reading.transmitted,
    ])
    .to_string()
}

/// One reading, before it is packed.
///
/// Named fields rather than a six-tuple, so that the only place two of these can be
/// transposed is `pack`, which a test pins position by position. Four of the six are plain
/// `u64` and would swap without a compiler complaint if the sampler handed them over
/// positionally.
struct Reading {
    /// `hbb_common::get_time()` is `i64` (libs/hbb_common/src/lib.rs:379); the spool line
    /// carries it as it comes rather than through a cast that could wrap.
    at: i64,
    cpu: u64,
    memory: Option<u64>,
    fullest: Option<u64>,
    received: u64,
    transmitted: u64,
}

/// `used` as a whole percent of `total`. Callers guarantee a non-zero total; a reading
/// that has no total to be a percent of is `None`, and serialises as `null` rather than
/// as a zero the console would render as a healthy measurement.
fn percent(used: u64, total: u64) -> u64 {
    ((used as f64 / total.max(1) as f64) * 100.0).round() as u64
}

#[cfg(test)]
mod tests {
    use super::*;

    fn machine() -> serde_json::Value {
        serde_json::json!({ "hostname": "host-1" })
    }

    #[test]
    fn test_the_batch_carries_the_window_and_strips_the_spool_timestamp() {
        let lines = vec![
            "[1788480000,7,42,55,100,200]".to_owned(),
            "[1788480060,9,43,55,140,260]".to_owned(),
            "[1788480120,11,44,56,180,320]".to_owned(),
        ];
        let body: serde_json::Value =
            serde_json::from_str(&batch_body(machine(), &lines, 60).unwrap()).unwrap();

        // Each figure by name, not merely "it parsed": `from` is the first sample's
        // timestamp and `to` the last, and neither may be a sample reading.
        assert_eq!(body["batch"]["from"], 1788480000u64);
        assert_eq!(body["batch"]["to"], 1788480120u64);
        assert_eq!(body["batch"]["step"], 60u64);
        assert_eq!(body["machine"]["hostname"], "host-1");

        // The timestamp leads the spool line and must not lead the packed sample, or every
        // chart would read a unix time as a CPU percentage.
        assert_eq!(
            body["batch"]["samples"],
            serde_json::json!([[7, 42, 55, 100, 200], [9, 43, 55, 140, 260], [11, 44, 56, 180, 320]])
        );
    }

    #[test]
    fn test_an_unreadable_line_is_skipped_and_an_unreadable_batch_is_refused() {
        let lines = vec![
            "not json at all".to_owned(),
            "[1788480060,9,43,55,140,260]".to_owned(),
            "{\"cpu\":7}".to_owned(),
        ];
        let body: serde_json::Value =
            serde_json::from_str(&batch_body(machine(), &lines, 60).unwrap()).unwrap();
        assert_eq!(body["batch"]["from"], 1788480060u64);
        assert_eq!(body["batch"]["to"], 1788480060u64);
        assert_eq!(
            body["batch"]["samples"],
            serde_json::json!([[9, 43, 55, 140, 260]])
        );

        // A window with nothing readable in it is an error rather than an empty batch, so
        // that the caller drops those lines instead of posting a batch of no samples.
        assert!(batch_body(machine(), &["not json at all".to_owned()], 60).is_err());
        assert!(batch_body(machine(), &[], 60).is_err());
    }

    #[test]
    fn test_a_reading_with_no_total_is_null_and_never_zero() {
        // The console renders absence as `--` and zero as a measurement. A machine whose
        // memory total could not be read is not a machine with no memory in use.
        assert_eq!(serde_json::json!(Option::<u64>::None), serde_json::Value::Null);
        assert_eq!(percent(0, 0), 0);
        assert_eq!(percent(1, 2), 50);
        assert_eq!(percent(2, 3), 67);
        assert_eq!(percent(1, 1000), 0);
    }

    #[test]
    fn test_a_sample_is_packed_in_the_one_order_the_wire_pins() {
        // Six values chosen so that no two are equal and none could pass for another: any
        // transposition at all moves a digit in this string. The wire is
        // `[cpu, memPct, fsWorstPct, netRx, netTx]` once the leading spool timestamp is
        // stripped, so a memory percentage arriving in the filesystem column would fire
        // every disk-full rule against the wrong series.
        assert_eq!(
            pack(&Reading {
                at: 1788480000,
                cpu: 7,
                memory: Some(42),
                fullest: Some(55),
                received: 100,
                transmitted: 200,
            }),
            "[1788480000,7,42,55,100,200]"
        );

        // Position by position, against a body built from that very line, so the packing
        // and the batch cannot drift apart.
        let body: serde_json::Value = serde_json::from_str(
            &batch_body(
                machine(),
                &[pack(&Reading {
                    at: 1788480000,
                    cpu: 7,
                    memory: Some(42),
                    fullest: Some(55),
                    received: 100,
                    transmitted: 200,
                })],
                60,
            )
            .unwrap(),
        )
        .unwrap();
        let sample = &body["batch"]["samples"][0];
        assert_eq!(body["batch"]["from"], 1788480000u64, "at leads the spool line");
        assert_eq!(sample[0], 7u64, "cpu is the first wire column");
        assert_eq!(sample[1], 42u64, "memPct is the second");
        assert_eq!(sample[2], 55u64, "fsWorstPct is the third");
        assert_eq!(sample[3], 100u64, "netRx is the fourth");
        assert_eq!(sample[4], 200u64, "netTx is the fifth");

        // A reading we could not take is `null` in place, never a zero and never a hole
        // that shortens the row and shifts every later column left.
        assert_eq!(
            pack(&Reading {
                at: 1788480000,
                cpu: 7,
                memory: None,
                fullest: None,
                received: 100,
                transmitted: 200,
            }),
            "[1788480000,7,null,null,100,200]"
        );
    }

    #[test]
    fn test_both_cadences_are_server_controlled_and_an_unchanged_pair_is_not_rewritten() {
        // The response shape from the wire format. Both members move the agent.
        assert_eq!(
            asked_cadences(r#"{"ok":true,"sampleSeconds":30,"flushSeconds":900}"#),
            (30, 900)
        );
        // A member the server omits is not a request to reset it, so it reads as zero and
        // leaves that cadence alone below.
        assert_eq!(asked_cadences(r#"{"ok":true,"flushSeconds":900}"#), (0, 900));
        assert_eq!(asked_cadences(r#"{"ok":true,"sampleSeconds":30}"#), (30, 0));
        assert_eq!(asked_cadences(r#"{"ok":true}"#), (0, 0));
        // A body that is not JSON, or names the cadences as something other than a number,
        // must not be read as "slow to zero".
        assert_eq!(asked_cadences("not json at all"), (0, 0));
        assert_eq!(asked_cadences(r#"{"sampleSeconds":"30"}"#), (0, 0));
        assert_eq!(asked_cadences(r#"{"sampleSeconds":-30}"#), (0, 0));

        // Each cadence is adopted on its own: a fleet slowed only in its sampling keeps the
        // flush it had, which is the whole point of the two being separate knobs.
        assert_eq!(adopted_cadences((30, 900), (60, 300)), Some((30, 900)));
        assert_eq!(adopted_cadences((30, 0), (60, 300)), Some((30, 300)));
        assert_eq!(adopted_cadences((0, 900), (60, 300)), Some((60, 900)));

        // And nothing moved means nothing is written. The identity file holds the machine
        // credential; rewriting it 288 times a day to store the number it already held is
        // 288 chances a day to lose it.
        assert_eq!(adopted_cadences((60, 300), (60, 300)), None);
        assert_eq!(adopted_cadences((0, 0), (60, 300)), None);
        assert_eq!(adopted_cadences((0, 300), (60, 300)), None);
    }
}

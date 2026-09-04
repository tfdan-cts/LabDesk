use crate::{common::do_check_software_update, hbbs_http::create_http_client_with_url_strict};
use hbb_common::{bail, config, log, ResultType};
use std::{
    io::{Read, Write},
    path::{Component, Path, PathBuf},
    sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc::{channel, Receiver, Sender},
        Mutex,
    },
    time::{Duration, Instant},
};

#[cfg(target_os = "macos")]
use std::os::{
    fd::AsRawFd,
    unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
};

#[cfg(target_os = "macos")]
struct MacUpdateLock {
    _file: std::fs::File,
}

#[cfg(target_os = "macos")]
fn acquire_mac_update_lock() -> ResultType<MacUpdateLock> {
    let path = std::path::PathBuf::from("/var/run/rustdesk-update.lock");
    let handle = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .custom_flags(hbb_common::libc::O_NOFOLLOW | hbb_common::libc::O_CLOEXEC)
        .open(&path)?;
    let metadata = handle.metadata()?;
    if !metadata.file_type().is_file() || metadata.uid() != 0 {
        bail!("[root-update] update lock is not a root-owned regular file");
    }
    handle.set_permissions(std::fs::Permissions::from_mode(0o600))?;

    // Keep the descriptor open through update preparation and detached-script
    // launch. O_CLOEXEC means this lock does not cover the detached bundle
    // swap; flock is released when this guard is dropped or the process exits.
    let lock_result = unsafe {
        hbb_common::libc::flock(
            handle.as_raw_fd(),
            hbb_common::libc::LOCK_EX | hbb_common::libc::LOCK_NB,
        )
    };
    if lock_result != 0 {
        let err = std::io::Error::last_os_error();
        if err.kind() == std::io::ErrorKind::WouldBlock {
            bail!("[root-update] another update is already running");
        }
        return Err(err.into());
    }
    Ok(MacUpdateLock { _file: handle })
}

enum UpdateMsg {
    CheckUpdate,
    Exit,
}

lazy_static::lazy_static! {
    static ref TX_MSG : Mutex<Sender<UpdateMsg>> = Mutex::new(start_auto_update_check());
}

static CONTROLLING_SESSION_COUNT: AtomicUsize = AtomicUsize::new(0);

/// Initial wait after startup before the first update check (30 seconds).
pub const INITIAL_CHECK_DELAY: Duration = Duration::from_secs(30);

/// One full day — default interval between update checks.
pub const DUR_ONE_DAY: Duration = Duration::from_secs(60 * 60 * 24);

/// Minimum interval between consecutive update checks (10 minutes).
pub const MIN_INTERVAL: Duration = Duration::from_secs(60 * 10);

/// Retry interval when an update check fails or a session is active (30 minutes).
pub const RETRY_INTERVAL: Duration = Duration::from_secs(60 * 30);

pub fn update_controlling_session_count(count: usize) {
    CONTROLLING_SESSION_COUNT.store(count, Ordering::SeqCst);
}

#[allow(dead_code)]
pub fn start_auto_update() {
    let _sender = TX_MSG.lock().unwrap();
}

#[allow(dead_code)]
pub fn manually_check_update() -> ResultType<()> {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::CheckUpdate)?;
    Ok(())
}

#[allow(dead_code)]
pub fn stop_auto_update() {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::Exit).unwrap_or_default();
}

#[inline]
/// Returns true when there are no active incoming or outgoing connections.
/// Used to avoid updating while a remote session is in progress.
pub fn has_no_active_conns() -> bool {
    let conns = crate::Connection::alive_conns();
    conns.is_empty() && has_no_controlling_conns()
}

#[cfg(any(not(target_os = "windows"), feature = "flutter"))]
fn has_no_controlling_conns() -> bool {
    CONTROLLING_SESSION_COUNT.load(Ordering::SeqCst) == 0
}

#[cfg(not(any(not(target_os = "windows"), feature = "flutter")))]
fn has_no_controlling_conns() -> bool {
    let app_exe = format!("{}.exe", crate::get_app_name().to_lowercase());
    for arg in [
        "--connect",
        "--play",
        "--file-transfer",
        "--view-camera",
        "--port-forward",
        "--rdp",
    ] {
        if !crate::platform::get_pids_of_process_with_first_arg(&app_exe, arg).is_empty() {
            return false;
        }
    }
    true
}

fn start_auto_update_check() -> Sender<UpdateMsg> {
    let (tx, rx) = channel();
    std::thread::spawn(move || start_auto_update_check_(rx));
    return tx;
}

fn start_auto_update_check_(rx_msg: Receiver<UpdateMsg>) {
    std::thread::sleep(INITIAL_CHECK_DELAY);
    if let Err(e) = check_update(false) {
        log::error!("Error checking for updates: {}", e);
    }

    let mut last_check_time = Instant::now();
    let mut check_interval = DUR_ONE_DAY;
    loop {
        let recv_res = rx_msg.recv_timeout(check_interval);
        match &recv_res {
            Ok(UpdateMsg::CheckUpdate) | Err(_) => {
                if last_check_time.elapsed() < MIN_INTERVAL {
                    // log::debug!("Update check skipped due to minimum interval.");
                    continue;
                }
                // Don't check update if there are alive connections.
                if !has_no_active_conns() {
                    check_interval = RETRY_INTERVAL;
                    continue;
                }
                if let Err(e) = check_update(matches!(recv_res, Ok(UpdateMsg::CheckUpdate))) {
                    log::error!("Error checking for updates: {}", e);
                    check_interval = RETRY_INTERVAL;
                } else {
                    last_check_time = Instant::now();
                    check_interval = DUR_ONE_DAY;
                }
            }
            Ok(UpdateMsg::Exit) => break,
        }
    }
}

fn check_update(manually: bool) -> ResultType<()> {
    // On macOS, auto-update is handled by check_update_as_root() in the service process.
    // The shared check_update() path is only used for manual update checks from the GUI.
    #[cfg(target_os = "macos")]
    if !manually {
        return Ok(());
    }
    #[cfg(target_os = "windows")]
    let update_msi = crate::platform::is_msi_installed()? && !crate::is_custom_client();
    if !(manually || config::Config::get_bool_option(config::keys::OPTION_ALLOW_AUTO_UPDATE)) {
        return Ok(());
    }
    if do_check_software_update().is_err() {
        // ignore
        return Ok(());
    }

    let update_url = crate::common::SOFTWARE_UPDATE_URL.lock().unwrap().clone();
    if update_url.is_empty() {
        log::debug!("No update available.");
    } else {
        let download_url = update_url.replace("tag", "download");
        let version = download_url.split('/').last().unwrap_or_default();
        #[cfg(target_os = "windows")]
        let download_url = if cfg!(feature = "flutter") {
            let Some(arch) = crate::platform::windows::release_arch_suffix() else {
                bail!(
                    "Unsupported Windows release architecture: {}",
                    std::env::consts::ARCH
                );
            };
            format!(
                "{}/labdesk-{}-{}.{}",
                download_url,
                version,
                arch,
                if update_msi { "msi" } else { "exe" }
            )
        } else {
            format!("{}/labdesk-{}-x86-sciter.exe", download_url, version)
        };
        log::debug!("New version available: {}", &version);
        // What the asset has to hash to, learned before a byte of it is
        // fetched. There is no unverified path from here: an update whose
        // digest cannot be read is an update that does not happen.
        let expected_sha256 = get_published_sha256(&download_url)?;
        let client = create_http_client_with_url_strict(&download_url)?;
        let Some(file_path) = get_download_file_from_url(&download_url) else {
            bail!("Failed to get the file path from the URL: {}", download_url);
        };
        let mut is_file_exists = false;
        if file_path.exists() {
            // A file left over in the temp directory is reusable only when it
            // is byte for byte the published asset. Its size said nothing
            // about its contents, and any local user can write that directory.
            is_file_exists =
                file_sha256(&file_path).ok().as_deref() == Some(expected_sha256.as_str());
        }
        if !is_file_exists {
            let response = client.get(&download_url).send()?;
            if !response.status().is_success() {
                bail!(
                    "Failed to download the new version file: {}",
                    response.status()
                );
            }
            let file_data = response.bytes()?;
            let mut file = std::fs::File::create(&file_path)?;
            file.write_all(&file_data)?;
        }
        // We have checked if the `conns` is empty before, but we need to check again.
        // No need to care about the downloaded file here, because it's rare case that the `conns` are empty
        // before the download, but not empty after the download.
        if has_no_active_conns() {
            // The installer runs elevated, so it runs on verified bytes or it
            // does not run. `update_new_version` hashes the file as its last
            // act before the handover, after the staging work, so nothing this
            // process does can come between the check and the launch.
            #[cfg(target_os = "windows")]
            update_new_version(update_msi, &version, &file_path, &expected_sha256);
            // Nothing installs on the other desktop platforms from here, but a
            // download that does not match still has to fail the check loudly
            // and be deleted rather than left in the temp directory.
            #[cfg(not(target_os = "windows"))]
            verify_downloaded_file(&file_path, &expected_sha256)?;
        }
    }
    Ok(())
}

/// Hands the downloaded installer to the elevated installer, and hashes it
/// immediately before doing so. The file lives in the temp directory, which
/// every local user can write, so the gap between the check and the launch is
/// the window an attacker gets; everything that can be done first is done
/// first, and the hash is the last thing before the handover.
#[cfg(target_os = "windows")]
fn update_new_version(
    update_msi: bool,
    version: &str,
    file_path: &PathBuf,
    expected_sha256: &str,
) {
    log::debug!(
        "New version is downloaded, update begin, update msi: {update_msi}, version: {version}, file: {:?}",
        file_path.to_str()
    );
    if let Some(p) = file_path.to_str() {
        if let Some(session_id) = crate::platform::get_current_process_session_id() {
            if update_msi {
                if let Err(e) = verify_downloaded_file(file_path, expected_sha256) {
                    log::error!("Refusing to install the new msi version \"{}\": {}", version, e);
                    return;
                }
                match crate::platform::update_me_msi(p, true) {
                    Ok(_) => {
                        log::debug!("New version \"{}\" updated.", version);
                    }
                    Err(e) => {
                        log::error!(
                            "Failed to install the new msi version  \"{}\": {}",
                            version,
                            e
                        );
                        std::fs::remove_file(&file_path).ok();
                    }
                }
            } else {
                let custom_client_staging_dir = if crate::is_custom_client() {
                    let custom_client_staging_dir =
                        crate::platform::get_custom_client_staging_dir();
                    if let Err(e) = crate::platform::handle_custom_client_staging_dir_before_update(
                        &custom_client_staging_dir,
                    ) {
                        log::error!(
                            "Failed to handle custom client staging dir before update: {}",
                            e
                        );
                        std::fs::remove_file(&file_path).ok();
                        return;
                    }
                    Some(custom_client_staging_dir)
                } else {
                    // Clean up any residual staging directory from previous custom client
                    let staging_dir = crate::platform::get_custom_client_staging_dir();
                    hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                        &staging_dir
                    ));
                    None
                };
                // Last act before the elevated launch, after the staging work,
                // so the file is not touched again between here and there.
                if let Err(e) = verify_downloaded_file(file_path, expected_sha256) {
                    log::error!("Refusing to install the new version \"{}\": {}", version, e);
                    if let Some(dir) = custom_client_staging_dir.as_deref() {
                        hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                            dir
                        ));
                    }
                    return;
                }
                let update_launched = match crate::platform::launch_privileged_process(
                    session_id,
                    &format!("{} --update", p),
                ) {
                    Ok(h) => {
                        if h.is_null() {
                            log::error!("Failed to update to the new version: {}", version);
                            false
                        } else {
                            log::debug!("New version \"{}\" is launched.", version);
                            true
                        }
                    }
                    Err(e) => {
                        log::error!("Failed to run the new version: {}", e);
                        false
                    }
                };
                if !update_launched {
                    if let Some(dir) = custom_client_staging_dir {
                        hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                            &dir
                        ));
                    }
                    std::fs::remove_file(&file_path).ok();
                }
            }
        } else {
            log::error!(
                "Failed to get the current process session id, Error {}",
                std::io::Error::last_os_error()
            );
            std::fs::remove_file(&file_path).ok();
        }
    } else {
        // unreachable!()
        log::error!(
            "Failed to convert the file path to string: {}",
            file_path.display()
        );
    }
}

/// The hosts an update may be fetched from, and the path shape under each.
/// Upstream: `https://github.com/rustdesk/rustdesk/releases/download/<tag>/<file>`.
/// LabDesk: `https://lab-desk.net/releases/download/<version>/<file>`, which the
/// site streams from the release its administrator made public.
pub fn get_update_download_file_from_url(url: &str) -> Option<PathBuf> {
    let parsed = url::Url::parse(url).ok()?;
    let labdesk_host = crate::common::LABDESK_SITE.trim_start_matches("https://");
    let (prefix, host, repo_segments) = if url.starts_with("https://github.com/") {
        ("https://github.com/", "github.com", 2)
    } else if url.starts_with(&format!("https://{}/", labdesk_host)) {
        ("", labdesk_host, 0)
    } else {
        return None;
    };
    // Check the raw prefix before Url normalizes default ports.
    if (!prefix.is_empty() && !url.starts_with(prefix))
        || parsed.scheme() != "https"
        || parsed.host_str() != Some(host)
        || !parsed.username().is_empty()
        || parsed.password().is_some()
        || parsed.port().is_some()
        || parsed.query().is_some()
        || parsed.fragment().is_some()
    {
        return None;
    }

    let mut segments = parsed.path_segments()?;
    if repo_segments == 2 {
        let owner = segments.next()?;
        let repo = segments.next()?;
        if owner != "rustdesk" || repo != "rustdesk" {
            return None;
        }
    }
    let releases = segments.next()?;
    let download = segments.next()?;
    let tag = segments.next()?;
    let filename = segments.next()?;

    if releases != "releases"
        || download != "download"
        || tag.is_empty()
        || segments.next().is_some()
        || !is_plain_update_filename(filename)
    {
        return None;
    }

    Some(std::env::temp_dir().join(filename))
}

fn is_plain_update_filename(filename: &str) -> bool {
    if filename.is_empty()
        || filename.contains('/')
        || filename.contains('\\')
        || filename.contains(':')
    {
        return false;
    }

    let mut components = Path::new(filename).components();
    matches!(
        components.next(),
        Some(Component::Normal(name)) if name.to_str() == Some(filename)
    ) && components.next().is_none()
}

/// The temp path an update from `url` is downloaded to. This says nothing at
/// all about the file's contents: a path coming back from here is not a
/// vouched-for installer, and every local user can write that directory. Any
/// caller about to hand the file to an elevated or root installer must call
/// [verify_update_file] with the same URL first.
pub fn get_download_file_from_url(url: &str) -> Option<PathBuf> {
    get_update_download_file_from_url(url)
}

/// Where the site serves a release asset, and where it publishes that asset's
/// SHA-256. The digest is produced by the release pipeline and uploaded to the
/// release as `SHA256SUMS`; the site reads it from there and serves one line
/// of it per asset.
const RELEASE_DOWNLOAD_PATH: &str = "/releases/download/";
const RELEASE_CHECKSUM_PATH: &str = "/releases/checksums/";

/// The URL that publishes the SHA-256 of the asset at `download_url`.
/// None for anything that is not a LabDesk release asset, including upstream
/// GitHub, which publishes no digest. Refusing to install what cannot be
/// verified is the point, so there is deliberately no fallback here.
pub fn get_update_checksum_url(download_url: &str) -> Option<String> {
    // Only a URL the release allowlist already accepted may be asked about.
    get_update_download_file_from_url(download_url)?;
    let prefix = format!("{}{}", crate::common::LABDESK_SITE, RELEASE_DOWNLOAD_PATH);
    let rest = download_url.strip_prefix(&prefix)?;
    Some(format!(
        "{}{}{}",
        crate::common::LABDESK_SITE,
        RELEASE_CHECKSUM_PATH,
        rest
    ))
}

/// A SHA-256 as the site publishes it: 64 hex characters and nothing else.
fn is_sha256_hex(digest: &str) -> bool {
    digest.len() == 64 && digest.bytes().all(|b| b.is_ascii_hexdigit())
}

/// The SHA-256 the release publishes for the asset at `download_url`.
/// Every failure is fatal to the update by design.
pub fn get_published_sha256(download_url: &str) -> ResultType<String> {
    let Some(checksum_url) = get_update_checksum_url(download_url) else {
        bail!(
            "No published SHA-256 for the update URL, refusing to install: {}",
            download_url
        );
    };
    let client = create_http_client_with_url_strict(&checksum_url)?;
    let response = client.get(&checksum_url).send()?;
    if !response.status().is_success() {
        // Worth spelling out: this freezes the update channel until the
        // release publishes SHA256SUMS, which is the whole reason a release
        // has to be checksummed before the channel is pointed at it.
        bail!(
            "The release publishes no SHA-256 for this asset ({} returned {}), so no update can be installed",
            checksum_url,
            response.status()
        );
    }
    // A digest is 64 bytes. Reading a bounded prefix keeps a hostile or broken
    // endpoint from being read into memory without limit.
    let mut body = String::new();
    response.take(128).read_to_string(&mut body)?;
    digest_from_response_body(&body)
}

/// The digest a response body carries, or an error. An error page, an empty
/// body or a truncated digest all land here and all stop the update, so the
/// hash comparison is never reached with something that is not a digest.
fn digest_from_response_body(body: &str) -> ResultType<String> {
    let digest = body.trim().to_lowercase();
    if !is_sha256_hex(&digest) {
        bail!("The published SHA-256 is not a hex digest");
    }
    Ok(digest)
}

/// The SHA-256 of a file on disk, as lowercase hex. Read in blocks so an
/// installer of any size is hashed in constant memory.
fn file_sha256(path: &Path) -> ResultType<String> {
    use sha2::{Digest, Sha256};
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buf)?;
        if read == 0 {
            break;
        }
        hasher.update(&buf[..read]);
    }
    Ok(hex::encode(hasher.finalize()))
}

/// Passes only a file whose SHA-256 is the published one. Anything else is
/// deleted, so no later run can mistake it for a download that was vouched for.
pub fn verify_downloaded_file(file_path: &Path, expected_sha256: &str) -> ResultType<()> {
    let actual = match file_sha256(file_path) {
        Ok(actual) => actual,
        Err(e) => {
            std::fs::remove_file(file_path).ok();
            return Err(e);
        }
    };
    if actual != expected_sha256 {
        std::fs::remove_file(file_path).ok();
        bail!(
            "The downloaded update does not match the published SHA-256: expected {}, got {}",
            expected_sha256,
            actual
        );
    }
    Ok(())
}

/// The whole check in one call: fetch the digest the site publishes for
/// `download_url`, then hash the file that was downloaded from it, deleting
/// the file and failing if the two do not agree.
///
/// This exists for callers that download an update themselves and want the
/// whole check in one call, without an elevated install waiting on the other
/// side of it. The Flutter UI's "extract-update-dmg" handler is the one such
/// caller: it opens the downloaded disk image to show the user what is in it,
/// before anything has been asked or elevated.
///
/// A caller that IS about to install must not use this. It fetches the digest
/// with [get_published_sha256] and hands that digest to
/// `crate::platform::update_to`, which checks it against the file as the last
/// act before the elevated launch, the same ordering `update_new_version`
/// follows. Hashing here and installing later leaves a window in a directory
/// every local user can write.
#[allow(dead_code)]
pub fn verify_update_file(download_url: &str, file_path: &Path) -> ResultType<()> {
    let expected_sha256 = get_published_sha256(download_url)?;
    verify_downloaded_file(file_path, &expected_sha256)
}

/// Queries all active connections (remote, file-transfer, port-forward, camera, terminal)
/// from every logged-in user's --server process via IPC.
/// The root service cannot read connection state directly since connections
/// live in user --server processes. Handles fast user switching by querying
/// all GUI users, including the login-window server at UID 0. Falls back to
/// false (assumes sessions active) on any IPC error to avoid updating during
/// an unknown session state.
#[cfg(target_os = "macos")]
pub fn has_no_active_conns_ipc() -> bool {
    let rt = match hbb_common::tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(_) => return false,
    };
    rt.block_on(async {
        // Use the same GUI-domain-filtered UID set as the update script.
        // Shell-only SSH/TTY users are excluded, while an empty GUI set maps
        // to UID 0 so the LoginWindow server is queried rather than assumed idle.
        let uids = crate::platform::get_logged_in_uids();
        // Check each user's server — fail closed if any has active connections
        for uid in uids {
            if let Ok(mut conn) = crate::ipc::connect_for_uid(1000, uid, "").await {
                if conn.send(&crate::ipc::Data::HasNoActiveConns(None)).await.is_ok() {
                    match conn.next_timeout(1000).await {
                        Ok(Some(crate::ipc::Data::HasNoActiveConns(Some(true)))) => {
                            // Explicit no active connections — safe to continue
                        }
                        Ok(Some(crate::ipc::Data::HasNoActiveConns(Some(false)))) => {
                            return false; // Explicit active connections
                        }
                        _ => {
                            return false; // Timeout/error/unexpected — fail closed
                        }
                    }
                } else {
                    return false; // Send failed — fail closed
                }
            } else {
                return false; // Connection failed — fail closed
            }
        }
        true // All users explicitly confirmed no active connections
    })
}

#[cfg(target_os = "macos")]
fn wait_for_failed_update_retry() {
    const FAILURE_MARKER: &str = "/var/root/.rustdeskupdate_failed";
    let marker = std::path::Path::new(FAILURE_MARKER);
    if !marker.exists() {
        return;
    }

    // The updater script records failure immediately before launchd restarts
    // the old daemon. Preserve the retry deadline across that restart instead
    // of consuming the marker and retrying the same broken release in 30 sec.
    let remaining = std::fs::metadata(marker)
        .and_then(|metadata| metadata.modified())
        .ok()
        .and_then(|modified| {
            std::time::SystemTime::now()
                .duration_since(modified)
                .ok()
        })
        .map(|elapsed| RETRY_INTERVAL.saturating_sub(elapsed))
        .unwrap_or(RETRY_INTERVAL);
    if !remaining.is_zero() {
        log::info!(
            "[root-update] Previous update failed; retrying in {} seconds.",
            remaining.as_secs()
        );
        std::thread::sleep(remaining);
    }
    match std::fs::remove_file(marker) {
        Ok(()) => log::info!("[root-update] Previous update retry interval elapsed."),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => log::warn!("[root-update] Failed to clear failure marker: {}", err),
    }
}

/// Starts the background silent auto-update scheduler for macOS.
/// Called from `start_os_service()` which runs as root via LaunchDaemon.
#[cfg(target_os = "macos")]
pub fn start_auto_update_macos() {
    let spawn_result = std::thread::Builder::new()
        .name("rustdesk-auto-update".to_owned())
        .spawn(|| {
            log::info!("[root-update] Auto-update scheduler thread started.");
            std::thread::sleep(INITIAL_CHECK_DELAY);
            wait_for_failed_update_retry();
            let mut interval = DUR_ONE_DAY;
            loop {
                log::info!("[root-update] Running scheduled update check...");
                let no_active_conns = has_no_active_conns_ipc();
                if !no_active_conns {
                    log::info!("[root-update] Active session in progress, retrying in 10 min.");
                    interval = MIN_INTERVAL;
                } else {
                    match check_update_as_root() {
                        Ok(update_started) => {
                            if update_started {
                                // The replacement script is detached and may fail
                                // after this process returns. Always retry at the
                                // failure interval until the new daemon replaces us.
                                interval = RETRY_INTERVAL;
                            } else {
                                interval = DUR_ONE_DAY;
                            }
                        }
                        Err(e) => {
                            log::error!("[root-update] Update check failed: {}", e);
                            interval = RETRY_INTERVAL;
                        }
                    }
                }
                std::thread::sleep(interval);
            }
        });
    if let Err(err) = spawn_result {
        log::error!("[root-update] Failed to start scheduler thread: {}", err);
    }
}

#[cfg(target_os = "macos")]
pub fn check_update_as_root() -> ResultType<bool> {
    let _update_lock = acquire_mac_update_lock()?;
    // Allow-auto-update setting
    if !config::Config::get_bool_option(config::keys::OPTION_ALLOW_AUTO_UPDATE) {
        log::info!("[root-update] Auto update is disabled, skipping.");
        return Ok(false);
    }
    if crate::is_custom_client() {
        log::info!("[root-update] Custom client detected, skipping stock update.");
        return Ok(false);
    }
    // Clean up only old temp dirs from previous failed updates. The detached
    // installer keeps using its update directory after this process exits and
    // releases the advisory lock, so a newly-started daemon must not remove a
    // directory that still belongs to the active transaction.
    if let Ok(entries) = std::fs::read_dir("/tmp") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name_str = name.to_string_lossy();
            if name_str.starts_with(".rustdeskupdate-root-")
                || name_str.starts_with(".rustdeskdownload-")
            {
                let path = entry.path();
                let Ok(metadata) = std::fs::symlink_metadata(&path) else {
                    continue;
                };
                let mode = metadata.mode() & 0o7777;
                let is_stale = metadata
                    .modified()
                    .ok()
                    .and_then(|modified| std::time::SystemTime::now().duration_since(modified).ok())
                    .is_some_and(|age| age >= RETRY_INTERVAL);
                if metadata.file_type().is_dir() && metadata.uid() == 0 && mode == 0o700 && is_stale
                {
                    if let Err(err) = std::fs::remove_dir_all(&path) {
                        log::warn!(
                            "[root-update] Failed to remove stale temp dir {}: {}",
                            path.display(),
                            err
                        );
                    }
                }
            }
        }
    }
    if let Err(e) = do_check_software_update() {
        bail!("[root-update] Failed to check for software update: {}", e);
    }
    let update_url = crate::common::SOFTWARE_UPDATE_URL.lock().unwrap().clone();
    if update_url.is_empty() {
        log::info!("[root-update] No update available.");
        return Ok(false);
    }
    let download_url = update_url.replace("tag", "download");
    let version = download_url.split('/').last().unwrap_or_default().to_string();
    let arch = if std::env::consts::ARCH == "aarch64" { "aarch64" } else { "x86_64" };
    let dmg_url = format!("{}/labdesk-{}-{}.dmg", download_url, version, arch);
    log::info!("[root-update] New version: {}, downloading from {}", version, dmg_url);
    // Validate URL against GitHub release allowlist before downloading as root
    let Some(file_path_validated) = get_update_download_file_from_url(&dmg_url) else {
        bail!("[root-update] URL failed allowlist check: {}", dmg_url);
    };
    drop(file_path_validated);
    // What the disk image has to hash to, learned before it is fetched. A root
    // installer is never pointed at bytes nobody vouched for.
    let expected_sha256 = get_published_sha256(&dmg_url)?;
    let client = create_http_client_with_url_strict(&dmg_url)?;
    // Use mktemp so a local user cannot pre-create a predictable path and
    // permanently deny updates for a reused service PID.
    let private_tmp_output = std::process::Command::new("/usr/bin/mktemp")
        .args(["-d", "/tmp/.rustdeskdownload-XXXXXX"])
        .output()?;
    if !private_tmp_output.status.success() {
        bail!(
            "[root-update] Failed to create private download directory: {}",
            String::from_utf8_lossy(&private_tmp_output.stderr).trim()
        );
    }
    let private_tmp = String::from_utf8(private_tmp_output.stdout)
        .map_err(|err| hbb_common::anyhow::anyhow!("[root-update] mktemp output error: {}", err))?
        .trim()
        .to_owned();
    if private_tmp.is_empty() {
        bail!("[root-update] mktemp returned an empty download directory");
    }
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&private_tmp, std::fs::Permissions::from_mode(0o700))?;
    }
    let filename = dmg_url.split('/').last().unwrap_or("rustdesk.dmg");
    let file_path = std::path::PathBuf::from(format!("{}/{}", private_tmp, filename));
    let tmp_path = file_path.to_string_lossy().to_string();
    // Download
    let mut response = client.get(&dmg_url).send()?;
    if !response.status().is_success() {
        let _ = std::fs::remove_dir_all(&private_tmp);
        bail!("[root-update] Failed to download: {}", response.status());
    }
    // Create file exclusively (O_EXCL) and stream response directly into it
    {
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&file_path)
            .map_err(|e| { let _ = std::fs::remove_dir_all(&private_tmp); e })?;
        std::io::copy(&mut response, &mut file)
            .map_err(|e| { let _ = std::fs::remove_dir_all(&private_tmp); e })?;
    }
    log::info!("[root-update] Downloaded to {}", tmp_path);
    // Recheck active sessions before installing — download can take minutes
    if !has_no_active_conns_ipc() {
        if let Err(e) = std::fs::remove_dir_all(&private_tmp) {
            log::warn!("[root-update] Failed to remove temp dir {}: {}", private_tmp, e);
        }
        bail!("[root-update] Active session started during download, deferring update.");
    }
    // The installer runs as root, so it runs on verified bytes or it does not
    // run. Checked here, immediately before the disk image is handed over.
    if let Err(e) = verify_downloaded_file(&file_path, &expected_sha256) {
        if let Err(err) = std::fs::remove_dir_all(&private_tmp) {
            log::warn!(
                "[root-update] Failed to remove temp dir {}: {}",
                private_tmp,
                err
            );
        }
        return Err(e);
    }
    // Install silently as root
    let result = crate::platform::update_from_dmg_as_root(&tmp_path, &version);
    // Clean up download directory
    if let Err(e) = std::fs::remove_dir_all(&private_tmp) {
        log::warn!("[root-update] Failed to remove temp dir {}: {}", private_tmp, e);
    }
    result.map(|_| true)
}

#[cfg(test)]
mod tests {
    use super::{
        digest_from_response_body, file_sha256, get_download_file_from_url,
        get_update_checksum_url, is_sha256_hex, verify_downloaded_file,
    };

    #[test]
    fn update_download_file_accepts_expected_github_asset_urls() {
        let file = get_download_file_from_url(
            "https://github.com/rustdesk/rustdesk/releases/download/1.4.0/rustdesk-1.4.0-x86_64.dmg",
        )
        .expect("valid GitHub release asset URL");

        assert_eq!(
            file.file_name().and_then(|name| name.to_str()),
            Some("rustdesk-1.4.0-x86_64.dmg")
        );
    }

    #[test]
    fn update_download_file_accepts_labdesk_site_asset_urls() {
        let file = get_download_file_from_url(
            "https://lab-desk.net/releases/download/1.2.0/rustdesk-1.2.0-x86_64.exe",
        )
        .expect("valid lab-desk.net release asset URL");
        assert_eq!(
            file.file_name().and_then(|name| name.to_str()),
            Some("rustdesk-1.2.0-x86_64.exe")
        );
        for url in [
            "http://lab-desk.net/releases/download/1.2.0/rustdesk-1.2.0-x86_64.exe",
            "https://lab-desk.net/rustdesk-1.2.0-x86_64.exe",
            "https://lab-desk.net/releases/download/1.2.0/",
            "https://lab-desk.net/releases/download/1.2.0/nested/rustdesk.exe",
            "https://lab-desk.net/releases/download/1.2.0/rustdesk.exe?x=1",
            "https://lab-desk.net.evil.com/releases/download/1.2.0/rustdesk.exe",
            "https://evil.com/lab-desk.net/releases/download/1.2.0/rustdesk.exe",
        ] {
            assert!(get_download_file_from_url(url).is_none(), "{url}");
        }
    }

    #[test]
    fn update_download_file_rejects_untrusted_or_malformed_urls() {
        for url in [
            "http://github.com/rustdesk/rustdesk/releases/download/1/rustdesk.exe",
            "https://example.com/rustdesk.exe",
            "https://github.com/other/project/releases/download/1/rustdesk.exe",
            "https://github.com/rustdesk/rustdesk/releases/download/1/",
            "https://github.com/rustdesk/rustdesk/releases/download/1/nested/rustdesk.exe",
            "https://github.com/rustdesk/rustdesk/releases/download/1/C:rustdesk.exe",
            "https://user@github.com/rustdesk/rustdesk/releases/download/1/rustdesk.exe",
            "https://github.com:443/rustdesk/rustdesk/releases/download/1/rustdesk.exe",
            "https://github.com/rustdesk/rustdesk/releases/download/1/rustdesk.exe?download=1",
            "https://github.com/rustdesk/rustdesk/releases/download/1/rustdesk.exe#download",
            "not a url",
        ] {
            assert!(get_download_file_from_url(url).is_none(), "{url}");
        }
    }

    #[test]
    fn a_digest_url_exists_only_for_a_labdesk_release_asset() {
        assert_eq!(
            get_update_checksum_url(
                "https://lab-desk.net/releases/download/1.2.0/labdesk-1.2.0-x86_64.exe"
            )
            .as_deref(),
            Some("https://lab-desk.net/releases/checksums/1.2.0/labdesk-1.2.0-x86_64.exe")
        );
        for url in [
            // Upstream GitHub publishes no digest, so nothing fetched from it
            // can be verified, so nothing fetched from it may be installed.
            "https://github.com/rustdesk/rustdesk/releases/download/1.4.0/rustdesk-1.4.0-x86_64.dmg",
            "http://lab-desk.net/releases/download/1.2.0/labdesk-1.2.0-x86_64.exe",
            "https://lab-desk.net/releases/download/1.2.0/nested/labdesk.exe",
            "https://lab-desk.net/releases/download/1.2.0/labdesk.exe?x=1",
            "https://lab-desk.net.evil.com/releases/download/1.2.0/labdesk.exe",
            "https://evil.com/lab-desk.net/releases/download/1.2.0/labdesk.exe",
            "not a url",
        ] {
            assert!(get_update_checksum_url(url).is_none(), "{url}");
        }
    }

    #[test]
    fn an_update_that_does_not_match_the_published_digest_is_refused_and_deleted() {
        // Process-unique so two test binaries on one runner cannot collide.
        let path = std::env::temp_dir().join(format!(
            "labdesk-update-verify-test-{}.bin",
            std::process::id()
        ));
        std::fs::write(&path, b"labdesk installer").expect("write the test payload");

        // A known vector, so this proves the digest is really SHA-256 and not
        // merely self-consistent.
        let digest = file_sha256(&path).expect("hash the test payload");
        assert!(is_sha256_hex(&digest));
        assert_eq!(
            digest,
            "460de39d0bfc73247f2f143b4a83d255a00a53620a116fca20af1f7963b7a2c5"
        );

        verify_downloaded_file(&path, &digest).expect("the published digest verifies");
        assert!(path.exists(), "a verified file is kept for the installer");

        let wrong = "0".repeat(64);
        assert!(
            verify_downloaded_file(&path, &wrong).is_err(),
            "a mismatched file is refused"
        );
        assert!(
            !path.exists(),
            "a file that failed verification is deleted, not left for a later run"
        );
    }

    #[test]
    fn a_response_body_that_is_not_a_digest_is_refused() {
        // The site serves the bare digest with a trailing newline, and an
        // uppercase digest is the same digest.
        assert_eq!(
            digest_from_response_body(
                "  460DE39D0BFC73247F2F143B4A83D255A00A53620A116FCA20AF1F7963B7A2C5\n"
            )
            .ok()
            .as_deref(),
            Some("460de39d0bfc73247f2f143b4a83d255a00a53620a116fca20af1f7963b7a2c5")
        );
        // An error page, an empty body or a truncated digest must stop the
        // update rather than reach the hash comparison.
        for bad in [
            "",
            "<html>404 Not Found</html>",
            "460de39d0bfc73247f2f143b4a83d255a00a53620a116fca20af1f7963b7a2c",
            "460de39d0bfc73247f2f143b4a83d255a00a53620a116fca20af1f7963b7a2c5 labdesk.exe",
        ] {
            assert!(digest_from_response_body(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn only_a_full_hex_digest_is_accepted() {
        assert!(is_sha256_hex(
            "460de39d0bfc73247f2f143b4a83d255a00a53620a116fca20af1f7963b7a2c5"
        ));
        for bad in [
            "",
            "460de39d0bfc73247f2f143b4a83d255a00a53620a116fca20af1f7963b7a2c",
            "460de39d0bfc73247f2f143b4a83d255a00a53620a116fca20af1f7963b7a2c55",
            "460de39d0bfc73247f2f143b4a83d255a00a53620a116fca20af1f7963b7a2cz",
        ] {
            assert!(!is_sha256_hex(bad), "{bad}");
        }
    }
}

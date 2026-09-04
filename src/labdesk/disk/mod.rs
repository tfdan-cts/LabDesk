// Disk health: the pure layer.
//
// Everything in this module is a total function over bytes. No I/O, no platform
// calls, no allocation beyond the returned collections. The platform layer
// (windows.rs / linux.rs / macos.rs) issues the DeviceIoControl / ioctl and hands
// the raw output buffer here; nothing here knows how the buffer was obtained.
// That is what lets these parsers be tested on a diskless, unprivileged CI runner
// from committed byte fixtures.
//
// The one rule the whole module exists to enforce: a buffer we could not read is
// `Verdict::Unreadable`, never `Verdict::Ok`. "The disk is fine" and "we could not
// ask" are different sentences and the console renders them differently.

pub mod ata;
pub mod nvme;
pub mod verdict;

// The platform layer: the only code in this module that touches a device. Each
// one issues its operating system's ioctls and hands the raw output buffers to
// the parsers above. Compiled one at a time, so a bad Windows constant is
// invisible to a Linux build and vice versa; see the notes at the top of each
// file for the privilege every call needs.
#[cfg(target_os = "linux")]
pub mod linux;
#[cfg(target_os = "macos")]
pub mod macos;
#[cfg(target_os = "windows")]
pub mod windows;

pub use ata::{checksum_ok, parse_ata_attributes, parse_ata_thresholds, AtaAttr, AtaSummary};
pub use nvme::{parse_nvme_health, NvmeHealth};
pub use verdict::{verdict, Source, Verdict};

/// Every structure this module parses is exactly 512 bytes: the ATA SMART
/// READ_ATTRIBUTES buffer (`READ_ATTRIBUTE_BUFFER_SIZE`), the ATA
/// READ_THRESHOLDS buffer (`READ_THRESHOLD_BUFFER_SIZE`) and the NVMe SMART /
/// Health Information log page (log identifier 02h).
pub const BUF_LEN: usize = 512;

/// Why a buffer carried no reading.
///
/// Both variants mean the same thing to the caller: record `Verdict::Unreadable`
/// and a `health_source` of `none` for this call. Neither is ever an excuse to
/// report zeroed counters as a healthy drive.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiskParseError {
    /// The buffer is shorter than the fixed-size structure the device owed us.
    /// A short read is the normal shape of a USB bridge or RAID controller that
    /// accepted the ioctl and then answered with less than it promised.
    TooShort { got: usize, need: usize },
    /// The buffer is the right length but carries no reading at all: an ioctl
    /// that failed quietly leaves the output buffer exactly as the caller zeroed
    /// it, and a table of zero attributes is indistinguishable from that.
    Empty,
}

impl std::fmt::Display for DiskParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::TooShort { got, need } => write!(f, "buffer too short: {} bytes, need {}", got, need),
            Self::Empty => write!(f, "buffer carries no reading"),
        }
    }
}

impl std::error::Error for DiskParseError {}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;

    /// Regenerate the committed byte fixtures from the builders in `ata::fixture`
    /// and `nvme::fixture`, which document every field they set:
    ///
    ///   LABDESK_WRITE_FIXTURES=1 cargo test -p rustdesk labdesk::disk::write_fixtures
    ///
    /// It is inert without that variable, so a normal test run never writes to
    /// the source tree. `fixtures_match_builders` in ata.rs and nvme.rs is what
    /// proves the committed bytes and the builders have not drifted apart.
    #[test]
    fn write_fixtures() {
        if std::env::var_os("LABDESK_WRITE_FIXTURES").is_none() {
            return;
        }
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src/labdesk/disk/fixtures");
        fs::create_dir_all(&dir).unwrap();
        let ata_healthy = super::ata::fixture::healthy();
        let ata_failing = super::ata::fixture::failing();
        let ata_thresholds = super::ata::fixture::thresholds();
        let nvme_ok = super::nvme::fixture::healthy();
        let nvme_failing = super::nvme::fixture::failing();
        // An untouched output buffer: what a quietly failed ioctl leaves.
        let zeros = [0u8; super::BUF_LEN];
        let files: [(&str, &[u8]); 6] = [
            ("ata_attrs_healthy.bin", &ata_healthy),
            ("ata_attrs_failing.bin", &ata_failing),
            ("ata_thresholds.bin", &ata_thresholds),
            ("nvme_health_ok.bin", &nvme_ok),
            ("nvme_health_failing.bin", &nvme_failing),
            ("malformed_zeros.bin", &zeros),
        ];
        for (name, bytes) in files {
            fs::write(dir.join(name), bytes).unwrap();
        }
        // A short read: the first 100 bytes of a real attribute table, which is
        // the shape a USB bridge returns when it accepts the command and then
        // answers with less than it promised.
        fs::write(dir.join("malformed_short.bin"), &ata_healthy[..100]).unwrap();
    }
}

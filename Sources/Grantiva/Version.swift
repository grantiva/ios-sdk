import Foundation

/// The single source of truth for the SDK's version string.
///
/// Updated automatically by the release workflow (`.github/workflows/release.yml`) — it bumps
/// this value, commits it, and creates the matching git tag + GitHub release. Do not edit by
/// hand; run the **Release** workflow instead.
public enum GrantivaVersion {
    public static let current = "2.1.0"
}

import Foundation

/// The APNs environment a device token was minted for.
///
/// Apple issues device tokens that are only valid against one APNs environment.
/// The backend needs to know which one so it routes pushes through the matching
/// APNs host (sandbox vs production). The raw values match the server's
/// `pushEnvironment` field exactly.
public enum PushEnvironment: String, Codable, Sendable {
    /// Development builds (Xcode run, `aps-environment: development`). Routed via
    /// APNs sandbox.
    case sandbox
    /// App Store and TestFlight builds (`aps-environment: production`). Routed via
    /// APNs production.
    case production

    /// Best-effort detection of the current build's APNs environment.
    ///
    /// Reads the `aps-environment` entitlement embedded in the app's provisioning
    /// profile (`embedded.mobileprovision`). App Store builds strip the profile, so
    /// when it's absent we fall back to the build configuration: `DEBUG` → `.sandbox`,
    /// release → `.production`.
    ///
    /// Pass an explicit `PushEnvironment` to `setPushToken(_:environment:)` if your
    /// build pipeline doesn't fit these heuristics.
    public static var detected: PushEnvironment {
        if let apsEnvironment = provisioningAPSEnvironment() {
            return apsEnvironment == "development" ? .sandbox : .production
        }
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }

    /// Parses the `aps-environment` value out of `embedded.mobileprovision`, or `nil`
    /// when no profile is bundled (e.g. App Store builds, the simulator).
    private static func provisioningAPSEnvironment() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url),
              // The profile is CMS-wrapped binary with an embedded plist; scan the
              // ASCII payload rather than decoding the signature.
              let text = String(data: raw, encoding: .ascii) else {
            return nil
        }

        // Look for: <key>aps-environment</key><string>development|production</string>
        guard let keyRange = text.range(of: "aps-environment"),
              let openTag = text.range(of: "<string>", range: keyRange.upperBound..<text.endIndex),
              let closeTag = text.range(of: "</string>", range: openTag.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[openTag.upperBound..<closeTag.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

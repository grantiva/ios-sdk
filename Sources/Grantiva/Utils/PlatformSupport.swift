import Foundation
import CryptoKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import IOKit
#endif

internal class PlatformSupport {

    /// Returns a SHA256 hex digest of the device identifier. Sent to the backend
    /// for MAD dedupe across the self-heal key-regeneration path. The raw
    /// identifier (IDFV on iOS, IOPlatformSerialNumber on macOS) is never
    /// transmitted — only its hash, which is opaque to the server.
    ///
    /// On iOS the IDFV changes when the user uninstalls the last app from this
    /// vendor; for the dedupe use case (same install, same month) it is stable.
    static func getDeviceFingerprint() -> String? {
        let raw = getDeviceIdentifier()
        guard raw != "unknown" else {
            return nil
        }
        let hash = SHA256.hash(data: Data(raw.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func getDeviceIdentifier() -> String {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        #elseif os(macOS)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != IO_OBJECT_NULL else { return "unknown" }
        defer { IOObjectRelease(service) }

        // `IORegistryEntryCreateCFProperty` follows the Create rule, so the
        // returned reference is +1 and must be taken retained or it leaks.
        guard let property = IORegistryEntryCreateCFProperty(service, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let serialNumber = property as? String else {
            return "unknown"
        }
        return serialNumber
        #else
        return "unknown"
        #endif
    }

    /// Returns the hardware model identifier (e.g. "iPhone14,2", "MacBookPro18,1").
    /// Uses sysctl to get the real identifier, not the marketing name.
    static func getHardwareModel() -> String {
        #if targetEnvironment(simulator)
        // In the simulator, "hw.machine" returns the Mac's architecture.
        // Use SIMULATOR_MODEL_IDENTIFIER environment variable instead.
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        #else
        // On iOS "hw.machine" is the model ("iPhone14,2"); on macOS it is the CPU
        // architecture ("arm64") and the model lives under "hw.model".
        #if os(macOS)
        let key = "hw.model"
        #else
        let key = "hw.machine"
        #endif
        var size: Int = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var machine = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(key, &machine, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: machine.prefix { $0 != 0 }, as: UTF8.self)
        #endif
    }

    /// Returns the OS version string (e.g. "18.2", "15.1.1").
    static func getOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.patchVersion == 0 {
            return "\(version.majorVersion).\(version.minorVersion)"
        }
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// Returns the app's marketing version (CFBundleShortVersionString), e.g. "2.3.1".
    static func getAppVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Returns the app's build number (CFBundleVersion), e.g. "42".
    static func getAppBuildNumber() -> String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    static func getSystemInfo() -> [String: String] {
        var info: [String: String] = [:]

        #if os(iOS)
        info["model"] = getHardwareModel()
        info["systemName"] = UIDevice.current.systemName
        info["systemVersion"] = getOSVersion()
        info["platform"] = "iOS"
        #elseif os(macOS)
        info["model"] = getHardwareModel()
        info["systemName"] = "macOS"
        info["systemVersion"] = getOSVersion()
        info["platform"] = "macOS"
        #endif

        if let appVersion = getAppVersion() {
            info["appVersion"] = appVersion
        }

        #if targetEnvironment(simulator)
        info["environment"] = "simulator"
        #else
        info["environment"] = "device"
        #endif

        return info
    }
}
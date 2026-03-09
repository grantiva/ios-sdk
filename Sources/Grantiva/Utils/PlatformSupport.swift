import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import IOKit
#endif

internal class PlatformSupport {

    static func getDeviceIdentifier() -> String {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        #elseif os(macOS)
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        var serialNumber: String = "unknown"

        if let serialNumberAsCFString = IORegistryEntryCreateCFProperty(service, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0)?.takeUnretainedValue() {
            if CFGetTypeID(serialNumberAsCFString) == CFStringGetTypeID() {
                serialNumber = String(serialNumberAsCFString as! CFString)
            }
        }

        IOObjectRelease(service)
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
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
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
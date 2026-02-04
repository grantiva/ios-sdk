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
    
    static func getSystemInfo() -> [String: String] {
        var info: [String: String] = [:]
        
        #if os(iOS)
        info["model"] = UIDevice.current.model
        info["systemName"] = UIDevice.current.systemName
        info["systemVersion"] = UIDevice.current.systemVersion
        info["platform"] = "iOS"
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        info["model"] = "Mac"
        info["systemName"] = "macOS"
        info["systemVersion"] = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        info["platform"] = "macOS"
        #endif
        
        #if targetEnvironment(simulator)
        info["environment"] = "simulator"
        #else
        info["environment"] = "device"
        #endif
        
        return info
    }
}
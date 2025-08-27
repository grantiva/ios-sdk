import Foundation
import DeviceCheck

internal class DeviceCompatibility {
    
    static func checkCompatibility() throws {
        guard #available(iOS 14.0, *) else {
            throw GrantivaError.deviceNotSupported
        }
        
        #if targetEnvironment(simulator)
        throw GrantivaError.deviceNotSupported
        #endif
        
        guard DCAppAttestService.shared.isSupported else {
            throw GrantivaError.attestationNotAvailable
        }
    }
    
    static func isDeviceSupported() -> Bool {
        guard #available(iOS 14.0, *) else {
            return false
        }
        
        #if targetEnvironment(simulator)
        return false
        #endif
        
        return DCAppAttestService.shared.isSupported
    }
    
    static func getDeviceInfo() -> [String: String] {
        var deviceInfo = PlatformSupport.getSystemInfo()
        deviceInfo["identifierForVendor"] = PlatformSupport.getDeviceIdentifier()
        return deviceInfo
    }
}
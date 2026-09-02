import Foundation
import DeviceCheck

internal enum DeviceCompatibility {

    static func checkCompatibility() throws {
        #if targetEnvironment(simulator)
        throw GrantivaError.deviceNotSupported
        #else
        guard DCAppAttestService.shared.isSupported else {
            throw GrantivaError.attestationNotAvailable
        }
        #endif
    }

    static func isDeviceSupported() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return DCAppAttestService.shared.isSupported
        #endif
    }
}

import Foundation

internal class CustomClaimsProcessor {
    
    static func processCustomClaims(_ claims: [String: String]?) -> [String: Any] {
        guard let claims = claims else {
            return [:]
        }

        return claims.mapValues { $0 as Any }
    }
    
    static func extractClaimValue<T>(from claims: [String: Any], key: String, as type: T.Type) -> T? {
        return claims[key] as? T
    }
    
    static func validateClaims(_ claims: [String: Any]) -> Bool {
        for (key, value) in claims {
            if !isValidClaimKey(key) || !isValidClaimValue(value) {
                Logger.warning("Invalid claim detected: \(key) = \(value)")
                return false
            }
        }
        return true
    }
    
    private static func isValidClaimKey(_ key: String) -> Bool {
        let invalidKeys = ["iss", "sub", "aud", "exp", "nbf", "iat", "jti"]
        return !invalidKeys.contains(key) && !key.isEmpty && key.count <= 100
    }
    
    private static func isValidClaimValue(_ value: Any) -> Bool {
        switch value {
        case is String:
            let stringValue = value as! String
            return stringValue.count <= 1000
        case is NSNumber:
            return true
        case is Bool:
            return true
        case is [Any]:
            let arrayValue = value as! [Any]
            return arrayValue.count <= 50 && arrayValue.allSatisfy { isValidClaimValue($0) }
        case is [String: Any]:
            let dictValue = value as! [String: Any]
            return dictValue.count <= 20 && dictValue.allSatisfy { isValidClaimKey($0.key) && isValidClaimValue($0.value) }
        default:
            return false
        }
    }
    
    static func getStandardClaims() -> [String] {
        return [
            "device_id",
            "app_version",
            "sdk_version",
            "platform",
            "user_id",
            "session_id",
            "timestamp"
        ]
    }
    
    static func addDeviceContextClaims() -> [String: Any] {
        var claims: [String: Any] = [:]
        
        let systemInfo = PlatformSupport.getSystemInfo()
        claims["platform"] = systemInfo["platform"]
        claims["system_version"] = systemInfo["systemVersion"]
        claims["device_model"] = systemInfo["model"]
        claims["sdk_version"] = "1.0.0"
        claims["timestamp"] = Int(Date().timeIntervalSince1970)
        
        let securityFeatures = DeviceIntelligenceExtractor.getDeviceSecurityFeatures()
        claims["security_features"] = securityFeatures
        
        return claims
    }
}
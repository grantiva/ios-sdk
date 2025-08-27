import Foundation

internal class DeviceIntelligenceExtractor {
    
    static func extractFromResponse(_ response: DeviceIntelligenceResponse) -> DeviceIntelligence {
        let dateFormatter = ISO8601DateFormatter()
        let lastAttestationDate = response.lastAttestationDate != nil ? dateFormatter.date(from: response.lastAttestationDate!) : nil
        
        return DeviceIntelligence(
            deviceId: response.deviceId,
            riskScore: response.riskScore,
            deviceIntegrity: response.deviceIntegrity,
            jailbreakDetected: response.jailbreakDetected,
            attestationCount: response.attestationCount,
            lastAttestationDate: lastAttestationDate
        )
    }
    
    static func analyzeRiskScore(_ score: Int) -> String {
        switch score {
        case 0...20:
            return "Low Risk"
        case 21...50:
            return "Medium Risk"
        case 51...80:
            return "High Risk"
        case 81...100:
            return "Very High Risk"
        default:
            return "Unknown Risk"
        }
    }
    
    static func getDeviceSecurityFeatures() -> [String: Bool] {
        var features: [String: Bool] = [:]
        
        #if os(iOS)
        features["appAttestSupported"] = DeviceCompatibility.isDeviceSupported()
        features["keychainAvailable"] = true
        features["biometricsAvailable"] = false
        #if targetEnvironment(simulator)
        features["runningOnSimulator"] = true
        #else
        features["runningOnSimulator"] = false
        #endif
        #elseif os(macOS)
        features["appAttestSupported"] = DeviceCompatibility.isDeviceSupported()
        features["keychainAvailable"] = true
        features["runningOnSimulator"] = false
        #endif
        
        return features
    }
    
    static func calculateLocalRiskScore() -> Int {
        var riskScore = 0
        
        #if targetEnvironment(simulator)
        riskScore += 30
        #endif
        
        if !DeviceCompatibility.isDeviceSupported() {
            riskScore += 50
        }
        
        let systemInfo = PlatformSupport.getSystemInfo()
        if let systemVersion = systemInfo["systemVersion"] {
            if systemVersion.hasPrefix("14.") || systemVersion.hasPrefix("13.") {
                riskScore += 10
            }
        }
        
        return min(riskScore, 100)
    }
}
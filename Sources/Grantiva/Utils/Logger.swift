import Foundation
import os.log

internal class Logger {
    private static let subsystem = "com.grantiva.sdk"
    private static let category = "GrantivaSDK"
    
    @available(iOS 14.0, macOS 11.0, *)
    private static let osLogger = os.Logger(subsystem: subsystem, category: category)
    
    enum LogLevel {
        case debug
        case info
        case warning
        case error
    }
    
    static func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"

        // The package requires iOS 18 / macOS 15, so os.Logger is always available.
        // Never fall back to print(): print() writes unconditionally to the device
        // console in release builds, which is how secrets leaked previously.
        switch level {
        case .debug:
            osLogger.debug("\(logMessage)")
        case .info:
            osLogger.info("\(logMessage)")
        case .warning:
            osLogger.warning("\(logMessage)")
        case .error:
            osLogger.error("\(logMessage)")
        }
    }
    
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}
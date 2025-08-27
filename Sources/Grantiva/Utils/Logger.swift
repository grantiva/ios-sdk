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
        
        if #available(iOS 14.0, macOS 11.0, *) {
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
        } else {
            let levelString = levelToString(level)
            print("[\(Date())] [\(levelString)] \(logMessage)")
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
    
    private static func levelToString(_ level: LogLevel) -> String {
        switch level {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .warning:
            return "WARNING"
        case .error:
            return "ERROR"
        }
    }
}
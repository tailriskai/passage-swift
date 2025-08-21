import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

/**
 * Logger module for Passage Swift SDK
 * Provides configurable logging with debug flag support and HTTP transport
 */

public enum PassageLogLevel: Int, CaseIterable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3
    case silent = 4
    
    var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        case .silent: return "SILENT"
        }
    }
}

struct LogEntry: Codable {
    let level: String
    let message: String
    let context: String?
    let metadata: [String: String]?
    let timestamp: String
    let sessionId: String?
    let source: String
    let sdkName: String
    let sdkVersion: String?
    let appVersion: String?
    let platform: String
    let deviceInfo: [String: String]?
    
    init(level: String, message: String, context: String? = nil, metadata: [String: String]? = nil, timestamp: String, sessionId: String? = nil, sdkVersion: String? = nil, appVersion: String? = nil, deviceInfo: [String: String]? = nil) {
        self.level = level
        self.message = message
        self.context = context
        self.metadata = metadata
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.source = "sdk"
        self.sdkName = "swift-ios"
        self.sdkVersion = sdkVersion
        self.appVersion = appVersion
        self.platform = "ios"
        self.deviceInfo = deviceInfo
    }
}

struct LogBatch: Codable {
    let logs: [LogEntry]
}

public struct HTTPTransportConfig {
    let endpoint: String
    let batchSize: Int
    let flushInterval: TimeInterval
    let maxRetries: Int
    let retryDelay: TimeInterval
    
    public static let `default` = HTTPTransportConfig(
        endpoint: PassageConstants.Defaults.loggerEndpoint,
        batchSize: 10,
        flushInterval: 5.0,
        maxRetries: 3,
        retryDelay: 1.0
    )
}

public class PassageLogger {
    public static let shared = PassageLogger()
    
    private var isDebugEnabled: Bool = false
    private var logLevel: PassageLogLevel = .info
    private let prefix: String = "[Passage]"
    
    // HTTP Transport properties
    private var httpTransportEnabled: Bool = false
    private var httpConfig: HTTPTransportConfig = .default
    private var logQueue: [LogEntry] = []
    private var flushTimer: Timer?
    private var sessionId: String?
    private var intentToken: String?
    private var isProcessing: Bool = false
    private let queueLock = NSLock()
    
    // Device info cache
    private lazy var deviceInfo: [String: String] = {
        var info: [String: String] = [:]
        #if canImport(UIKit)
        info["model"] = UIDevice.current.model
        info["systemName"] = UIDevice.current.systemName
        info["systemVersion"] = UIDevice.current.systemVersion
        if let name = UIDevice.current.name as String? {
            info["name"] = name
        }
        #endif
        return info
    }()
    
    private lazy var appVersion: String? = {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }()
    
    public var sdkVersion: String?
    
    private init() {
        setupAppStateObservers()
    }
    
    // Configure logger with debug flag (HTTP transport always enabled)
    public func configure(debug: Bool, level: PassageLogLevel? = nil, sdkVersion: String? = nil) {
        self.isDebugEnabled = debug
        self.logLevel = level ?? (debug ? .debug : .info)
        self.sdkVersion = sdkVersion
        self.httpTransportEnabled = true // Always enabled
        
        startHttpTransport()
        
        if debug {
            info("Logger configured with debug enabled, HTTP transport: enabled, SDK version: \(sdkVersion ?? "unknown")")
        }
    }

    // Allow host app to update SDK version dynamically at runtime
    public func setSdkVersion(_ version: String?) {
        self.sdkVersion = version
        debug("SDK version updated to: \(version ?? "nil")")
    }
    
    // Configure HTTP transport
    public func configureHttpTransport(enabled: Bool, config: HTTPTransportConfig? = nil) {
        httpTransportEnabled = enabled
        if let config = config {
            httpConfig = config
        }
        
        if enabled {
            startHttpTransport()
        } else {
            stopHttpTransport()
        }
    }
    
    // Update intent token for session tracking
    public func updateIntentToken(_ token: String?) {
        intentToken = token
        sessionId = extractSessionId(from: token)
        debug("Intent token updated, sessionId: \(sessionId ?? "nil")")
    }
    
    // Extract session ID from JWT intent token
    private func extractSessionId(from token: String?) -> String? {
        guard let token = token else { return nil }
        
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else { return nil }
        
        let payload = components[1]
        guard let data = Data(base64Encoded: addPadding(to: payload)) else { return nil }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sessionId = json["sessionId"] as? String {
                return sessionId
            }
        } catch {
            debug("Failed to decode intent token: \(error)")
        }
        
        return nil
    }
    
    // Add padding to base64 string if needed
    private func addPadding(to base64: String) -> String {
        let remainder = base64.count % 4
        if remainder > 0 {
            return base64 + String(repeating: "=", count: 4 - remainder)
        }
        return base64
    }
    
    // Setup app state observers for flushing logs
    private func setupAppStateObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        #endif
    }
    
    #if canImport(UIKit)
    @objc private func appDidEnterBackground() {
        flushLogs()
    }
    
    @objc private func appWillTerminate() {
        flushLogs()
    }
    #endif
    
    // Start HTTP transport with timer
    private func startHttpTransport() {
        stopHttpTransport() // Stop existing timer if any
        
        flushTimer = Timer.scheduledTimer(withTimeInterval: httpConfig.flushInterval, repeats: true) { [weak self] _ in
            self?.flushLogs()
        }
    }
    
    // Stop HTTP transport
    private func stopHttpTransport() {
        flushTimer?.invalidate()
        flushTimer = nil
        flushLogs() // Final flush
    }
    
    // Check if we should log at the given level
    private func shouldLog(_ level: PassageLogLevel) -> Bool {
        // When debug is disabled, suppress ALL logging
        if !isDebugEnabled {
            return false
        }
        return level.rawValue >= logLevel.rawValue
    }
    
    // Format message with timestamp and level
    private func formatMessage(_ level: PassageLogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) -> String {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let location = "[\(fileName):\(line) \(function)]"
        
        return "\(prefix) [\(level.description)] \(message) \(location)"
    }
    
    // Main logging methods
    public func debug(_ message: String, context: String? = nil, metadata: [String: String]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        logToAll(.debug, message, context: context, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func info(_ message: String, context: String? = nil, metadata: [String: String]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        logToAll(.info, message, context: context, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func warn(_ message: String, context: String? = nil, metadata: [String: String]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        logToAll(.warn, message, context: context, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func error(_ message: String, context: String? = nil, metadata: [String: String]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        logToAll(.error, message, context: context, metadata: metadata, file: file, function: function, line: line)
    }
    
    // Combined logging method that handles both console and HTTP transport
    private func logToAll(_ level: PassageLogLevel, _ message: String, context: String? = nil, metadata: [String: String]? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog(level) else { return }
        
        // Console logging
        let formattedMessage = formatMessage(level, message, file: file, function: function, line: line)
        print(formattedMessage)
        
        // HTTP transport logging
        if httpTransportEnabled {
            let logEntry = LogEntry(
                level: level.description,
                message: message,
                context: context,
                metadata: metadata,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                sessionId: sessionId,
                sdkVersion: sdkVersion,
                appVersion: appVersion,
                deviceInfo: deviceInfo
            )
            
            queueLogEntry(logEntry)
        }
    }
    
    // Queue log entry for HTTP transport
    private func queueLogEntry(_ entry: LogEntry) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        logQueue.append(entry)
        
        // Flush if batch size reached
        if logQueue.count >= httpConfig.batchSize {
            flushLogs()
        }
    }
    
    // Flush logs to HTTP endpoint
    public func flushLogs() {
        guard httpTransportEnabled && !isProcessing else { return }
        
        queueLock.lock()
        let logsToSend = logQueue
        logQueue.removeAll()
        queueLock.unlock()
        
        guard !logsToSend.isEmpty else { return }
        
        isProcessing = true
        
        let batch = LogBatch(logs: logsToSend)
        sendLogs(batch: batch, retryCount: 0) { [weak self] success in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                if !success {
                    // Re-queue failed logs (with limit to prevent infinite growth)
                    self?.queueLock.lock()
                    if let strongSelf = self, strongSelf.logQueue.count < 100 {
                        strongSelf.logQueue.insert(contentsOf: logsToSend, at: 0)
                    }
                    self?.queueLock.unlock()
                }
            }
        }
    }
    
    // Send logs to HTTP endpoint with retry logic
    private func sendLogs(batch: LogBatch, retryCount: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: httpConfig.endpoint) else {
            if isDebugEnabled {
                print("PassageLogger: Invalid endpoint URL: \(httpConfig.endpoint)")
            }
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONEncoder().encode(batch)
            request.httpBody = jsonData
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        completion(true)
                    } else {
                        // Retry logic
                        if retryCount < self?.httpConfig.maxRetries ?? 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + (self?.httpConfig.retryDelay ?? 1.0) * Double(retryCount + 1)) {
                                self?.sendLogs(batch: batch, retryCount: retryCount + 1, completion: completion)
                            }
                        } else {
                            completion(false)
                        }
                    }
                } else if let error = error {
                    if self?.isDebugEnabled == true {
                        print("PassageLogger: Request error: \(error.localizedDescription)")
                    }
                    // Retry logic
                    if retryCount < self?.httpConfig.maxRetries ?? 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + (self?.httpConfig.retryDelay ?? 1.0) * Double(retryCount + 1)) {
                            self?.sendLogs(batch: batch, retryCount: retryCount + 1, completion: completion)
                        }
                    } else {
                        completion(false)
                    }
                }
            }.resume()
            
        } catch {
            if isDebugEnabled {
                print("PassageLogger: JSON encoding error: \(error.localizedDescription)")
            }
            completion(false)
        }
    }
    
    // Convenience methods for common logging patterns
    public func debugMethod(_ methodName: String, params: Any? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let context = "method_call"
        var metadata: [String: String] = ["method": methodName]
        
        if let params = params {
            metadata["params"] = String(describing: params)
            debug("\(methodName) called with params: \(params)", context: context, metadata: metadata, file: file, function: function, line: line)
        } else {
            debug("\(methodName) called", context: context, metadata: metadata, file: file, function: function, line: line)
        }
    }
    
    public func debugResult(_ methodName: String, result: Any, file: String = #file, function: String = #function, line: Int = #line) {
        let context = "method_result"
        let metadata: [String: String] = [
            "method": methodName,
            "result": truncateData(result)
        ]
        debug("\(methodName) result: \(result)", context: context, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func errorMethod(_ methodName: String, error: Error, file: String = #file, function: String = #function, line: Int = #line) {
        let context = "method_error"
        let metadata: [String: String] = [
            "method": methodName,
            "error_type": String(describing: type(of: error)),
            "error_code": String((error as NSError).code)
        ]
        self.error("\(methodName) error: \(error.localizedDescription)", context: context, metadata: metadata, file: file, function: function, line: line)
    }
    
    // WebView specific logging
    public func webView(_ message: String, webViewType: String? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let prefix = webViewType != nil ? "[WebView-\(webViewType!)]" : "[WebView]"
        let context = "webview"
        var metadata: [String: String] = [:]
        if let webViewType = webViewType {
            metadata["webview_type"] = webViewType
        }
        debug("\(prefix) \(message)", context: context, metadata: metadata, file: file, function: function, line: line)
    }
    
    public func navigation(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let context = "navigation"
        debug("[Navigation] \(message)", context: context, metadata: nil, file: file, function: function, line: line)
    }
    
    // Cleanup method
    public func cleanup() {
        stopHttpTransport()
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        cleanup()
    }
    
    // Data truncation utilities for sensitive logging
    public func truncateData(_ data: Any, maxLength: Int = 100) -> String {
        let dataString = String(describing: data)
        if dataString.count <= maxLength {
            return dataString
        }
        
        let truncated = String(dataString.prefix(maxLength))
        return "\(truncated)... (truncated, original length: \(dataString.count))"
    }
    
    public func truncateUrl(_ url: String, maxLength: Int = 100) -> String {
        if url.count <= maxLength {
            return url
        }
        
        return "\(url.prefix(maxLength))..."
    }
    
    public func truncateHtml(_ html: String?, maxLength: Int = 100) -> String {
        guard let html = html else { return "nil" }
        
        if html.count <= maxLength {
            return "\(html.count) chars"
        }
        
        let truncated = String(html.prefix(maxLength))
        return "\(html.count) chars (first \(maxLength): \(truncated)...)"
    }
}

// Date formatter extension for consistent log formatting
extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}

// Global convenience variable
public let passageLogger = PassageLogger.shared

import Foundation
import UIKit

/**
 * Analytics module for Passage Swift SDK
 * Tracks SDK events with proper payload structure and HTTP transport
 * Based on requirements from llms.txt
 */

// MARK: - Analytics Event Types

public enum PassageAnalyticsEvent: String, CaseIterable {
    // SDK Lifecycle Events
    case sdkModalOpened = "SDK_MODAL_OPENED"
    case sdkModalClosed = "SDK_MODAL_CLOSED"
    case sdkConfigureStart = "SDK_CONFIGURE_START"
    case sdkConfigureSuccess = "SDK_CONFIGURE_SUCCESS"
    case sdkConfigureError = "SDK_CONFIGURE_ERROR"
    case sdkConfigurationRequest = "SDK_CONFIGURATION_REQUEST"
    case sdkConfigurationSuccess = "SDK_CONFIGURATION_SUCCESS"
    case sdkConfigurationError = "SDK_CONFIGURATION_ERROR"
    case sdkOpenRequest = "SDK_OPEN_REQUEST"
    case sdkOpenSuccess = "SDK_OPEN_SUCCESS"
    case sdkOpenError = "SDK_OPEN_ERROR"
    case sdkOnSuccess = "SDK_ON_SUCCESS"
    case sdkOnError = "SDK_ON_ERROR"
    
    // Remote Control Events
    case sdkRemoteControlConnectStart = "SDK_REMOTE_CONTROL_CONNECT_START"
    case sdkRemoteControlConnectSuccess = "SDK_REMOTE_CONTROL_CONNECT_SUCCESS"
    case sdkRemoteControlConnectError = "SDK_REMOTE_CONTROL_CONNECT_ERROR"
    case sdkRemoteControlDisconnect = "SDK_REMOTE_CONTROL_DISCONNECT"
    case sdkWebViewSwitch = "SDK_WEBVIEW_SWITCH"
    
    // Navigation Events
    case sdkNavigationStart = "SDK_NAVIGATION_START"
    case sdkNavigationSuccess = "SDK_NAVIGATION_SUCCESS"
    case sdkNavigationError = "SDK_NAVIGATION_ERROR"
    
    // Command Events
    case sdkCommandReceived = "SDK_COMMAND_RECEIVED"
    case sdkCommandSuccess = "SDK_COMMAND_SUCCESS"
    case sdkCommandError = "SDK_COMMAND_ERROR"
}

// MARK: - Analytics Payload Structure

public struct PassageAnalyticsPayload: Codable {
    let event: String
    let source: String = "sdk"
    let sdkName: String
    let sdkVersion: String?
    let sessionId: String?
    let timestamp: String
    let metadata: [String: AnyCodable]?
    let platform: String = "ios"
    let deviceInfo: [String: String]?
}

// MARK: - Analytics Configuration

public struct PassageAnalyticsConfig {
    let endpoint: String
    let batchSize: Int
    let flushInterval: TimeInterval
    let maxRetries: Int
    let retryDelay: TimeInterval
    let enabled: Bool
    
    public static let `default` = PassageAnalyticsConfig(
        endpoint: "https://ui.getpassage.ai/api/analytics",
        batchSize: 10,
        flushInterval: 5.0,
        maxRetries: 3,
        retryDelay: 1.0,
        enabled: true
    )
}

// MARK: - Analytics Manager

public class PassageAnalytics {
    public static let shared = PassageAnalytics()
    
    private var config: PassageAnalyticsConfig = .default
    private var eventQueue: [PassageAnalyticsPayload] = []
    private var flushTimer: Timer?
    private var isProcessing: Bool = false
    private let queueLock = NSLock()
    
    // SDK Information
    private var sdkVersion: String?
    private var sessionId: String?
    private var intentToken: String?
    
    // Device info cache
    private lazy var deviceInfo: [String: String] = {
        var info: [String: String] = [:]
        #if canImport(UIKit)
        info["model"] = UIDevice.current.model
        info["systemName"] = UIDevice.current.systemName
        info["systemVersion"] = UIDevice.current.systemVersion
        info["idiom"] = UIDevice.current.userInterfaceIdiom.description
        if let name = UIDevice.current.name as String? {
            info["name"] = name
        }
        // Add app info
        if let bundle = Bundle.main.infoDictionary {
            info["appVersion"] = bundle["CFBundleShortVersionString"] as? String
            info["appBuild"] = bundle["CFBundleVersion"] as? String
            info["appBundleId"] = bundle["CFBundleIdentifier"] as? String
        }
        #endif
        return info
    }()
    
    private lazy var sdkName: String = {
        return "swift-ios"
    }()
    
    private init() {
        setupAppStateObservers()
    }
    
    // MARK: - Configuration
    
    public func configure(_ config: PassageAnalyticsConfig, sdkVersion: String? = nil) {
        self.config = config
        self.sdkVersion = sdkVersion
        
        if config.enabled {
            startAnalytics()
            passageLogger.debug("[ANALYTICS] Analytics configured - endpoint: \(config.endpoint), enabled: true")
        } else {
            stopAnalytics()
            passageLogger.debug("[ANALYTICS] Analytics disabled")
        }
    }
    
    public func updateSessionInfo(intentToken: String?, sessionId: String?) {
        self.intentToken = intentToken
        self.sessionId = sessionId
        passageLogger.debug("[ANALYTICS] Session info updated - sessionId: \(sessionId ?? "nil")")
    }
    
    // MARK: - Event Tracking
    
    public func track(event: PassageAnalyticsEvent, metadata: [String: Any]? = nil) {
        guard config.enabled else { return }
        
        passageLogger.debug("[ANALYTICS] Tracking event: \(event.rawValue)")
        
        let convertedMetadata = metadata?.mapValues { AnyCodable($0) }
        
        let payload = PassageAnalyticsPayload(
            event: event.rawValue,
            sdkName: sdkName,
            sdkVersion: sdkVersion,
            sessionId: sessionId,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            metadata: convertedMetadata,
            deviceInfo: deviceInfo
        )
        
        queueEvent(payload)
    }
    
    // MARK: - Convenience Methods
    
    public func trackModalOpened(presentationStyle: String, url: String?) {
        track(event: .sdkModalOpened, metadata: [
            "presentationStyle": presentationStyle,
            "url": url ?? ""
        ])
    }
    
    public func trackModalClosed(reason: String = "user_action") {
        track(event: .sdkModalClosed, metadata: [
            "reason": reason
        ])
    }
    
    public func trackConfigureStart() {
        track(event: .sdkConfigureStart)
    }
    
    public func trackConfigureSuccess(config: [String: Any]) {
        track(event: .sdkConfigureSuccess, metadata: config)
    }
    
    public func trackConfigureError(error: String) {
        track(event: .sdkConfigureError, metadata: [
            "error": error
        ])
    }
    
    public func trackConfigurationRequest(url: String) {
        track(event: .sdkConfigurationRequest, metadata: [
            "url": PassageLogger.shared.truncateUrl(url, maxLength: 200)
        ])
    }
    
    public func trackConfigurationSuccess(userAgent: String?, integrationUrl: String?) {
        track(event: .sdkConfigurationSuccess, metadata: [
            "hasUserAgent": userAgent != nil,
            "hasIntegrationUrl": integrationUrl != nil
        ])
    }
    
    public func trackConfigurationError(error: String, url: String) {
        track(event: .sdkConfigurationError, metadata: [
            "error": error,
            "url": PassageLogger.shared.truncateUrl(url, maxLength: 200)
        ])
    }
    
    public func trackRemoteControlDisconnect(reason: String = "manual") {
        track(event: .sdkRemoteControlDisconnect, metadata: [
            "reason": reason
        ])
    }
    
    public func trackOpenRequest(token: String) {
        track(event: .sdkOpenRequest, metadata: [
            "tokenLength": token.count,
            "hasToken": !token.isEmpty
        ])
    }
    
    public func trackOpenSuccess(url: String) {
        track(event: .sdkOpenSuccess, metadata: [
            "finalUrl": PassageLogger.shared.truncateUrl(url, maxLength: 200)
        ])
    }
    
    public func trackOpenError(error: String, context: String? = nil) {
        track(event: .sdkOpenError, metadata: [
            "error": error,
            "context": context ?? ""
        ])
    }
    
    public func trackOnSuccess(historyCount: Int, connectionId: String) {
        track(event: .sdkOnSuccess, metadata: [
            "historyCount": historyCount,
            "connectionId": connectionId,
            "hasData": historyCount > 0
        ])
    }
    
    public func trackOnError(error: String, data: Any? = nil) {
        track(event: .sdkOnError, metadata: [
            "error": error,
            "hasData": data != nil
        ])
    }
    
    public func trackRemoteControlConnectStart(socketUrl: String, namespace: String) {
        track(event: .sdkRemoteControlConnectStart, metadata: [
            "socketUrl": socketUrl,
            "namespace": namespace
        ])
    }
    
    public func trackRemoteControlConnectSuccess(socketId: String? = nil) {
        track(event: .sdkRemoteControlConnectSuccess, metadata: [
            "socketId": socketId ?? "",
            "connected": true
        ])
    }
    
    public func trackRemoteControlConnectError(error: String, attempt: Int = 1) {
        track(event: .sdkRemoteControlConnectError, metadata: [
            "error": error,
            "attempt": attempt,
            "connected": false
        ])
    }
    
    public func trackWebViewSwitch(from: String, to: String, reason: String) {
        track(event: .sdkWebViewSwitch, metadata: [
            "fromWebView": from,
            "toWebView": to,
            "reason": reason
        ])
    }
    
    public func trackNavigationStart(url: String, webViewType: String) {
        track(event: .sdkNavigationStart, metadata: [
            "url": PassageLogger.shared.truncateUrl(url, maxLength: 200),
            "webViewType": webViewType
        ])
    }
    
    public func trackNavigationSuccess(url: String, webViewType: String, duration: TimeInterval? = nil) {
        var metadata: [String: Any] = [
            "url": PassageLogger.shared.truncateUrl(url, maxLength: 200),
            "webViewType": webViewType
        ]
        if let duration = duration {
            metadata["duration"] = duration
        }
        track(event: .sdkNavigationSuccess, metadata: metadata)
    }
    
    public func trackNavigationError(url: String, webViewType: String, error: String) {
        track(event: .sdkNavigationError, metadata: [
            "url": PassageLogger.shared.truncateUrl(url, maxLength: 200),
            "webViewType": webViewType,
            "error": error
        ])
    }
    
    public func trackCommandReceived(commandId: String, commandType: String, userActionRequired: Bool) {
        track(event: .sdkCommandReceived, metadata: [
            "commandId": commandId,
            "commandType": commandType,
            "userActionRequired": userActionRequired
        ])
    }
    
    public func trackCommandSuccess(commandId: String, commandType: String, duration: TimeInterval? = nil) {
        var metadata: [String: Any] = [
            "commandId": commandId,
            "commandType": commandType
        ]
        if let duration = duration {
            metadata["duration"] = duration
        }
        track(event: .sdkCommandSuccess, metadata: metadata)
    }
    
    public func trackCommandError(commandId: String, commandType: String, error: String) {
        track(event: .sdkCommandError, metadata: [
            "commandId": commandId,
            "commandType": commandType,
            "error": error
        ])
    }
    
    // MARK: - Private Methods
    
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
        flushEvents()
    }
    
    @objc private func appWillTerminate() {
        flushEvents()
    }
    #endif
    
    private func startAnalytics() {
        stopAnalytics() // Stop existing timer if any
        
        flushTimer = Timer.scheduledTimer(withTimeInterval: config.flushInterval, repeats: true) { [weak self] _ in
            self?.flushEvents()
        }
    }
    
    private func stopAnalytics() {
        flushTimer?.invalidate()
        flushTimer = nil
        flushEvents() // Final flush
    }
    
    private func queueEvent(_ payload: PassageAnalyticsPayload) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        eventQueue.append(payload)
        
        // Flush if batch size reached
        if eventQueue.count >= config.batchSize {
            flushEvents()
        }
    }
    
    public func flushEvents() {
        guard config.enabled && !isProcessing else { return }
        
        queueLock.lock()
        let eventsToSend = eventQueue
        eventQueue.removeAll()
        queueLock.unlock()
        
        guard !eventsToSend.isEmpty else { return }
        
        isProcessing = true
        
        sendEvents(events: eventsToSend, retryCount: 0) { [weak self] success in
            DispatchQueue.main.async {
                self?.isProcessing = false
                
                if !success {
                    // Re-queue failed events (with limit to prevent infinite growth)
                    self?.queueLock.lock()
                    if let strongSelf = self, strongSelf.eventQueue.count < 100 {
                        strongSelf.eventQueue.insert(contentsOf: eventsToSend, at: 0)
                    }
                    self?.queueLock.unlock()
                }
            }
        }
    }
    
    private func sendEvents(events: [PassageAnalyticsPayload], retryCount: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: config.endpoint) else {
            passageLogger.error("[ANALYTICS] Invalid endpoint URL: \(config.endpoint)")
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add intent token if available
        if let intentToken = intentToken {
            request.setValue(intentToken, forHTTPHeaderField: "x-intent-token")
        }
        
        do {
            let jsonData = try JSONEncoder().encode(["events": events])
            request.httpBody = jsonData
            
            passageLogger.debug("[ANALYTICS] Sending \(events.count) events to analytics endpoint")
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                if let error = error {
                    passageLogger.error("[ANALYTICS] Error sending events: \(error)")
                    
                    // Retry logic
                    if retryCount < self?.config.maxRetries ?? 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + (self?.config.retryDelay ?? 1.0) * Double(retryCount + 1)) {
                            self?.sendEvents(events: events, retryCount: retryCount + 1, completion: completion)
                        }
                    } else {
                        completion(false)
                    }
                } else if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        passageLogger.debug("[ANALYTICS] Events sent successfully - Status: \(httpResponse.statusCode)")
                        completion(true)
                    } else {
                        passageLogger.error("[ANALYTICS] Server error - Status: \(httpResponse.statusCode)")
                        
                        // Retry logic for server errors
                        if retryCount < self?.config.maxRetries ?? 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + (self?.config.retryDelay ?? 1.0) * Double(retryCount + 1)) {
                                self?.sendEvents(events: events, retryCount: retryCount + 1, completion: completion)
                            }
                        } else {
                            completion(false)
                        }
                    }
                } else {
                    completion(false)
                }
            }.resume()
            
        } catch {
            passageLogger.error("[ANALYTICS] JSON encoding error: \(error)")
            completion(false)
        }
    }
    
    // MARK: - Cleanup
    
    public func cleanup() {
        stopAnalytics()
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - UIUserInterfaceIdiom Extension

#if canImport(UIKit)
extension UIUserInterfaceIdiom {
    var description: String {
        switch self {
        case .phone: return "phone"
        case .pad: return "pad"
        case .tv: return "tv"
        case .carPlay: return "carPlay"
        case .mac: return "mac"
        case .vision: return "vision"
        @unknown default: return "unknown"
        }
    }
}
#endif

// Global convenience variable
public let passageAnalytics = PassageAnalytics.shared

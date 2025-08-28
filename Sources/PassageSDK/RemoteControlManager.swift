#if canImport(UIKit)
import Foundation
import WebKit
import SocketIO

// MARK: - Remote Control Types

public struct RemoteCommand {
    let id: String
    let type: CommandType
    let args: [String: Any]?
    let injectScript: String?
    let cookieDomains: [String]?
    let userActionRequired: Bool?
    
    enum CommandType: String {
        case navigate = "navigate"
        case click = "click"
        case input = "input"
        case wait = "wait"
        case injectScript = "injectScript"
        case done = "done"
    }
}

struct CommandResult: Codable {
    let id: String
    let status: String
    let data: AnyCodable?
    let pageData: PageData?
    let error: String?
}

struct PageData: Codable {
    let cookies: [CookieData]?
    let localStorage: [StorageItem]?
    let sessionStorage: [StorageItem]?
    let html: String?
    let url: String?
    let screenshot: String?
}

struct CookieData: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String?
    let expires: Double?
    let secure: Bool?
    let httpOnly: Bool?
    let sameSite: String?
}

struct StorageItem: Codable {
    let name: String
    let value: String
}

// AnyCodable is defined in PassageAnalytics.swift

// MARK: - RemoteControlManager

class RemoteControlManager {
    private let config: PassageConfig
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var isConnected: Bool = false
    private var intentToken: String?
    private var onSuccess: ((PassageSuccessData) -> Void)?
    private var onError: ((PassageErrorData) -> Void)?
    private var onDataComplete: ((PassageDataResult) -> Void)?
    private var onPromptComplete: ((PassagePromptResponse) -> Void)?
    private var cookieDomains: [String] = []
    private var connectionData: [[String: Any]]? = nil
    private var connectionId: String? = nil
    private var globalJavascript: String = ""
    private var automationUserAgent: String = ""
    private var integrationUrl: String?
    private var currentWebViewType: String = PassageConstants.WebViewTypes.ui
    private var lastUserActionCommand: RemoteCommand?
    private var currentCommand: RemoteCommand?
    private var lastWaitCommand: RemoteCommand? // Track wait commands for reinjection
    private var onConfigurationUpdated: ((_ userAgent: String, _ integrationUrl: String?) -> Void)?
    
    // Screenshot and record mode support
    private var screenshotAccessors: ScreenshotAccessors?
    private var captureImageFunction: CaptureImageFunction?
    
    // Screenshot accessor protocols (matching React Native)
    typealias ScreenshotAccessors = (
        getCurrentScreenshot: () -> String?,
        getPreviousScreenshot: () -> String?
    )
    
    typealias CaptureImageFunction = () async -> String?
    
    init(config: PassageConfig) {
        self.config = config
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // Observe navigation completion for sending command results
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigationCompleted(_:)),
            name: .navigationCompleted,
            object: nil
        )
        
        // Observe script execution results
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScriptExecutionResult(_:)),
            name: .scriptExecutionResult,
            object: nil
        )
        
        // Observe browser state updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSendBrowserState(_:)),
            name: .sendBrowserState,
            object: nil
        )
    }
    
    @objc private func handleNavigationCompleted(_ notification: Notification) {
        passageLogger.info("[REMOTE CONTROL] handleNavigationCompleted called")
        
        guard let url = notification.userInfo?["url"] as? String,
              let webViewType = notification.userInfo?["webViewType"] as? String,
              webViewType == PassageConstants.WebViewTypes.automation,
              let command = currentCommand,
              command.type == .navigate else {
            passageLogger.warn("[REMOTE CONTROL] Navigation completed but missing required data or not navigation command")
            passageLogger.debug("[REMOTE CONTROL] URL: \(notification.userInfo?["url"] as? String ?? "nil")")
            passageLogger.debug("[REMOTE CONTROL] WebViewType: \(notification.userInfo?["webViewType"] as? String ?? "nil")")
            passageLogger.debug("[REMOTE CONTROL] Current command: \(currentCommand?.id ?? "nil") type: \(currentCommand?.type.rawValue ?? "nil")")
            return
        }
        
        passageLogger.info("[REMOTE CONTROL] Navigation completed for command: \(command.id)")
        passageLogger.info("[REMOTE CONTROL] Final URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
        
        // Send success result
        passageLogger.info("[REMOTE CONTROL] About to send success result...")
        sendSuccess(commandId: command.id, data: ["url": url])
        
        // Clear the current command
        currentCommand = nil
        passageLogger.info("[REMOTE CONTROL] Navigation command cleared")
    }
    
    // Add method to handle navigation completion from WebView (matches React Native)
    func handleNavigationComplete(_ url: String) {
        passageLogger.debug("[REMOTE CONTROL] Navigation complete called for URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
        
        // Handle navigation command completion
        if let command = currentCommand, command.type == .navigate {
            passageLogger.info("[REMOTE CONTROL] Completing navigation command: \(command.id)")
            sendSuccess(commandId: command.id, data: ["url": url])
            currentCommand = nil
        }
        
        // Check if we need to reinject a wait command after navigation
        if let waitCommand = lastWaitCommand {
            passageLogger.info("[REMOTE CONTROL] Re-injecting wait command after navigation: \(waitCommand.id)")
            
            // Add a delay to ensure page is fully loaded before reinjecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.handleScriptExecution(waitCommand)
            }
        }
    }
    
    @objc private func handleScriptExecutionResult(_ notification: Notification) {
        guard let commandId = notification.userInfo?["commandId"] as? String,
              let success = notification.userInfo?["success"] as? Bool else {
            passageLogger.error("[REMOTE CONTROL] Script execution result missing required data")
            return
        }
        
        passageLogger.info("[REMOTE CONTROL] Script execution result for command: \(commandId), success: \(success)")
        
        // Clear wait command if it completed (successfully or not)
        if let waitCommand = lastWaitCommand, waitCommand.id == commandId {
            passageLogger.debug("[REMOTE CONTROL] Clearing completed wait command: \(commandId)")
            lastWaitCommand = nil
        }
        
        if success {
            let result = notification.userInfo?["result"]
            sendSuccess(commandId: commandId, data: result)
        } else {
            let error = notification.userInfo?["error"] as? String ?? "Script execution failed"
            sendError(commandId: commandId, error: error)
        }
    }
    
    @objc private func handleSendBrowserState(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? String,
              let webViewType = notification.userInfo?["webViewType"] as? String else {
            passageLogger.error("[REMOTE CONTROL] Browser state notification missing required data")
            return
        }
        
        passageLogger.debug("[REMOTE CONTROL] Sending browser state for \(webViewType): \(passageLogger.truncateUrl(url, maxLength: 100))")
        
        // TODO: Implement browser state sending like React Native implementation
        // For now, just log that we received the notification
        // This would typically collect page data and send it to the backend
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func updateConfig(_ config: PassageConfig) {
        // Update config if needed
    }
    
    // MARK: - Record Mode and Screenshot Support
    
    func getRecordFlag() -> Bool {
        guard let intentToken = intentToken else { return false }
        return extractRecordFlag(from: intentToken)
    }
    
    func setScreenshotAccessors(_ accessors: ScreenshotAccessors?) {
        self.screenshotAccessors = accessors
    }
    
    func setCaptureImageFunction(_ captureImageFn: CaptureImageFunction?) {
        self.captureImageFunction = captureImageFn
    }
    
    private func extractRecordFlag(from token: String) -> Bool {
        // Extract record flag from JWT token (matching React Native implementation)
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else { return false }
        
        let payload = components[1]
        guard let data = Data(base64Encoded: addPadding(to: payload)) else { return false }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let record = json["record"] as? Bool {
                return record
            }
        } catch {
            passageLogger.debug("[REMOTE CONTROL] Failed to decode record flag from intent token: \(error)")
        }
        
        return false
    }
    
    // Helper method to add padding to base64 string
    private func addPadding(to base64: String) -> String {
        let remainder = base64.count % 4
        if remainder > 0 {
            return base64 + String(repeating: "=", count: 4 - remainder)
        }
        return base64
    }
    
    func setConfigurationCallback(_ callback: ((_ userAgent: String, _ integrationUrl: String?) -> Void)?) {
        self.onConfigurationUpdated = callback
    }
    
    // MARK: - Global JavaScript Access
    
    /// Get the global JavaScript that should be injected into automation webview on every navigation
    /// Returns empty string if no global JavaScript is configured
    func getGlobalJavascript() -> String {
        return globalJavascript
    }
    
    func connect(
        intentToken: String,
        onSuccess: ((PassageSuccessData) -> Void)? = nil,
        onError: ((PassageErrorData) -> Void)? = nil,
        onDataComplete: ((PassageDataResult) -> Void)? = nil,
        onPromptComplete: ((PassagePromptResponse) -> Void)? = nil
    ) {
        self.intentToken = intentToken
        self.onSuccess = onSuccess
        self.onError = onError
        self.onDataComplete = onDataComplete
        self.onPromptComplete = onPromptComplete
        
        passageLogger.info("[REMOTE CONTROL] ========== STARTING CONNECTION ==========")
        passageLogger.info("[REMOTE CONTROL] Intent token length: \(intentToken.count)")
        passageLogger.debug("[REMOTE CONTROL] Intent token preview: \(passageLogger.truncateData(intentToken, maxLength: 50))")
        passageLogger.info("[REMOTE CONTROL] Socket URL: \(config.socketUrl)")
        passageLogger.info("[REMOTE CONTROL] Socket Namespace: \(config.socketNamespace)")
        passageLogger.info("[REMOTE CONTROL] Record mode: \(getRecordFlag() ? "ENABLED (screenshots will be captured)" : "DISABLED (no screenshots)")")
        passageLogger.info("[REMOTE CONTROL] Page data collection: ENABLED (HTML, localStorage, sessionStorage, cookies)")
        
        // Fetch configuration first
        passageLogger.info("[REMOTE CONTROL] Fetching configuration from server...")
        passageAnalytics.trackConfigurationRequest(url: "\(config.socketUrl)\(PassageConstants.Paths.automationConfig)")
        fetchConfiguration { [weak self] in
            passageLogger.info("[REMOTE CONTROL] Configuration fetch completed, proceeding to socket connection")
            self?.connectSocket()
        }
    }
    
    private func fetchConfiguration(completion: @escaping () -> Void) {
        guard let intentToken = intentToken else {
            passageLogger.error("[REMOTE CONTROL] No intent token available for configuration fetch")
            completion()
            return
        }
        
        let urlString = "\(config.socketUrl)\(PassageConstants.Paths.automationConfig)"
        passageLogger.info("[REMOTE CONTROL] Fetching config from: \(urlString)")
        
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.addValue(intentToken, forHTTPHeaderField: "x-intent-token")
        
        passageLogger.debug("[REMOTE CONTROL] Request headers: \(request.allHTTPHeaderFields ?? [:])")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                passageLogger.error("[REMOTE CONTROL] Configuration fetch error: \(error.localizedDescription)")
                passageLogger.error("[REMOTE CONTROL] Error details: \(error)")
                passageAnalytics.trackConfigurationError(error: error.localizedDescription, url: urlString)
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                passageLogger.info("[REMOTE CONTROL] Configuration response status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    passageLogger.warn("[REMOTE CONTROL] Non-200 status code received")
                    passageAnalytics.trackConfigurationError(error: "Status code: \(httpResponse.statusCode)", url: urlString)
                }
            }
            
            if let data = data {
                passageLogger.info("[REMOTE CONTROL] Configuration data received: \(data.count) bytes")
                if let jsonString = String(data: data, encoding: .utf8) {
                    passageLogger.debug("[REMOTE CONTROL] Raw response: \(passageLogger.truncateData(jsonString, maxLength: 500))")
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self?.cookieDomains = json["cookieDomains"] as? [String] ?? []
                        self?.globalJavascript = json["globalJavascript"] as? String ?? ""
                        // Extract automationUserAgent - undefined/null becomes empty string
                        self?.automationUserAgent = json["automationUserAgent"] as? String ?? ""
                        self?.integrationUrl = (json["integration"] as? [String: Any])?["url"] as? String
                        
                        passageLogger.info("[REMOTE CONTROL] Configuration parsed successfully")
                        passageLogger.debug("[REMOTE CONTROL] Cookie domains: \(self?.cookieDomains ?? [])")
                        passageLogger.debug("[REMOTE CONTROL] Global JS length: \(self?.globalJavascript.count ?? 0)")
                        let userAgentInfo: String
                        if let self = self, !self.automationUserAgent.isEmpty {
                            let agent = self.automationUserAgent
                            userAgentInfo = "provided (\(agent.count) chars)"
                        } else {
                            userAgentInfo = "empty (will use webview default)"
                        }
                        passageLogger.debug("[REMOTE CONTROL] Automation user agent: \(userAgentInfo)")
                        passageLogger.debug("[REMOTE CONTROL] Integration URL: \(self?.integrationUrl ?? "none")")
                        passageLogger.info("[REMOTE CONTROL] Cookie domains configured: \(self?.cookieDomains.count ?? 0) domains")
                        
                        // Notify about configuration update (matches React Native implementation)
                        if let self = self, let callback = self.onConfigurationUpdated {
                            callback(self.automationUserAgent, self.integrationUrl)
                        }
                        if let self = self {
                            passageAnalytics.trackConfigurationSuccess(userAgent: self.automationUserAgent, integrationUrl: self.integrationUrl)
                        }
                    }
                } catch {
                    passageLogger.error("[REMOTE CONTROL] JSON parsing error: \(error)")
                    passageAnalytics.trackConfigurationError(error: "JSON parsing error", url: urlString)
                }
            } else {
                passageLogger.warn("[REMOTE CONTROL] No data received in configuration response")
                passageAnalytics.trackConfigurationError(error: "No data", url: urlString)
            }
            
            completion()
        }.resume()
    }
    
    private func connectSocket() {
        let socketURL = URL(string: config.socketUrl)!
        
        passageLogger.info("[REMOTE CONTROL] ========== SOCKET CONNECTION STARTING ==========")
        passageLogger.info("[REMOTE CONTROL] Socket URL: \(socketURL.absoluteString)")
        passageLogger.info("[REMOTE CONTROL] Namespace: \(config.socketNamespace)")
        passageLogger.info("[REMOTE CONTROL] Intent token available: \(intentToken != nil)")
        passageAnalytics.trackRemoteControlConnectStart(socketUrl: socketURL.absoluteString, namespace: config.socketNamespace)
        
        // Determine if we should use secure connection based on URL scheme
        let isSecure = socketURL.scheme?.lowercased() == "https"
        passageLogger.info("[REMOTE CONTROL] Using secure connection: \(isSecure) (scheme: \(socketURL.scheme ?? "nil"))")
        
        let socketConfig: SocketIOClientConfiguration = [
            .log(config.debug),  // Use unified debug flag from PassageConfig
            .compress,
            .path("/socket.io/"),  // Standard Socket.IO path
            .connectParams(["intentToken": intentToken ?? ""]),
            .forceWebsockets(true),
            .forceNew(true),
            .reconnects(true),
            .reconnectAttempts(5),
            .reconnectWait(2),
            .reconnectWaitMax(10),
            .randomizationFactor(0),
            .secure(isSecure),  // Use secure connection only for HTTPS URLs
            .selfSigned(false)
            // Remove version specification to let it auto-negotiate
        ]
        
        passageLogger.debug("[REMOTE CONTROL] Socket configuration: \(socketConfig)")
        
        manager = SocketManager(
            socketURL: socketURL,
            config: socketConfig
        )
        
        // Use 'ws' namespace as expected by the server
        socket = manager?.socket(forNamespace: "/ws")
        passageLogger.info("[REMOTE CONTROL] Using namespace: /ws with path: /socket.io/")
        
        passageLogger.info("[REMOTE CONTROL] Socket manager created: \(manager != nil)")
        passageLogger.info("[REMOTE CONTROL] Socket instance created: \(socket != nil)")
        
        if socket == nil {
            passageLogger.error("[REMOTE CONTROL] ❌ CRITICAL: Failed to create socket instance")
            let error = PassageErrorData(error: "Failed to create socket instance", data: nil)
            onError?(error)
            return
        }
        
        passageLogger.info("[REMOTE CONTROL] Setting up socket event handlers...")
        setupSocketHandlers()
        
        passageLogger.info("[REMOTE CONTROL] Initiating socket connection...")
        passageLogger.debug("[REMOTE CONTROL] Token for connection: \(passageLogger.truncateData(intentToken ?? "nil", maxLength: 50))")
        
        // Log initial socket state
        if let status = socket?.status {
            passageLogger.info("[REMOTE CONTROL] Initial socket status: \(status)")
        }
        
        socket?.connect()
        
        // Check socket status at multiple intervals
        let checkIntervals: [Double] = [0.5, 1.0, 2.0, 3.0, 5.0]
        for interval in checkIntervals {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let status = self?.socket?.status {
                    passageLogger.info("[REMOTE CONTROL] Socket status after \(interval)s: \(status)")
                    if let manager = self?.manager {
                        passageLogger.debug("[REMOTE CONTROL] Manager status: \(manager.status)")
                    }
                }
            }
        }
    }
    
    private func setupSocketHandlers() {
        passageLogger.info("[SOCKET HANDLERS] Setting up all socket event handlers")
        
        socket?.on(clientEvent: .connect) { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] ✅ CONNECTED to server")
            passageLogger.debug("[SOCKET EVENT] Connect data: \(data)")
            passageLogger.debug("[SOCKET EVENT] Connect ack: \(String(describing: ack))")
            self?.isConnected = true
            
            // Log socket details after connection
            if let socket = self?.socket {
                passageLogger.info("[SOCKET INFO] Socket ID: \(socket.sid ?? "no-sid")")
                passageLogger.info("[SOCKET INFO] Status: \(socket.status)")
                passageLogger.info("[SOCKET INFO] Manager status: \(socket.manager?.status ?? .notConnected)")
                passageAnalytics.trackRemoteControlConnectSuccess(socketId: socket.sid)
            }
        }
        
        socket?.on(clientEvent: .error) { [weak self] data, ack in
            passageLogger.error("[SOCKET EVENT] ❌ ERROR occurred")
            passageLogger.error("[SOCKET EVENT] Error data: \(data)")
            passageAnalytics.trackRemoteControlConnectError(error: String(describing: data), attempt: 1)
            
            // Try to parse error details
            if let errorArray = data.first as? [Any], !errorArray.isEmpty {
                for (index, item) in errorArray.enumerated() {
                    passageLogger.error("[SOCKET EVENT] Error item \(index): \(item)")
                }
            } else if !data.isEmpty {
                for (index, item) in data.enumerated() {
                    passageLogger.error("[SOCKET EVENT] Error item \(index): \(item)")
                }
            }
            
            // Send error callback
            let errorMessage = "Socket error: \(data)"
            let error = PassageErrorData(error: errorMessage, data: data)
            self?.onError?(error)
        }
        
        socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
            passageLogger.warn("[SOCKET EVENT] 🔌 DISCONNECTED from server")
            passageLogger.warn("[SOCKET EVENT] Disconnect reason: \(data)")
            self?.isConnected = false
            passageAnalytics.trackRemoteControlDisconnect(reason: "\(data)")
            
            // Log final socket state
            if let socket = self?.socket {
                passageLogger.debug("[SOCKET INFO] Final status: \(socket.status)")
            }
        }
        
        socket?.on(clientEvent: .reconnect) { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] 🔄 RECONNECTED successfully")
            passageLogger.info("[SOCKET EVENT] Reconnected after \(data) attempts")
            self?.isConnected = true
        }
        
        socket?.on(clientEvent: .reconnectAttempt) { data, ack in
            passageLogger.warn("[SOCKET EVENT] 🔄 RECONNECT ATTEMPT #\(data)")
        }
        
        socket?.on(clientEvent: .statusChange) { data, ack in
            passageLogger.info("[SOCKET EVENT] 📊 STATUS CHANGED")
            passageLogger.info("[SOCKET EVENT] New status: \(data)")
        }
        
        socket?.on(clientEvent: .ping) { data, ack in
            passageLogger.debug("[SOCKET EVENT] 🏓 PING received")
        }
        
        socket?.on(clientEvent: .pong) { data, ack in
            passageLogger.debug("[SOCKET EVENT] 🏓 PONG received")
        }
        
        // Add websocket specific error handlers
        socket?.on(clientEvent: .websocketUpgrade) { data, ack in
            passageLogger.info("[SOCKET EVENT] 🔄 WebSocket upgrade: \(data)")
        }
        
        socket?.onAny { event in
            passageLogger.debug("[SOCKET EVENT] Any event received: \(event.event) with items: \(event.items ?? [])")
        }
        
        // Custom events
        socket?.on("command") { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] 📨 COMMAND received")
            passageLogger.debug("[SOCKET EVENT] Command data: \(data)")
            
            guard let commandData = data.first as? [String: Any] else {
                passageLogger.error("[SOCKET EVENT] Invalid command data format")
                return
            }
            
            passageLogger.info("[SOCKET EVENT] Processing command...")
            self?.handleCommand(commandData)
        }
        
        socket?.on("welcome") { data, ack in
            passageLogger.info("[SOCKET EVENT] 👋 WELCOME message received")
            passageLogger.debug("[SOCKET EVENT] Welcome data: \(data)")
        }
        
        socket?.on("error") { data, ack in
            passageLogger.error("[SOCKET EVENT] Server error event received")
            passageLogger.error("[SOCKET EVENT] Server error data: \(data)")
        }
        
        // Handle DATA_COMPLETE events (like React Native SDK)
        socket?.on("DATA_COMPLETE") { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] 📊 DATA_COMPLETE event received")
            passageLogger.debug("[SOCKET EVENT] Data complete data: \(data)")
            
            if let eventData = data.first as? [String: Any] {
                let dataResult = PassageDataResult(
                    data: eventData["data"],
                    prompts: eventData["prompts"] as? [[String: Any]]
                )
                self?.onDataComplete?(dataResult)
            }
        }
        
        // Handle PROMPT_COMPLETE events (like React Native SDK)
        socket?.on("PROMPT_COMPLETE") { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] 🎯 PROMPT_COMPLETE event received")
            passageLogger.debug("[SOCKET EVENT] Prompt complete data: \(data)")
            
            if let eventData = data.first as? [String: Any],
               let key = eventData["key"] as? String,
               let value = eventData["value"] as? String {
                let promptResponse = PassagePromptResponse(
                    key: key,
                    value: value,
                    response: eventData["response"]
                )
                self?.onPromptComplete?(promptResponse)
            }
        }
        
        // Handle connection events for webview switching
        socket?.on("connection") { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] 🔗 CONNECTION event received")
            passageLogger.debug("[SOCKET EVENT] Connection data: \(data)")
            
            guard let connectionData = data.first as? [String: Any] else {
                passageLogger.error("[SOCKET EVENT] Invalid connection data format")
                return
            }
            
            // Check for userActionRequired flag
            if let userActionRequired = connectionData["userActionRequired"] as? Bool {
                passageLogger.info("[SOCKET EVENT] Connection userActionRequired: \(userActionRequired)")
                self?.handleUserActionRequiredChange(userActionRequired)
            }
            
            // Log other connection info
            if let status = connectionData["status"] as? String {
                passageLogger.info("[SOCKET EVENT] Connection status: \(status)")
            }
            if let statusMessage = connectionData["statusMessage"] as? String {
                passageLogger.info("[SOCKET EVENT] Status message: \(statusMessage)")
            }
            if let progress = connectionData["progress"] as? Int {
                passageLogger.info("[SOCKET EVENT] Progress: \(progress)%")
            }
            
            // Store data when status is "connected" and progress is 100, and data is present
            passageLogger.debug("[SOCKET EVENT] Checking data storage conditions:")
            passageLogger.debug("[SOCKET EVENT]   - Status: \(connectionData["status"] as? String ?? "nil")")
            passageLogger.debug("[SOCKET EVENT]   - Progress: \(connectionData["progress"] as? Int ?? -1)")
            passageLogger.debug("[SOCKET EVENT]   - Data type: \(type(of: connectionData["data"]))")
            passageLogger.debug("[SOCKET EVENT]   - Data count: \((connectionData["data"] as? [[String: Any]])?.count ?? 0)")
            
            if let status = connectionData["status"] as? String,
               let progress = connectionData["progress"] as? Int,
               (status == "connected" || status == "data_available") && progress == 100,
               let actualData = connectionData["data"] as? [[String: Any]],
               !actualData.isEmpty {
                
                passageLogger.info("[SOCKET EVENT] ✅ Data collection complete - storing data for success callback")
                passageLogger.info("[SOCKET EVENT] Found data array with \(actualData.count) items")
                
                // Store the data and connection ID for when the success callback is triggered
                self?.connectionData = actualData
                self?.connectionId = connectionData["id"] as? String
                
                passageLogger.info("[SOCKET EVENT] Data stored successfully:")
                passageLogger.info("[SOCKET EVENT]   - Stored \(actualData.count) data items")
                passageLogger.info("[SOCKET EVENT]   - Connection ID: \(connectionData["id"] as? String ?? "nil")")
                
                // Trigger onDataComplete callback immediately when data is available
                if status == "data_available" {
                    passageLogger.info("[SOCKET EVENT] Triggering onDataComplete callback with available data")
                    let dataResult = PassageDataResult(
                        data: actualData, // Pass all data items
                        prompts: connectionData["promptResults"] as? [[String: Any]]
                    )
                    self?.onDataComplete?(dataResult)
                }
            } else {
                passageLogger.warn("[SOCKET EVENT] ❌ Data storage conditions not met - data will not be available for success callback")
            }
        }
        
        // Log all handlers that were set up
        passageLogger.info("[SOCKET HANDLERS] All event handlers configured successfully")
    }
    
    private func handleUserActionRequiredChange(_ userActionRequired: Bool) {
        passageLogger.info("[WEBVIEW SWITCH] ========== USER ACTION REQUIRED CHANGE ==========")
        passageLogger.info("[WEBVIEW SWITCH] New userActionRequired: \(userActionRequired)")
        passageLogger.info("[WEBVIEW SWITCH] Current webview type: \(currentWebViewType)")
        
        if userActionRequired {
            // User needs to interact - show automation webview
            if currentWebViewType != PassageConstants.WebViewTypes.automation {
                passageLogger.info("[WEBVIEW SWITCH] Switching to AUTOMATION webview (user interaction needed)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .showAutomationWebView, object: nil)
                }
                currentWebViewType = PassageConstants.WebViewTypes.automation
            } else {
                passageLogger.info("[WEBVIEW SWITCH] Already showing automation webview")
            }
        } else {
            // No user interaction needed - show UI webview, automation runs in background
            if currentWebViewType != PassageConstants.WebViewTypes.ui {
                passageLogger.info("[WEBVIEW SWITCH] Switching to UI webview (background automation)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .showUIWebView, object: nil)
                }
                currentWebViewType = PassageConstants.WebViewTypes.ui
            } else {
                passageLogger.info("[WEBVIEW SWITCH] Keeping UI webview visible (automation runs in background)")
            }
        }
    }
    
    private func handleCommand(_ commandData: [String: Any]) {
        passageLogger.info("[COMMAND HANDLER] ========== PROCESSING COMMAND ==========")
        passageLogger.info("[COMMAND HANDLER] Raw command data: \(commandData)")
        
        guard let id = commandData["id"] as? String else {
            passageLogger.error("[COMMAND HANDLER] ❌ Missing command ID")
            return
        }
        
        guard let typeStr = commandData["type"] as? String else {
            passageLogger.error("[COMMAND HANDLER] ❌ Missing command type")
            return
        }
        
        guard let type = RemoteCommand.CommandType(rawValue: typeStr) else {
            passageLogger.error("[COMMAND HANDLER] ❌ Unknown command type: \(typeStr)")
            return
        }
        
        passageLogger.info("[COMMAND HANDLER] Command ID: \(id)")
        passageLogger.info("[COMMAND HANDLER] Command type: \(type.rawValue)")
        
        let command = RemoteCommand(
            id: id,
            type: type,
            args: commandData["args"] as? [String: Any],
            injectScript: commandData["injectScript"] as? String,
            cookieDomains: commandData["cookieDomains"] as? [String],
            userActionRequired: commandData["userActionRequired"] as? Bool
        )
        
        passageLogger.debug("[COMMAND HANDLER] Command details:")
        passageLogger.debug("[COMMAND HANDLER]   - Args: \(command.args ?? [:])")
        passageLogger.debug("[COMMAND HANDLER]   - InjectScript: \(command.injectScript != nil ? "Yes (\(command.injectScript!.count) chars)" : "No")")
        passageLogger.debug("[COMMAND HANDLER]   - Cookie domains: \(command.cookieDomains ?? [])")
        passageLogger.debug("[COMMAND HANDLER]   - User action required: \(command.userActionRequired ?? false)")
        
        // Note: Webview switching is now handled by the connection event, not individual commands
        
        // Store user action commands for potential re-execution
        if command.userActionRequired == true {
            lastUserActionCommand = command
        }
        
        // Store wait commands for potential reinjection after navigation
        if command.type == .wait {
            lastWaitCommand = command
            passageLogger.debug("[REMOTE CONTROL] Stored wait command for potential reinjection: \(command.id)")
        }
        
        // Store current command (matches React Native implementation)
        currentCommand = command
        
        // Execute command
        switch command.type {
        case .navigate:
            handleNavigate(command)
        case .click, .input, .wait, .injectScript:
            handleScriptExecution(command)
        case .done:
            handleDone(command)
        }
    }
    
    private func handleNavigate(_ command: RemoteCommand) {
        guard let url = command.args?["url"] as? String else {
            sendError(commandId: command.id, error: "No URL provided")
            return
        }
        
        passageLogger.info("[COMMAND HANDLER] Navigating to URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
        passageAnalytics.trackCommandReceived(commandId: command.id, commandType: command.type.rawValue, userActionRequired: command.userActionRequired ?? false)
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .navigateInAutomation,
                object: nil,
                userInfo: ["url": url, "commandId": command.id]
            )
        }
    }
    
    private func handleScriptExecution(_ command: RemoteCommand) {
        guard let script = command.injectScript else {
            sendError(commandId: command.id, error: "No script provided for execution")
            return
        }
        
        passageLogger.info("[COMMAND HANDLER] Executing \(command.type.rawValue) script for command: \(command.id)")
        passageLogger.debug("[COMMAND HANDLER] Script length: \(script.count) characters")
        passageAnalytics.trackCommandReceived(commandId: command.id, commandType: command.type.rawValue, userActionRequired: command.userActionRequired ?? false)
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .injectScript,
                object: nil,
                userInfo: ["script": script, "commandId": command.id, "commandType": command.type.rawValue]
            )
        }
    }
    
    private func handleDone(_ command: RemoteCommand) {
        let success = command.args?["success"] as? Bool ?? true
        let data = command.args?["data"]
        
        passageLogger.info("[COMMAND HANDLER] Handling done command - success: \(success)")
        
        // Always switch to UI webview for final result display
        if currentWebViewType != PassageConstants.WebViewTypes.ui {
            passageLogger.info("[COMMAND HANDLER] Switching to UI webview for final result")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showUIWebView, object: nil)
            }
            currentWebViewType = PassageConstants.WebViewTypes.ui
        }
        
        if success {
            // Use async page data collection for done command like React Native
            getPageData { [weak self] pageData in
                let result = CommandResult(
                    id: command.id,
                    status: "success",
                    data: data != nil ? AnyCodable(data!) : nil,
                    pageData: pageData,
                    error: nil
                )
                self?.sendResult(result)
            }
            
            // Parse data into PassageSuccessData format
            let history = parseHistory(from: data)
            let connectionId = (data as? [String: Any])?["connectionId"] as? String ?? ""
            
            let successData = PassageSuccessData(
                history: history,
                connectionId: connectionId
            )
            onSuccess?(successData)
            
            // Navigate to success URL in UI webview
            let successUrl = buildConnectUrl(success: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .navigate,
                    object: nil,
                    userInfo: ["url": successUrl]
                )
            }
        } else {
            let errorMessage = (data as? [String: Any])?["error"] as? String ?? "Done command indicates failure"
            sendError(commandId: command.id, error: errorMessage)
            
            let errorData = PassageErrorData(error: errorMessage, data: data)
            onError?(errorData)
            
            // Navigate to error URL in UI webview
            let errorUrl = buildConnectUrl(success: false, error: errorMessage)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .navigate,
                    object: nil,
                    userInfo: ["url": errorUrl]
                )
            }
        }
    }
    
    private func parseHistory(from data: Any?) -> [PassageHistoryItem] {
        guard let historyData = data as? [String: Any],
              let historyArray = historyData["history"] as? [[String: Any]] else {
            return []
        }
        
        return historyArray.map { item in
            let structuredData = item["structuredData"]
            var additionalData = item
            additionalData.removeValue(forKey: "structuredData")
            
            return PassageHistoryItem(
                structuredData: structuredData,
                additionalData: additionalData
            )
        }
    }
    
    private func buildConnectUrl(success: Bool, error: String? = nil) -> String {
        var components = URLComponents(string: "\(config.baseUrl)\(PassageConstants.Paths.connect)")!
        var queryItems = [
            URLQueryItem(name: "intentToken", value: intentToken ?? ""),
            URLQueryItem(name: "success", value: success.description),
            URLQueryItem(name: "appAgentName", value: config.agentName)
        ]
        
        if let error = error {
            queryItems.append(URLQueryItem(name: "error", value: error))
        }
        
        components.queryItems = queryItems
        return components.url!.absoluteString
    }
    
    private func sendSuccess(commandId: String, data: Any?) {
        passageLogger.info("[REMOTE CONTROL] sendSuccess called for command: \(commandId)")
        
        // Collect page data like React Native SDK
        getPageData { [weak self] pageData in
            let result = CommandResult(
                id: commandId,
                status: "success",
                data: data != nil ? AnyCodable(data!) : nil,
                pageData: pageData,
                error: nil
            )
            
            self?.sendResult(result)
            passageAnalytics.trackCommandSuccess(commandId: commandId, commandType: self?.currentCommand?.type.rawValue ?? "", duration: nil)
        }
    }
    
    private func sendError(commandId: String, error: String) {
        // Error results don't typically include page data in React Native either
        let result = CommandResult(
            id: commandId,
            status: "error",
            data: nil,
            pageData: nil,
            error: error
        )
        sendResult(result)
        passageAnalytics.trackCommandError(commandId: commandId, commandType: currentCommand?.type.rawValue ?? "", error: error)
    }
    
    func sendCommandResult(commandId: String, data: Any?, pageData: [String: Any]?) {
        // Convert pageData to proper structure
        var structuredPageData: PageData?
        if let pageData = pageData {
            structuredPageData = PageData(
                cookies: parseCookies(pageData["cookies"] as? [[String: Any]]),
                localStorage: parseStorage(pageData["localStorage"] as? [[String: Any]]),
                sessionStorage: parseStorage(pageData["sessionStorage"] as? [[String: Any]]),
                html: pageData["html"] as? String,
                url: pageData["url"] as? String,
                screenshot: nil
            )
        }
        
        let result = CommandResult(
            id: commandId,
            status: "success",
            data: data != nil ? AnyCodable(data!) : nil,
            pageData: structuredPageData,
            error: nil
        )
        sendResult(result)
    }
    
    private func parseCookies(_ cookiesData: [[String: Any]]?) -> [CookieData]? {
        guard let cookiesData = cookiesData else { return nil }
        
        return cookiesData.map { cookie in
            CookieData(
                name: cookie["name"] as? String ?? "",
                value: cookie["value"] as? String ?? "",
                domain: cookie["domain"] as? String ?? "",
                path: cookie["path"] as? String,
                expires: cookie["expires"] as? Double,
                secure: cookie["secure"] as? Bool,
                httpOnly: cookie["httpOnly"] as? Bool,
                sameSite: cookie["sameSite"] as? String
            )
        }
    }
    
    private func parseStorage(_ storageData: [[String: Any]]?) -> [StorageItem]? {
        guard let storageData = storageData else { return nil }
        
        return storageData.map { item in
            StorageItem(
                name: item["name"] as? String ?? "",
                value: item["value"] as? String ?? ""
            )
        }
    }
    
    private func getPageData(completion: @escaping (PageData?) -> Void) {
        passageLogger.debug("[REMOTE CONTROL] Collecting page data from automation webview...")
        
        // JavaScript to collect page data (matching React Native implementation)
        let pageDataScript = """
        (function() {
            try {
                const localStorageItems = [];
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    localStorageItems.push({ name: key, value: localStorage.getItem(key) });
                }
                
                const sessionStorageItems = [];
                for (let i = 0; i < sessionStorage.length; i++) {
                    const key = sessionStorage.key(i);
                    sessionStorageItems.push({ name: key, value: sessionStorage.getItem(key) });
                }
                
                const result = {
                    url: window.location.href,
                    html: document.documentElement.outerHTML,
                    localStorage: localStorageItems,
                    sessionStorage: sessionStorageItems
                };
                
                // Send via webkit message handler
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capacitorWebViewModal) {
                    window.webkit.messageHandlers.capacitorWebViewModal.postMessage({
                        type: 'pageData',
                        data: result,
                        webViewType: 'automation',
                        timestamp: Date.now()
                    });
                } else {
                    console.error('[PageData] Message handlers not available');
                }
            } catch (error) {
                console.error('[PageData] Error collecting page data:', error);
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capacitorWebViewModal) {
                    window.webkit.messageHandlers.capacitorWebViewModal.postMessage({
                        type: 'pageData',
                        error: error.toString(),
                        webViewType: 'automation',
                        timestamp: Date.now()
                    });
                }
            }
        })();
        """
        
        // Set up completion timeout (5 seconds like React Native)
        var hasCompleted = false
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            if !hasCompleted {
                hasCompleted = true
                passageLogger.warn("[REMOTE CONTROL] Page data collection timeout - returning minimal data")
                // Return minimal page data on timeout
                completion(PageData(
                    cookies: [],
                    localStorage: [],
                    sessionStorage: [],
                    html: nil,
                    url: nil,
                    screenshot: nil
                ))
            }
        }
        
        // Store completion handler for message processing
        pageDataCompletionHandler = { [weak self] pageData in
            if !hasCompleted {
                hasCompleted = true
                timeoutTimer.invalidate()
                
                // Collect cookies from WKWebsiteDataStore
                self?.collectCookies { cookies in
                    // Convert localStorage and sessionStorage to proper format
                    let localStorage = self?.convertStorageItems(pageData["localStorage"] as? [[String: Any]]) ?? []
                    let sessionStorage = self?.convertStorageItems(pageData["sessionStorage"] as? [[String: Any]]) ?? []
                    
                    // Collect screenshot only if record flag is true (matching React Native)
                    self?.collectScreenshot { screenshot in
                        let fullPageData = PageData(
                            cookies: cookies,
                            localStorage: localStorage,
                            sessionStorage: sessionStorage,
                            html: pageData["html"] as? String,
                            url: pageData["url"] as? String,
                            screenshot: screenshot
                        )
                        
                        let screenshotInfo = screenshot != nil ? "\(screenshot!.count) chars" : "nil"
                        passageLogger.debug("[REMOTE CONTROL] Page data collected: html=\(passageLogger.truncateHtml(fullPageData.html)), localStorage=\(localStorage.count) items, sessionStorage=\(sessionStorage.count) items, cookies=\(cookies.count) items, screenshot=\(screenshotInfo), url=\(fullPageData.url ?? "nil")")
                        
                        completion(fullPageData)
                    }
                }
            }
        }
        
        // Inject script into automation webview
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .collectPageData,
                object: nil,
                userInfo: ["script": pageDataScript]
            )
        }
    }
    
    private func collectCookies(completion: @escaping ([CookieData]) -> Void) {
        guard !cookieDomains.isEmpty else {
            passageLogger.debug("[REMOTE CONTROL] No cookie domains configured, returning empty array")
            completion([])
            return
        }
        
        passageLogger.debug("[REMOTE CONTROL] Collecting cookies for domains: \(cookieDomains)")
        
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        var allCookies: [CookieData] = []
        let group = DispatchGroup()
        
        for domain in cookieDomains {
            group.enter()
            
            // Get all cookies and filter by domain
            cookieStore.getAllCookies { cookies in
                defer { group.leave() }
                
                let domainCookies = cookies.filter { cookie in
                    self.cookieMatchesDomain(cookie: cookie, domain: domain)
                }
                
                let convertedCookies = domainCookies.map { cookie in
                    CookieData(
                        name: cookie.name,
                        value: cookie.value,
                        domain: cookie.domain,
                        path: cookie.path,
                        expires: cookie.expiresDate?.timeIntervalSince1970,
                        secure: cookie.isSecure,
                        httpOnly: cookie.isHTTPOnly,
                        sameSite: self.convertSameSitePolicy(cookie.sameSitePolicy)
                    )
                }
                
                allCookies.append(contentsOf: convertedCookies)
                passageLogger.debug("[REMOTE CONTROL] Found \(domainCookies.count) cookies for domain: \(domain)")
            }
        }
        
        group.notify(queue: .main) {
            passageLogger.debug("[REMOTE CONTROL] Cookie collection complete: \(allCookies.count) total cookies")
            completion(allCookies)
        }
    }
    
    private func cookieMatchesDomain(cookie: HTTPCookie, domain: String) -> Bool {
        // Check if cookie domain matches the configured domain
        let cookieDomain = cookie.domain.hasPrefix(".") ? cookie.domain : "."+cookie.domain
        let targetDomain = domain.hasPrefix(".") ? domain : "."+domain
        
        return cookieDomain == targetDomain || cookieDomain.hasSuffix(targetDomain)
    }
    
    private func convertSameSitePolicy(_ policy: HTTPCookieStringPolicy?) -> String? {
        guard let policy = policy else { return nil }
        
        switch policy {
        case .sameSiteStrict:
            return "Strict"
        case .sameSiteLax:
            return "Lax"
        default:
            return "None"
        }
    }
    
    // Store completion handler for page data collection
    private var pageDataCompletionHandler: (([String: Any]) -> Void)?
    
    func handlePageDataResult(_ data: [String: Any]) {
        passageLogger.debug("[REMOTE CONTROL] Received page data result from webview")
        pageDataCompletionHandler?(data)
    }
    
    private func convertStorageItems(_ items: [[String: Any]]?) -> [StorageItem] {
        guard let items = items else { return [] }
        
        return items.compactMap { item in
            guard let name = item["name"] as? String,
                  let value = item["value"] as? String else {
                return nil
            }
            return StorageItem(name: name, value: value)
        }
    }
    
    private func collectScreenshot(completion: @escaping (String?) -> Void) {
        // Only include screenshot if record flag is true (matching React Native implementation)
        let includeScreenshot = getRecordFlag()
        
        guard includeScreenshot else {
            passageLogger.debug("[REMOTE CONTROL] Screenshot collection skipped - record flag is false")
            completion(nil)
            return
        }
        
        passageLogger.debug("[REMOTE CONTROL] Collecting screenshot for record mode")
        
        // Try to get current screenshot from accessors first
        if let currentScreenshot = screenshotAccessors?.getCurrentScreenshot() {
            passageLogger.debug("[REMOTE CONTROL] Using current screenshot from accessors")
            completion(currentScreenshot)
            return
        }
        
        // If no current screenshot available, try to capture a new one
        if let captureImageFunction = captureImageFunction {
            Task {
                let screenshot = await captureImageFunction()
                passageLogger.debug("[REMOTE CONTROL] New screenshot captured: \(screenshot != nil ? "\(screenshot!.count) chars" : "nil")")
                completion(screenshot)
            }
        } else {
            passageLogger.debug("[REMOTE CONTROL] No screenshot capture function available")
            completion(nil)
        }
    }
    
    private func sendResult(_ result: CommandResult) {
        guard let intentToken = intentToken else {
            passageLogger.error("[REMOTE CONTROL] No intent token available for sending result")
            return
        }
        
        let urlString = "\(config.socketUrl)\(PassageConstants.Paths.automationCommandResult)"
        passageLogger.info("[REMOTE CONTROL] Sending result to: \(urlString)")
        passageLogger.info("[REMOTE CONTROL] Command ID: \(result.id), Status: \(result.status)")
        
        // Log page data status (matching React Native's truncated logging approach)
        if let pageData = result.pageData {
            let recordModeInfo = getRecordFlag() ? " (record mode)" : " (non-record mode)"
            passageLogger.info("[REMOTE CONTROL] ✅ Sending result WITH page data\(recordModeInfo): {")
            passageLogger.info("[REMOTE CONTROL]   cookies: \(pageData.cookies?.count ?? 0) items")
            passageLogger.info("[REMOTE CONTROL]   localStorage: \(pageData.localStorage?.count ?? 0) items")
            passageLogger.info("[REMOTE CONTROL]   sessionStorage: \(pageData.sessionStorage?.count ?? 0) items")
            passageLogger.info("[REMOTE CONTROL]   html: \(passageLogger.truncateHtml(pageData.html))")
            passageLogger.info("[REMOTE CONTROL]   screenshot: \(pageData.screenshot != nil ? "\(pageData.screenshot!.count) chars (redacted)" : "nil")")
            passageLogger.info("[REMOTE CONTROL]   url: \(pageData.url ?? "nil")")
            passageLogger.info("[REMOTE CONTROL] } (matches React Native SDK functionality)")
        } else {
            passageLogger.warn("[REMOTE CONTROL] ⚠️ Sending result WITHOUT page data (pageData: nil)")
            passageLogger.warn("[REMOTE CONTROL] React Native SDK would include: HTML, localStorage, sessionStorage, cookies, URL, screenshot")
        }
        
        guard let url = URL(string: urlString) else {
            passageLogger.error("[REMOTE CONTROL] Invalid URL: \(urlString)")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(intentToken, forHTTPHeaderField: "x-intent-token")
        
        do {
            let jsonData = try JSONEncoder().encode(result)
            request.httpBody = jsonData
            
            passageLogger.info("[REMOTE CONTROL] Sending HTTP POST request...")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    passageLogger.error("[REMOTE CONTROL] Error sending result: \(error)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    passageLogger.info("[REMOTE CONTROL] Result sent successfully - Status: \(httpResponse.statusCode)")
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        passageLogger.debug("[REMOTE CONTROL] Response: \(responseString)")
                    }
                } else {
                    passageLogger.debug("[REMOTE CONTROL] Result sent successfully")
                }
            }.resume()
        } catch {
            passageLogger.error("[REMOTE CONTROL] Error encoding result: \(error)")
        }
    }
    
    func handleWebViewMessage(_ message: [String: Any]) {
        // Handle messages from webview (matches React Native implementation)
        passageLogger.debug("[REMOTE CONTROL] Handling WebView message: \(message["type"] as? String ?? "unknown")")
        
        if let messageType = message["type"] as? String {
            switch messageType {
            case "commandResult":
                // Handle command results from automation webview
                if let commandId = message["commandId"] as? String,
                   let status = message["status"] as? String {
                    
                    passageLogger.info("[REMOTE CONTROL] Command result: \(commandId), status: \(status)")
                    
                    if status == "success" {
                        let result = message["data"]
                        sendSuccess(commandId: commandId, data: result)
                    } else {
                        let error = message["error"] as? String ?? "Command failed"
                        sendError(commandId: commandId, error: error)
                    }
                }
                
            case "currentUrl":
                // Handle current URL responses
                passageLogger.debug("[REMOTE CONTROL] Current URL: \(message["url"] as? String ?? "unknown")")
                
            case "pageData":
                // Handle page data responses
                passageLogger.debug("[REMOTE CONTROL] Received page data")
                // TODO: Handle page data promise resolution
                
            case "SWITCH_WEBVIEW":
                // Handle manual webview switching from window.passage methods
                if let targetWebView = message["targetWebView"] as? String {
                    passageLogger.debug("[REMOTE CONTROL] Manual webview switch requested to \(targetWebView)")
                    
                    if targetWebView == "ui" {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .showUIWebView, object: nil)
                        }
                    } else if targetWebView == "automation" {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .showAutomationWebView, object: nil)
                        }
                    }
                }
                
            case "passage_message":
                // Handle window.passage.postMessage calls
                if let passageData = message["data"] {
                    passageLogger.debug("[REMOTE CONTROL] Received passage message")
                    
                    var parsedData: [String: Any]?
                    if let dataString = passageData as? String,
                       let jsonData = dataString.data(using: .utf8) {
                        parsedData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                    } else if let dataDict = passageData as? [String: Any] {
                        parsedData = dataDict
                    }
                    
                    if let parsedData = parsedData,
                       let commandId = parsedData["commandId"] as? String,
                       let commandType = parsedData["type"] as? String {
                        
                        passageLogger.info("[REMOTE CONTROL] Processing \(commandType) result for command: \(commandId)")
                        
                        // Handle different command types
                        switch commandType {
                        case "injectScript", "wait":
                            let success = parsedData["error"] == nil
                            if success {
                                sendSuccess(commandId: commandId, data: parsedData["value"])
                            } else {
                                let error = parsedData["error"] as? String ?? "Script execution failed"
                                sendError(commandId: commandId, error: error)
                            }
                            
                        default:
                            passageLogger.debug("[REMOTE CONTROL] Unhandled passage message type: \(commandType)")
                        }
                    }
                }
                
            default:
                passageLogger.debug("[REMOTE CONTROL] Unhandled message type: \(messageType)")
            }
        }
    }
    
    func getStoredConnectionData() -> (data: [[String: Any]]?, connectionId: String?) {
        passageLogger.debug("[REMOTE CONTROL] getStoredConnectionData called")
        passageLogger.debug("[REMOTE CONTROL]   - Returning data count: \(connectionData?.count ?? 0)")
        passageLogger.debug("[REMOTE CONTROL]   - Returning connection ID: \(connectionId ?? "nil")")
        return (connectionData, connectionId)
    }
    
    // MARK: - Recording Methods (matching React Native SDK)
    
    /// Complete recording session with optional data
    /// Matches React Native SDK completeRecording method
    func completeRecording(data: [String: Any]) async {
        passageLogger.debug("[REMOTE CONTROL] completeRecording called with data: \(data)")
        
        guard let currentCommand = currentCommand else {
            passageLogger.error("[REMOTE CONTROL] No current command available to complete")
            return
        }
        
        passageLogger.debug("[REMOTE CONTROL] Completing recording for command: \(currentCommand.id)")
        
        // Collect page data with screenshot if record flag is enabled
        await withCheckedContinuation { continuation in
            getPageData { pageData in
                // Send done result with success status
                let result = CommandResult(
                    id: currentCommand.id,
                    status: "success",
                    data: AnyCodable(data),
                    pageData: pageData,
                    error: nil
                )
                
                Task {
                    self.sendResult(result)
                    
                    // Call success callback if available
                    if let onSuccess = self.onSuccess,
                       let connectionData = self.connectionData,
                       let connectionId = self.connectionId {
                        let successData = PassageSuccessData(
                            history: connectionData.compactMap { item in
                                PassageHistoryItem(structuredData: item, additionalData: [:])
                            },
                            connectionId: connectionId
                        )
                        onSuccess(successData)
                    }
                    
                    passageLogger.info("[REMOTE CONTROL] Recording completed successfully")
                    continuation.resume()
                }
            }
        }
    }
    
    /// Capture recording data without completing the session
    /// Matches React Native SDK captureRecordingData method
    func captureRecordingData(data: [String: Any]) async {
        passageLogger.debug("[REMOTE CONTROL] captureRecordingData called with data: \(data)")
        
        guard let currentCommand = currentCommand else {
            passageLogger.error("[REMOTE CONTROL] No current command available to capture")
            return
        }
        
        passageLogger.debug("[REMOTE CONTROL] Capturing recording data for command: \(currentCommand.id)")
        
        // Collect page data with screenshot if record flag is enabled
        await withCheckedContinuation { continuation in
            getPageData { pageData in
                // Send success result (not done, so session continues)
                let result = CommandResult(
                    id: currentCommand.id,
                    status: "success",
                    data: AnyCodable(data),
                    pageData: pageData,
                    error: nil
                )
                
                Task {
                    self.sendResult(result)
                    passageLogger.info("[REMOTE CONTROL] Recording data captured successfully")
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Modal Exit Event (matching React Native SDK)
    
    /// Emit modalExit event to server before disconnecting
    /// Matches React Native SDK emitModalExit method
    func emitModalExit() async {
        await withCheckedContinuation { continuation in
            if let socket = socket, socket.status == .connected {
                passageLogger.debug("[REMOTE CONTROL] Emitting modalExit event")
                
                let modalExitData: [String: Any] = [
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "intentToken": intentToken ?? ""
                ]
                
                // Use an atomic flag to ensure continuation is only resumed once
                let resumeState = NSMutableDictionary()
                resumeState["hasResumed"] = false
                let resumeLock = NSLock()
                
                // Set up one-time listener for acknowledgment
                let onAck: () -> Void = {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }
                    
                    if !(resumeState["hasResumed"] as? Bool ?? true) {
                        resumeState["hasResumed"] = true
                        passageLogger.debug("[REMOTE CONTROL] Received modalExit acknowledgment")
                        continuation.resume()
                    }
                }
                
                // Emit with callback for acknowledgment
                socket.emit("modalExit", modalExitData, completion: onAck)
                
                // Fallback timeout in case server doesn't respond
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }
                    
                    if !(resumeState["hasResumed"] as? Bool ?? true) {
                        resumeState["hasResumed"] = true
                        passageLogger.debug("[REMOTE CONTROL] modalExit timeout, proceeding anyway")
                        continuation.resume()
                    }
                }
            } else {
                // If not connected, resolve immediately
                passageLogger.debug("[REMOTE CONTROL] Socket not connected, skipping modalExit")
                continuation.resume()
            }
        }
    }
    
    func disconnect() {
        passageLogger.info("[REMOTE CONTROL] ========== DISCONNECTING ==========")
        passageLogger.info("[REMOTE CONTROL] Current connection state: \(isConnected)")
        
        if let socket = socket {
            passageLogger.info("[REMOTE CONTROL] Socket status before disconnect: \(socket.status)")
            socket.disconnect()
            passageLogger.info("[REMOTE CONTROL] Socket disconnect called")
        } else {
            passageLogger.warn("[REMOTE CONTROL] Socket was already nil")
        }
        
        if let manager = manager {
            passageLogger.info("[REMOTE CONTROL] Manager status before cleanup: \(manager.status)")
        }
        
        socket = nil
        manager = nil
        
        isConnected = false
        intentToken = nil
        lastUserActionCommand = nil
        currentWebViewType = PassageConstants.WebViewTypes.ui
        connectionData = nil
        connectionId = nil
        
        onSuccess = nil
        onError = nil
        onDataComplete = nil
        onPromptComplete = nil
        
        passageLogger.info("[REMOTE CONTROL] Cleanup completed")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigate = Notification.Name("PassageNavigate")
    static let navigateInAutomation = Notification.Name("PassageNavigateInAutomation")
    static let navigationCompleted = Notification.Name("PassageNavigationCompleted")
    static let injectScript = Notification.Name("PassageInjectScript")
    static let scriptExecutionResult = Notification.Name("PassageScriptExecutionResult")
    static let getPageData = Notification.Name("PassageGetPageData")
    static let collectPageData = Notification.Name("PassageCollectPageData")
    static let sendBrowserState = Notification.Name("PassageSendBrowserState")
    static let showUIWebView = Notification.Name("PassageShowUIWebView")
    static let showAutomationWebView = Notification.Name("PassageShowAutomationWebView")
}
#endif

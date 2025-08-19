import Foundation
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

// Helper for encoding/decoding Any types
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - RemoteControlManager

class RemoteControlManager {
    private let config: PassageConfig
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var isConnected: Bool = false
    private var intentToken: String?
    private var onSuccess: ((PassageSuccessData) -> Void)?
    private var onError: ((PassageErrorData) -> Void)?
    private var cookieDomains: [String] = []
    private var globalJavascript: String = ""
    private var currentWebViewType: String = PassageConstants.WebViewTypes.ui
    private var lastUserActionCommand: RemoteCommand?
    
    init(config: PassageConfig) {
        self.config = config
    }
    
    func updateConfig(_ config: PassageConfig) {
        // Update config if needed
    }
    
    func connect(
        intentToken: String,
        onSuccess: ((PassageSuccessData) -> Void)? = nil,
        onError: ((PassageErrorData) -> Void)? = nil
    ) {
        self.intentToken = intentToken
        self.onSuccess = onSuccess
        self.onError = onError
        
        passageLogger.debug("[REMOTE CONTROL] Connecting with token: \(passageLogger.truncateData(intentToken, maxLength: 20))")
        
        // Fetch configuration first
        fetchConfiguration { [weak self] in
            self?.connectSocket()
        }
    }
    
    private func fetchConfiguration(completion: @escaping () -> Void) {
        guard let intentToken = intentToken else {
            completion()
            return
        }
        
        let url = URL(string: "\(config.socketUrl)\(PassageConstants.Paths.automationConfig)")!
        var request = URLRequest(url: url)
        request.addValue(intentToken, forHTTPHeaderField: "x-intent-token")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self?.cookieDomains = json["cookieDomains"] as? [String] ?? []
                self?.globalJavascript = json["globalJavascript"] as? String ?? ""
                passageLogger.debug("[REMOTE CONTROL] Configuration fetched")
            }
            completion()
        }.resume()
    }
    
    private func connectSocket() {
        let socketURL = URL(string: config.socketUrl)!
        
        passageLogger.debug("[REMOTE CONTROL] Connecting to socket URL: \(socketURL.absoluteString) with namespace: \(config.socketNamespace)")
        
        manager = SocketManager(
            socketURL: socketURL,
            config: [
                .log(true),
                .compress,
                .path(config.socketNamespace),
                .connectParams(["intentToken": intentToken ?? ""]),
                .forceWebsockets(true)
            ]
        )
        
        socket = manager?.defaultSocket
        
        passageLogger.debug("[REMOTE CONTROL] Socket manager created, socket instance: \(socket != nil ? "created" : "nil")")
        
        if socket == nil {
            passageLogger.error("[REMOTE CONTROL] Failed to create socket instance")
            return
        }
        
        passageLogger.debug("[REMOTE CONTROL] Setting up handlers...")
        setupSocketHandlers()
        
        passageLogger.debug("[REMOTE CONTROL] Connecting socket with token: \(passageLogger.truncateData(intentToken ?? "nil", maxLength: 20))")
        socket?.connect()
        
        // Check socket status after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if let status = self?.socket?.status {
                passageLogger.debug("[REMOTE CONTROL] Socket status after 1 second: \(status)")
            }
        }
    }
    
    private func setupSocketHandlers() {
        socket?.on(clientEvent: .connect) { [weak self] data, ack in
            passageLogger.debug("[REMOTE CONTROL] Connected to server")
            self?.isConnected = true
        }
        
        socket?.on(clientEvent: .error) { data, ack in
            passageLogger.error("[REMOTE CONTROL] Socket error: \(data)")
        }
        
        socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
            passageLogger.debug("[REMOTE CONTROL] Disconnected from server, reason: \(data)")
            self?.isConnected = false
        }
        
        socket?.on(clientEvent: .reconnect) { data, ack in
            passageLogger.debug("[REMOTE CONTROL] Reconnected after \(data) attempts")
        }
        
        socket?.on(clientEvent: .reconnectAttempt) { data, ack in
            passageLogger.debug("[REMOTE CONTROL] Attempting to reconnect... attempt #\(data)")
        }
        
        socket?.on(clientEvent: .statusChange) { data, ack in
            passageLogger.debug("[REMOTE CONTROL] Socket status changed: \(data)")
        }
        
        socket?.on("command") { [weak self] data, ack in
            guard let commandData = data.first as? [String: Any] else { return }
            self?.handleCommand(commandData)
        }
        
        socket?.on("welcome") { data, ack in
            passageLogger.debug("[REMOTE CONTROL] Welcome message received")
        }
    }
    
    private func handleCommand(_ commandData: [String: Any]) {
        guard let id = commandData["id"] as? String,
              let typeStr = commandData["type"] as? String,
              let type = RemoteCommand.CommandType(rawValue: typeStr) else {
            return
        }
        
        let command = RemoteCommand(
            id: id,
            type: type,
            args: commandData["args"] as? [String: Any],
            injectScript: commandData["injectScript"] as? String,
            cookieDomains: commandData["cookieDomains"] as? [String],
            userActionRequired: commandData["userActionRequired"] as? Bool
        )
        
        passageLogger.debug("[REMOTE CONTROL] Received command: \(type.rawValue)")
        
        // Handle webview switching based on userActionRequired
        if let userActionRequired = command.userActionRequired {
            if userActionRequired && currentWebViewType != PassageConstants.WebViewTypes.automation {
                // Switch to automation webview
                NotificationCenter.default.post(name: .showAutomationWebView, object: nil)
                currentWebViewType = PassageConstants.WebViewTypes.automation
            } else if !userActionRequired && currentWebViewType != PassageConstants.WebViewTypes.ui {
                // Switch to UI webview
                NotificationCenter.default.post(name: .showUIWebView, object: nil)
                currentWebViewType = PassageConstants.WebViewTypes.ui
            }
        }
        
        // Store user action commands for potential re-execution
        if command.userActionRequired == true {
            lastUserActionCommand = command
        }
        
        // Execute command
        switch command.type {
        case .navigate:
            handleNavigate(command)
        case .click, .input, .wait:
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
        
        NotificationCenter.default.post(
            name: .navigateInAutomation,
            object: nil,
            userInfo: ["url": url]
        )
        
        // Wait for navigation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.sendSuccess(commandId: command.id, data: ["url": url])
        }
    }
    
    private func handleScriptExecution(_ command: RemoteCommand) {
        guard let script = command.injectScript else {
            sendSuccess(commandId: command.id, data: nil)
            return
        }
        
        NotificationCenter.default.post(
            name: .injectScript,
            object: nil,
            userInfo: ["script": script, "commandId": command.id]
        )
    }
    
    private func handleDone(_ command: RemoteCommand) {
        let success = command.args?["success"] as? Bool ?? true
        let data = command.args?["data"]
        
        if success {
            sendSuccess(commandId: command.id, data: data)
            
            // Parse data into PassageSuccessData format
            let history = parseHistory(from: data)
            let connectionId = (data as? [String: Any])?["connectionId"] as? String ?? ""
            
            let successData = PassageSuccessData(
                history: history,
                connectionId: connectionId
            )
            onSuccess?(successData)
            
            // Navigate to success URL
            let successUrl = buildConnectUrl(success: true)
            NotificationCenter.default.post(
                name: .navigate,
                object: nil,
                userInfo: ["url": successUrl]
            )
        } else {
            let errorMessage = (data as? [String: Any])?["error"] as? String ?? "Done command indicates failure"
            sendError(commandId: command.id, error: errorMessage)
            
            let errorData = PassageErrorData(error: errorMessage, data: data)
            onError?(errorData)
            
            // Navigate to error URL
            let errorUrl = buildConnectUrl(success: false, error: errorMessage)
            NotificationCenter.default.post(
                name: .navigate,
                object: nil,
                userInfo: ["url": errorUrl]
            )
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
            URLQueryItem(name: "success", value: success.description)
        ]
        
        if let error = error {
            queryItems.append(URLQueryItem(name: "error", value: error))
        }
        
        components.queryItems = queryItems
        return components.url!.absoluteString
    }
    
    private func sendSuccess(commandId: String, data: Any?) {
        // Get page data
        NotificationCenter.default.post(
            name: .getPageData,
            object: nil,
            userInfo: ["commandId": commandId, "data": data ?? NSNull()]
        )
    }
    
    private func sendError(commandId: String, error: String) {
        let result = CommandResult(
            id: commandId,
            status: "error",
            data: nil,
            pageData: nil,
            error: error
        )
        sendResult(result)
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
                url: pageData["url"] as? String
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
    
    private func sendResult(_ result: CommandResult) {
        guard let intentToken = intentToken else { return }
        
        let url = URL(string: "\(config.socketUrl)\(PassageConstants.Paths.automationCommandResult)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(intentToken, forHTTPHeaderField: "x-intent-token")
        
        do {
            let jsonData = try JSONEncoder().encode(result)
            request.httpBody = jsonData
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    passageLogger.error("[REMOTE CONTROL] Error sending result: \(error)")
                } else {
                    passageLogger.debug("[REMOTE CONTROL] Result sent successfully")
                }
            }.resume()
        } catch {
            passageLogger.error("[REMOTE CONTROL] Error encoding result: \(error)")
        }
    }
    
    func handleWebViewMessage(_ message: [String: Any]) {
        // Handle messages from webview
        // This would be implemented based on specific message types
    }
    
    func disconnect() {
        passageLogger.debug("[REMOTE CONTROL] Disconnecting")
        
        socket?.disconnect()
        socket = nil
        manager = nil
        
        isConnected = false
        intentToken = nil
        lastUserActionCommand = nil
        currentWebViewType = PassageConstants.WebViewTypes.ui
        
        onSuccess = nil
        onError = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigate = Notification.Name("PassageNavigate")
    static let navigateInAutomation = Notification.Name("PassageNavigateInAutomation")
    static let injectScript = Notification.Name("PassageInjectScript")
    static let getPageData = Notification.Name("PassageGetPageData")
    static let showUIWebView = Notification.Name("PassageShowUIWebView")
    static let showAutomationWebView = Notification.Name("PassageShowAutomationWebView")
}

import UIKit
import PassageSDK
import WebKit

class ViewController: UIViewController {
    
    private var titleLabel: UILabel!
    private var connectButton: UIButton!
    private var resultTextView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("========== EXAMPLE APP STARTING ==========")
        print("View controller loaded")
        
        // Configure Passage SDK with debug mode
        let config = PassageConfig(
            baseUrl: PassageConstants.Defaults.baseUrl,
            socketUrl: PassageConstants.Defaults.socketUrl,
            socketNamespace: PassageConstants.Defaults.socketNamespace,
            debug: true  // Enable debug mode for comprehensive logging
        )
        
        print("Configuring SDK with:")
        print("  - Base URL: \(config.baseUrl)")
        print("  - Socket URL: \(config.socketUrl)")
        print("  - Socket Namespace: \(config.socketNamespace)")
        print("  - Debug: \(config.debug)")
        
        // Configure SDK - this will automatically set SDK version and configure all logging
        Passage.shared.configure(config)
        
        // Temporarily disable HTTP transport to avoid potential blocking
        PassageLogger.shared.configureHttpTransport(enabled: false)
        
        print("SDK configured successfully")
        
        // Set up UI programmatically
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Title Label
        titleLabel = UILabel()
        titleLabel.text = "Passage SDK Example"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // Connect Button
        connectButton = UIButton(type: .system)
        connectButton.setTitle("Connect", for: .normal)
        connectButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        connectButton.backgroundColor = .systemBlue
        connectButton.setTitleColor(.white, for: .normal)
        connectButton.layer.cornerRadius = 8
        connectButton.translatesAutoresizingMaskIntoConstraints = false
        connectButton.addTarget(self, action: #selector(connectButtonTapped), for: .touchUpInside)
        view.addSubview(connectButton)
        
        // Result Text View
        resultTextView = UITextView()
        resultTextView.font = .systemFont(ofSize: 14)
        resultTextView.layer.borderWidth = 1
        resultTextView.layer.borderColor = UIColor.systemGray4.cgColor
        resultTextView.layer.cornerRadius = 8
        resultTextView.isEditable = false
        resultTextView.isScrollEnabled = true
        resultTextView.showsVerticalScrollIndicator = true
        resultTextView.alwaysBounceVertical = true
        resultTextView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        resultTextView.text = "Results will appear here..."
        resultTextView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultTextView)
        

        
        // Set up constraints
        NSLayoutConstraint.activate([
            // Title Label
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // Connect Button
            connectButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            connectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectButton.widthAnchor.constraint(equalToConstant: 200),
            connectButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Result Text View
            resultTextView.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 30),
            resultTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            resultTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
    

    
    @objc private func connectButtonTapped() {
        print("\n========== CONNECT BUTTON TAPPED ==========")
        print("Current time: \(Date())")
        
        // Disable button and show loading state
        connectButton.isEnabled = false
        connectButton.setTitle("Fetching token...", for: .normal)
        resultTextView.text = "Fetching intent token...\n\nCheck console logs for detailed debugging information."
        
        // Fetch intent token from API
        fetchIntentToken { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let intentToken):
                    print("Successfully fetched intent token")
                    self?.connectButton.setTitle("Opening Passage...", for: .normal)
                    self?.resultTextView.text = "Opening Passage...\n\nCheck console logs for detailed debugging information."
                    
                    // Parse JWT to check details
                    self?.logTokenDetails(intentToken)
                    
                    self?.openPassage(with: intentToken)
                    
                case .failure(let error):
                    print("Failed to fetch intent token: \(error)")
                    self?.connectButton.isEnabled = true
                    self?.connectButton.setTitle("Connect", for: .normal)
                    self?.resultTextView.text = "❌ Failed to fetch intent token:\n\n\(error.localizedDescription)"
                }
            }
        }
    }
    
    private func addPadding(to base64: String) -> String {
        let remainder = base64.count % 4
        if remainder > 0 {
            return base64 + String(repeating: "=", count: 4 - remainder)
        }
        return base64
    }
    
    private func logTokenDetails(_ intentToken: String) {
        print("Intent token length: \(intentToken.count)")
        print("Using API-fetched intent token")
        
        // Parse JWT to check expiration
        let parts = intentToken.components(separatedBy: ".")
        if parts.count == 3 {
            let payload = parts[1]
            if let data = Data(base64Encoded: addPadding(to: payload)),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("JWT payload:")
                print("  - clientId: \(json["clientId"] ?? "nil")")
                print("  - integrationId: \(json["integrationId"] ?? "nil")")
                print("  - sessionId: \(json["sessionId"] ?? "nil")")
                print("  - products: \(json["products"] ?? "nil")")
                
                if let exp = json["exp"] as? Double {
                    let expDate = Date(timeIntervalSince1970: exp)
                    print("  - expires: \(expDate)")
                    print("  - is expired: \(expDate < Date())")
                }
            }
        }
    }
    
    // MARK: - API fetch method
    private func fetchIntentToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.getpassage.ai/intent-token") else {
            completion(.failure(NSError(domain: "InvalidURL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Set headers
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "accept-language")
        request.setValue("Publishable pk-live-0d017c4c-307e-441c-8b72-cb60f64f77f8", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("u=1, i", forHTTPHeaderField: "priority")
        request.setValue("\"Not;A=Brand\";v=\"99\", \"Google Chrome\";v=\"139\", \"Chromium\";v=\"139\"", forHTTPHeaderField: "sec-ch-ua")
        request.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile")
        request.setValue("\"macOS\"", forHTTPHeaderField: "sec-ch-ua-platform")
        request.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
        request.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        request.setValue("cross-site", forHTTPHeaderField: "sec-fetch-site")
        
        // Create request body with kruger integration
        let requestBody: [String: Any] = [
            "integrationId": "netflix"
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            print("Making API request to: \(url)")
            print("Request body: \(String(data: jsonData, encoding: .utf8) ?? "nil")")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Network error: \(error)")
                    completion(.failure(error))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP Status Code: \(httpResponse.statusCode)")
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "NoData", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                // Log the raw response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    print("API response: \(responseString)")
                }
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data)
                    
                    // Handle different possible response formats
                    if let dict = json as? [String: Any] {
                        // Check for "intentToken" field
                        if let intentToken = dict["intentToken"] as? String {
                            print("Found intentToken in response")
                            completion(.success(intentToken))
                            return
                        }
                        // Check for "token" field
                        if let token = dict["token"] as? String {
                            print("Found token in response")
                            completion(.success(token))
                            return
                        }
                        // Check for nested data structure
                        if let data = dict["data"] as? [String: Any], let token = data["token"] as? String {
                            print("Found token in nested data")
                            completion(.success(token))
                            return
                        }
                    }
                    
                    // If we get here, we couldn't find the token
                    let errorMsg = "Failed to parse intent token. Response: \(String(data: data, encoding: .utf8) ?? "nil")"
                    completion(.failure(NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                    
                } catch {
                    print("JSON parsing error: \(error)")
                    completion(.failure(error))
                }
            }.resume()
            
        } catch {
            print("Failed to serialize request body: \(error)")
            completion(.failure(error))
        }
    }
    
    private func openPassage(with token: String) {
        print("\n========== OPENING PASSAGE SDK ==========")
        print("Calling Passage.shared.open")
        
        // Alternative approach using PassageOpenOptions (React Native style):
        /*
        let options = PassageOpenOptions(
            intentToken: token,
            onConnectionComplete: { [weak self] (data: PassageSuccessData) in
                print("\n✅ CONNECTION COMPLETE CALLBACK TRIGGERED")
                self?.handleSuccess(data)
            },
            onConnectionError: { [weak self] (error: PassageErrorData) in
                print("\n❌ CONNECTION ERROR CALLBACK TRIGGERED")
                self?.handleError(error)
            },
            onDataComplete: { [weak self] (data: PassageDataResult) in
                print("\n📊 DATA COMPLETE CALLBACK TRIGGERED")
                self?.handleDataComplete(data)
            },
            onPromptComplete: { [weak self] (prompt: PassagePromptResponse) in
                print("\n🎯 PROMPT COMPLETE CALLBACK TRIGGERED")
                self?.handlePromptComplete(prompt)
            },
            onExit: { [weak self] (reason: String?) in
                print("\n🚪 EXIT CALLBACK TRIGGERED - Reason: \(reason ?? "unknown")")
                self?.handleClose()
            },
            onWebviewChange: { [weak self] (webviewType: String) in
                print("\n🔄 WEBVIEW CHANGE CALLBACK TRIGGERED - Type: \(webviewType)")
                self?.handleWebviewChange(webviewType)
            },
            presentationStyle: .modal
        )
        Passage.shared.open(options, from: self)
        */
        
        // Current approach using individual parameters:
        Passage.shared.open(
            token: token,
            presentationStyle: .modal,
            from: self,
            onConnectionComplete: { [weak self] (data: PassageSuccessData) in
                print("\n✅ CONNECTION COMPLETE CALLBACK TRIGGERED")
                self?.handleSuccess(data)
            },
            onConnectionError: { [weak self] (error: PassageErrorData) in
                print("\n❌ CONNECTION ERROR CALLBACK TRIGGERED")
                self?.handleError(error)
            },
            onDataComplete: { [weak self] (data: PassageDataResult) in
                print("\n📊 DATA COMPLETE CALLBACK TRIGGERED")
                self?.handleDataComplete(data)
            },
            onPromptComplete: { [weak self] (prompt: PassagePromptResponse) in
                print("\n🎯 PROMPT COMPLETE CALLBACK TRIGGERED")
                self?.handlePromptComplete(prompt)
            },
            onExit: { [weak self] (reason: String?) in
                print("\n🚪 EXIT CALLBACK TRIGGERED - Reason: \(reason ?? "unknown")")
                self?.handleClose()
            },
            onWebviewChange: { [weak self] (webviewType: String) in
                print("\n🔄 WEBVIEW CHANGE CALLBACK TRIGGERED - Type: \(webviewType)")
                self?.handleWebviewChange(webviewType)
            }
        )
        
        print("Passage.shared.open called, waiting for callbacks...")
    }
    
    private func handleSuccess(_ data: PassageSuccessData) {
        DispatchQueue.main.async { [weak self] in
            self?.connectButton.isEnabled = true
            self?.connectButton.setTitle("Connect", for: .normal)
            self?.displayResult(data, isError: false)
        }
    }
    
    private func handleError(_ error: PassageErrorData) {
        print("Error details:")
        print("  - Error message: \(error.error)")
        print("  - Error data: \(String(describing: error.data))")
        
        DispatchQueue.main.async { [weak self] in
            self?.connectButton.isEnabled = true
            self?.connectButton.setTitle("Connect", for: .normal)
            self?.displayResult(error, isError: true)
        }
    }
    
    private func handleDataComplete(_ data: PassageDataResult) {
        print("Data complete details:")
        print("  - Data: \(String(describing: data.data))")
        print("  - Prompts: \(data.prompts?.count ?? 0)")
        
        // This callback provides additional data when available
        // In most cases, the main data will still come through onConnectionComplete
    }
    
    private func handlePromptComplete(_ prompt: PassagePromptResponse) {
        print("Prompt complete details:")
        print("  - Key: \(prompt.key)")
        print("  - Value: \(prompt.value)")
        print("  - Response: \(String(describing: prompt.response))")
        
        // This callback is triggered when prompt processing completes
    }
    
    private func handleWebviewChange(_ webviewType: String) {
        print("Webview changed to: \(webviewType)")
        
        DispatchQueue.main.async { [weak self] in
            // Update UI to reflect webview change if needed
            if webviewType == "automation" {
                self?.connectButton.setTitle("Automation Active", for: .normal)
            } else {
                self?.connectButton.setTitle("Opening Passage...", for: .normal)
            }
        }
    }
    
    private func handleClose() {
        DispatchQueue.main.async { [weak self] in
            self?.connectButton.isEnabled = true
            self?.connectButton.setTitle("Connect", for: .normal)
            if self?.resultTextView.text == "Opening Passage..." || self?.resultTextView.text?.contains("Automation Active") == true {
                self?.resultTextView.text = "Passage closed"
            }
        }
    }
    
    private func displayResult(_ message: Any, isError: Bool) {
        var resultText = ""
        
        if isError {
            resultText = "❌ Error:\n\n"
            if let error = message as? PassageErrorData {
                // Format error as JSON
                let errorDict: [String: Any] = [
                    "success": false,
                    "error": error.error,
                    "data": error.data ?? NSNull()
                ]
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: errorDict, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    resultText += jsonString
                } else {
                    resultText += "Error: \(error.error)\n"
                    if let data = error.data {
                        resultText += "Data: \(data)\n"
                    }
                }
            } else {
                resultText += String(describing: message)
            }
        } else {
            resultText = "✅ Success:\n\n"
            if let data = message as? PassageSuccessData {
                // Format success data as JSON
                var historyArray: [[String: Any]] = []
                
                for item in data.history {
                    var historyItem: [String: Any] = [:]
                    if let structuredData = item.structuredData {
                        historyItem["structuredData"] = structuredData
                    }
                    if !item.additionalData.isEmpty {
                        historyItem["additionalData"] = item.additionalData
                    }
                    historyArray.append(historyItem)
                }
                
                let successDict: [String: Any] = [
                    "success": true,
                    "connectionId": data.connectionId,
                    "historyCount": data.history.count,
                    "history": historyArray
                ]
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: successDict, options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    resultText += jsonString
                } else {
                    // Fallback to original format if JSON serialization fails
                    resultText += "Connection ID: \(data.connectionId)\n"
                    resultText += "History Items: \(data.history.count)\n\n"
                    
                    if !data.history.isEmpty {
                        resultText += "Data:\n"
                        for (index, item) in data.history.enumerated() {
                            if index >= 5 {
                                resultText += "... and \(data.history.count - 5) more items\n"
                                break
                            }
                            
                            if let structuredData = item.structuredData as? [String: Any] {
                                if let title = structuredData["title"] as? String {
                                    resultText += "\(index + 1). \(title)\n"
                                } else {
                                    resultText += "\(index + 1). \(structuredData)\n"
                                }
                            } else {
                                resultText += "\(index + 1). \(item.structuredData ?? "No data")\n"
                            }
                        }
                    } else {
                        resultText += "No data items found\n"
                    }
                }
            } else {
                resultText += String(describing: message)
            }
        }
        
        resultTextView.text = resultText
    }
}

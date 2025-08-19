import UIKit
import PassageSDK

class ViewController: UIViewController {
    
    private var titleLabel: UILabel!
    private var connectButton: UIButton!
    private var resultTextView: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure Passage SDK with debug mode
        let config = PassageConfig(
            debug: true
        )
        PassageSDK.shared.configure(config)
        
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
        resultTextView.text = ""
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
        // Disable button and show loading state
        connectButton.isEnabled = false
        connectButton.setTitle("Opening Passage...", for: .normal)
        resultTextView.text = "Opening Passage..."
        
        // Use hardcoded intent token
        let intentToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJjbGllbnRJZCI6ImMyNDUxZTkxODQxZmE2ZjYxMDU2MWQ1OWRkOGI0OGUxIiwiaW50ZWdyYXRpb25JZCI6Im5ldGZsaXgiLCJzZXNzaW9uSWQiOiI3MmYwNGJiYi03ZjFmLTQ4MWItYTFjZC05ODU2ZmI4NGY2N2EiLCJwcm9kdWN0cyI6WyJoaXN0b3J5Il0sImlhdCI6MTc1NTYzMzEwMiwiZXhwIjoxNzU4MjI1MTAyLCJhdWQiOiJpbnRlbnQtdG9rZW5zIiwiaXNzIjoiZ3JhdnktY29ubmVjdC1hcGkifQ.6i7OMxkzinkbSR_5HX2P6x2FcG-0hvJM4qtgwSIfNHs"
        
        print("Using hardcoded intent token")
        openPassage(with: intentToken)
    }
    
    // MARK: - Server fetch method (commented out - using hardcoded token)
    /*
    private func fetchIntentToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "http://localhost:3005/intent-token?integrationId=kindle") else {
            completion(.failure(NSError(domain: "InvalidURL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "NoData", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            // Log the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Server response: \(responseString)")
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data)
                
                // Handle different possible response formats
                if let dict = json as? [String: Any] {
                    // Check for "intentToken" field
                    if let intentToken = dict["intentToken"] as? String {
                        print("Intent Token: \(intentToken)")
                        completion(.success(intentToken))
                        return
                    }
                    // Check for "token" field
                    if let token = dict["token"] as? String {
                        print("Token: \(token)")
                        completion(.success(token))
                        return
                    }
                    // Check for nested data structure
                    if let data = dict["data"] as? [String: Any], let token = data["token"] as? String {
                        print("Nested Token: \(token)")
                        completion(.success(token))
                        return
                    }
                }
                
                // If we get here, we couldn't find the token
                let errorMsg = "Failed to parse intent token. Response: \(String(data: data, encoding: .utf8) ?? "nil")"
                completion(.failure(NSError(domain: "ParseError", code: 0, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    */
    
    private func openPassage(with token: String) {
        PassageSDK.shared.open(
            token: token,
            presentationStyle: .modal,
            from: self,
            onSuccess: { [weak self] data in
                self?.handleSuccess(data)
            },
            onError: { [weak self] error in
                self?.handleError(error)
            },
            onClose: { [weak self] in
                self?.handleClose()
            }
        )
    }
    
    private func handleSuccess(_ data: PassageSuccessData) {
        DispatchQueue.main.async { [weak self] in
            self?.connectButton.isEnabled = true
            self?.connectButton.setTitle("Connect", for: .normal)
            self?.displayResult(data, isError: false)
        }
    }
    
    private func handleError(_ error: PassageErrorData) {
        DispatchQueue.main.async { [weak self] in
            self?.connectButton.isEnabled = true
            self?.connectButton.setTitle("Connect", for: .normal)
            self?.displayResult(error, isError: true)
        }
    }
    
    private func handleClose() {
        DispatchQueue.main.async { [weak self] in
            self?.connectButton.isEnabled = true
            self?.connectButton.setTitle("Connect", for: .normal)
            if self?.resultTextView.text == "Opening Passage..." {
                self?.resultTextView.text = "Passage closed"
            }
        }
    }
    
    private func displayResult(_ message: Any, isError: Bool) {
        var resultText = ""
        
        if isError {
            resultText = "❌ Error:\n\n"
            if let error = message as? PassageErrorData {
                resultText += "Error: \(error.error)\n"
                if let data = error.data {
                    resultText += "Data: \(data)\n"
                }
            } else {
                resultText += String(describing: message)
            }
        } else {
            resultText = "✅ Success:\n\n"
            if let data = message as? PassageSuccessData {
                if let jsonData = try? JSONSerialization.data(withJSONObject: ["data": data.connectionId], options: .prettyPrinted),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    resultText += jsonString
                } else {
                    resultText += "Connection ID: \(data.connectionId)\n"
                }
            } else {
                resultText += String(describing: message)
            }
        }
        
        resultTextView.text = resultText
    }
}

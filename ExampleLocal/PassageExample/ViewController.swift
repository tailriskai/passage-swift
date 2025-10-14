import UIKit
import PassageSDK
import WebKit

class ViewController: UIViewController {

    // MARK: - Configuration URLs
    private let passageUIUrl = "http://localhost:3001"
    private let passageAPIUrl = "http://localhost:3000"
    private let passageSocketUrl = "http://localhost:3000"
    private let defaultPublishableKey = "pk-live-0d017c4c-307e-441c-8b72-cb60f64f77f8"

    // MARK: - UI Components
    private var titleLabel: UILabel!
    private var connectButton: UIButton!
    private var initializeButton: UIButton!
    private var resultTextView: UITextView!
    private var integrationLabel: UILabel!
    private var integrationButton: UIButton!
    private var tokenLabel: UILabel!
    private var tokenTextView: UITextView!
    private var modeSegmentedControl: UISegmentedControl!
    private var clearCookiesSwitch: UISwitch!
    private var clearCookiesLabel: UILabel!
    private var clearCookiesStackView: UIStackView!
    private var recordModeSwitch: UISwitch!
    private var recordModeLabel: UILabel!
    private var recordModeStackView: UIStackView!

    // MARK: - State
    private var selectedIntegration: String = "kroger"
    private var exitCallCount: Int = 0  // Track onExit callback calls
    private var isInitialized: Bool = false  // Track SDK initialization state

    // Record mode bottom sheet
    private var recordModeBottomSheet: RecordModeBottomSheet?
    private var isRecordModeActive = false
    
    // Constraint references for dynamic layout
    private var connectButtonTopConstraint: NSLayoutConstraint!
    private var initializeButtonTopConstraint: NSLayoutConstraint!
    private var resultTextViewTopConstraint: NSLayoutConstraint!
    
    private var integrationOptions: [(value: String, label: String)] = [
        ("passage-test-captcha", "Passage Test Integration (with CAPTCHA)"),
        ("passage-test", "Passage Test Integration"),
        ("amazon", "Amazon"),
        ("uber", "Uber"),
        ("kroger", "Kroger"),
        ("kindle", "Kindle"),
        ("audible", "Audible"),
        ("youtube", "YouTube"),
        ("netflix", "Netflix"),
        ("doordash", "Doordash"),
        ("ubereats", "UberEats"),
        ("chess", "Chess.com"),
        ("spotify", "Spotify"),
        ("verizon", "Verizon"),
        ("chewy", "Chewy"),
        ("att", "AT&T")
    ]

    private var isLoadingIntegrations = false

    override func viewDidLoad() {
        super.viewDidLoad()

        print("========== EXAMPLE APP STARTING ==========")
        print("View controller loaded")

        // Configure Passage SDK with debug mode
        let config = PassageConfig(
            uiUrl: passageUIUrl,
            apiUrl: passageAPIUrl,
            socketUrl: passageSocketUrl,
            debug: true
        )

        print("Configuring SDK with:")
        print("  - UI URL: \(config.uiUrl)")
        print("  - API URL: \(config.apiUrl)")
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

        // Fetch available integrations from API
        fetchIntegrations()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Title Label
        titleLabel = UILabel()
        titleLabel.text = "Passage SDK"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Mode Segmented Control
        modeSegmentedControl = UISegmentedControl(items: ["Auto-Fetch Token", "Manual Token"])
        modeSegmentedControl.selectedSegmentIndex = 0
        modeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        modeSegmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        view.addSubview(modeSegmentedControl)

        // Integration Label
        integrationLabel = UILabel()
        integrationLabel.text = "Integration Type:"
        integrationLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        integrationLabel.textColor = .label
        integrationLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(integrationLabel)

        // Integration Button
        integrationButton = UIButton(type: .system)
        integrationButton.setTitle("Loading integrations...", for: .normal)
        integrationButton.titleLabel?.font = .systemFont(ofSize: 16)
        integrationButton.backgroundColor = .systemGray6
        integrationButton.setTitleColor(.label, for: .normal)
        integrationButton.layer.cornerRadius = 8
        integrationButton.layer.borderWidth = 1
        integrationButton.layer.borderColor = UIColor.systemGray4.cgColor
        integrationButton.contentHorizontalAlignment = .left
        integrationButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 0)
        integrationButton.translatesAutoresizingMaskIntoConstraints = false
        integrationButton.addTarget(self, action: #selector(integrationButtonTapped), for: .touchUpInside)
        integrationButton.isEnabled = false  // Disable while loading integrations
        view.addSubview(integrationButton)

        // Clear Cookies Stack View (for auto-fetch mode)
        clearCookiesStackView = UIStackView()
        clearCookiesStackView.axis = .horizontal
        clearCookiesStackView.spacing = 12
        clearCookiesStackView.alignment = .center
        clearCookiesStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clearCookiesStackView)

        // Clear Cookies Switch
        clearCookiesSwitch = UISwitch()
        clearCookiesSwitch.isOn = false
        clearCookiesSwitch.translatesAutoresizingMaskIntoConstraints = false
        clearCookiesStackView.addArrangedSubview(clearCookiesSwitch)

        // Clear Cookies Label
        clearCookiesLabel = UILabel()
        clearCookiesLabel.text = "Clear all cookies"
        clearCookiesLabel.font = .systemFont(ofSize: 16)
        clearCookiesLabel.textColor = .label
        clearCookiesLabel.translatesAutoresizingMaskIntoConstraints = false
        clearCookiesStackView.addArrangedSubview(clearCookiesLabel)

        // Add spacer to push content to the left
        let spacerView = UIView()
        spacerView.translatesAutoresizingMaskIntoConstraints = false
        clearCookiesStackView.addArrangedSubview(spacerView)

        // Record Mode Stack View (for auto-fetch mode)
        recordModeStackView = UIStackView()
        recordModeStackView.axis = .horizontal
        recordModeStackView.spacing = 12
        recordModeStackView.alignment = .center
        recordModeStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recordModeStackView)

        // Record Mode Switch
        recordModeSwitch = UISwitch()
        recordModeSwitch.isOn = false
        recordModeSwitch.translatesAutoresizingMaskIntoConstraints = false
        recordModeStackView.addArrangedSubview(recordModeSwitch)

        // Record Mode Label
        recordModeLabel = UILabel()
        recordModeLabel.text = "Record mode"
        recordModeLabel.font = .systemFont(ofSize: 16)
        recordModeLabel.textColor = .label
        recordModeLabel.translatesAutoresizingMaskIntoConstraints = false
        recordModeStackView.addArrangedSubview(recordModeLabel)

        // Add spacer to push content to the left
        let recordSpacerView = UIView()
        recordSpacerView.translatesAutoresizingMaskIntoConstraints = false
        recordModeStackView.addArrangedSubview(recordSpacerView)

        // Token Label
        tokenLabel = UILabel()
        tokenLabel.text = "Intent Token:"
        tokenLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        tokenLabel.textColor = .label
        tokenLabel.translatesAutoresizingMaskIntoConstraints = false
        tokenLabel.isHidden = true  // Hidden by default (auto-fetch mode)
        view.addSubview(tokenLabel)

        // Token Text View (better for handling long tokens)
        tokenTextView = UITextView()
        tokenTextView.text = ""
        tokenTextView.font = .systemFont(ofSize: 14)
        tokenTextView.backgroundColor = .systemGray6
        tokenTextView.layer.cornerRadius = 8
        tokenTextView.layer.borderWidth = 1
        tokenTextView.layer.borderColor = UIColor.systemGray4.cgColor
        tokenTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        tokenTextView.isScrollEnabled = true
        tokenTextView.showsVerticalScrollIndicator = true
        tokenTextView.translatesAutoresizingMaskIntoConstraints = false
        tokenTextView.isHidden = true  // Hidden by default (auto-fetch mode)
        tokenTextView.delegate = self
        view.addSubview(tokenTextView)

        // Add placeholder label for the text view
        let placeholderLabel = UILabel()
        placeholderLabel.text = "Paste intent token here..."
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.tag = 999 // Tag to identify placeholder
        tokenTextView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: tokenTextView.topAnchor, constant: 16),
            placeholderLabel.leadingAnchor.constraint(equalTo: tokenTextView.leadingAnchor, constant: 12)
        ])

        // Initialize Button
        initializeButton = UIButton(type: .system)
        initializeButton.setTitle("Initialize SDK", for: .normal)
        initializeButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        initializeButton.backgroundColor = .systemGreen
        initializeButton.setTitleColor(.white, for: .normal)
        initializeButton.layer.cornerRadius = 8
        initializeButton.translatesAutoresizingMaskIntoConstraints = false
        initializeButton.addTarget(self, action: #selector(initializeButtonTapped), for: .touchUpInside)
        initializeButton.isHidden = true  // Hidden by default (auto-fetch mode)
        view.addSubview(initializeButton)

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
        // Create dynamic constraints for button positioning
        connectButtonTopConstraint = connectButton.topAnchor.constraint(equalTo: recordModeStackView.bottomAnchor, constant: 30)
        initializeButtonTopConstraint = initializeButton.topAnchor.constraint(equalTo: tokenTextView.bottomAnchor, constant: 20)
        resultTextViewTopConstraint = resultTextView.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 20)

        NSLayoutConstraint.activate([
            // Title Label
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Mode Segmented Control
            modeSegmentedControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            modeSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            modeSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Integration Label (for auto-fetch mode)
            integrationLabel.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 20),
            integrationLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            integrationLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Integration Button (for auto-fetch mode)
            integrationButton.topAnchor.constraint(equalTo: integrationLabel.bottomAnchor, constant: 8),
            integrationButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            integrationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            integrationButton.heightAnchor.constraint(equalToConstant: 44),

            // Clear Cookies Stack View (for auto-fetch mode)
            clearCookiesStackView.topAnchor.constraint(equalTo: integrationButton.bottomAnchor, constant: 16),
            clearCookiesStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            clearCookiesStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Record Mode Stack View (for auto-fetch mode)
            recordModeStackView.topAnchor.constraint(equalTo: clearCookiesStackView.bottomAnchor, constant: 12),
            recordModeStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            recordModeStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Token Label (for manual mode)
            tokenLabel.topAnchor.constraint(equalTo: modeSegmentedControl.bottomAnchor, constant: 20),
            tokenLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tokenLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Token Text View (for manual mode)
            tokenTextView.topAnchor.constraint(equalTo: tokenLabel.bottomAnchor, constant: 8),
            tokenTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tokenTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tokenTextView.heightAnchor.constraint(equalToConstant: 80),

            // Initialize Button (for manual mode) - positioned dynamically
            initializeButtonTopConstraint,
            initializeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            initializeButton.widthAnchor.constraint(equalToConstant: 200),
            initializeButton.heightAnchor.constraint(equalToConstant: 50),

            // Connect Button (positioned dynamically based on mode)
            connectButtonTopConstraint,
            connectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectButton.widthAnchor.constraint(equalToConstant: 200),
            connectButton.heightAnchor.constraint(equalToConstant: 50),

            // Result Text View
            resultTextViewTopConstraint,
            resultTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            resultTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])

        // Set initial mode state
        modeChanged()
    }

    private func getSelectedIntegrationLabel() -> String {
        return integrationOptions.first { $0.value == selectedIntegration }?.label ?? "Select Integration"
    }

    @objc private func integrationButtonTapped() {
        let alertController = UIAlertController(title: "Select Integration", message: nil, preferredStyle: .actionSheet)

        for option in integrationOptions {
            let action = UIAlertAction(title: option.label, style: .default) { [weak self] _ in
                self?.selectedIntegration = option.value
                self?.integrationButton.setTitle(option.label, for: .normal)
                print("Selected integration: \(option.label)")
            }

            if option.value == selectedIntegration {
                action.setValue(UIImage(systemName: "checkmark"), forKey: "image")
            }

            alertController.addAction(action)
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alertController.addAction(cancelAction)

        // For iPad support
        if let popover = alertController.popoverPresentationController {
            popover.sourceView = integrationButton
            popover.sourceRect = integrationButton.bounds
        }

        present(alertController, animated: true)
    }

    @objc private func modeChanged() {
        let isManualMode = modeSegmentedControl.selectedSegmentIndex == 1

        // Show/hide manual token controls
        tokenLabel.isHidden = !isManualMode
        tokenTextView.isHidden = !isManualMode
        initializeButton.isHidden = !isManualMode

        // Update integration label visibility
        integrationLabel.isHidden = isManualMode
        integrationButton.isHidden = isManualMode
        clearCookiesStackView.isHidden = isManualMode
        recordModeStackView.isHidden = isManualMode

        // Update button positioning constraints
        connectButtonTopConstraint.isActive = false
        initializeButtonTopConstraint.isActive = false

        if isManualMode {
            // In manual mode, both buttons use the same position (below token text view)
            connectButtonTopConstraint = connectButton.topAnchor.constraint(equalTo: tokenTextView.bottomAnchor, constant: 20)
            initializeButtonTopConstraint = initializeButton.topAnchor.constraint(equalTo: tokenTextView.bottomAnchor, constant: 20)
        } else {
            // In auto-fetch mode, position connect button below record mode stack view
            connectButtonTopConstraint = connectButton.topAnchor.constraint(equalTo: recordModeStackView.bottomAnchor, constant: 30)
            // Initialize button constraint doesn't matter in auto-fetch mode since it's hidden
            initializeButtonTopConstraint = initializeButton.topAnchor.constraint(equalTo: tokenTextView.bottomAnchor, constant: 20)
        }

        connectButtonTopConstraint.isActive = true
        initializeButtonTopConstraint.isActive = true

        // Reset initialization state when switching modes
        if !isManualMode {
            isInitialized = false
        }

        // Update button states based on mode
        if isManualMode {
            updateButtonStates()
        } else {
            // In auto-fetch mode, always show connect button and hide initialize button
            initializeButton.isHidden = true
            connectButton.isHidden = false
            connectButton.setTitle("Connect", for: .normal)
            connectButton.isEnabled = true
            connectButton.backgroundColor = .systemBlue
        }

        // Update result text view constraint to reference the visible button
        updateResultTextViewConstraint()

        print("Mode changed to: \(isManualMode ? "Manual Token" : "Auto-Fetch Token")")
    }

    private func updateButtonStates() {
        let isManualMode = modeSegmentedControl.selectedSegmentIndex == 1
        guard isManualMode else { return }

        let hasToken = !(tokenTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        if !isInitialized {
            // Show only initialize button when not initialized
            initializeButton.isHidden = false
            connectButton.isHidden = true

            initializeButton.isEnabled = hasToken
            initializeButton.backgroundColor = hasToken ? .systemGreen : .systemGray
            initializeButton.setTitle(hasToken ? "Initialize SDK" : "Enter Token First", for: .normal)
        } else {
            // Show only connect button when initialized
            initializeButton.isHidden = true
            connectButton.isHidden = false

            connectButton.isEnabled = true
            connectButton.backgroundColor = .systemBlue
            connectButton.setTitle("Open Passage", for: .normal)
        }

        // Update result text view constraint to reference the visible button
        updateResultTextViewConstraint()
    }

    private func updateResultTextViewConstraint() {
        resultTextViewTopConstraint.isActive = false

        let isManualMode = modeSegmentedControl.selectedSegmentIndex == 1

        if isManualMode {
            // In manual mode, reference whichever button is currently visible
            if !initializeButton.isHidden {
                resultTextViewTopConstraint = resultTextView.topAnchor.constraint(equalTo: initializeButton.bottomAnchor, constant: 20)
            } else {
                resultTextViewTopConstraint = resultTextView.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 20)
            }
        } else {
            // In auto-fetch mode, always reference connect button
            resultTextViewTopConstraint = resultTextView.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 20)
        }

        resultTextViewTopConstraint.isActive = true
    }

    @objc private func initializeButtonTapped() {
        print("\n========== INITIALIZE BUTTON TAPPED ==========")

        guard let token = tokenTextView.text, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            resultTextView.text = "❌ Please enter an intent token"
            return
        }

        // Disable button and show loading state
        initializeButton.isEnabled = false
        initializeButton.setTitle("Initializing...", for: .normal)
        resultTextView.text = "Initializing SDK with provided token...\n\nCheck console logs for detailed debugging information."

        // Parse JWT to check details
        logTokenDetails(token)

        // Initialize SDK with the provided token
        initializeSDK(with: token)
    }

    @objc private func connectButtonTapped() {
        print("\n========== CONNECT BUTTON TAPPED ==========")
        print("Current time: \(Date())")

        let isManualMode = modeSegmentedControl.selectedSegmentIndex == 1

        if isManualMode {
            // Manual mode - use the token from text field
            guard isInitialized else {
                resultTextView.text = "❌ Please initialize the SDK first"
                return
            }

            guard let token = tokenTextView.text, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                resultTextView.text = "❌ Please enter an intent token"
                return
            }

            // Disable button and show loading state
            connectButton.isEnabled = false
            connectButton.setTitle("Opening Passage...", for: .normal)
            resultTextView.text = "Opening Passage with initialized SDK...\n\nCheck console logs for detailed debugging information."

            openPassage(with: token)
        } else {
            // Auto-fetch mode - fetch token from API
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

        // Parse JWT to check expiration and record mode
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

                // 🔑 Check for record mode flag
                if let recordFlag = json["record"] as? Bool, recordFlag {
                    print("  - ✅ RECORD MODE ENABLED")
                    isRecordModeActive = true
                } else {
                    print("  - record mode: false")
                    isRecordModeActive = false
                }
            }
        }
    }

    private func showRecordModeBottomSheet() {
        guard isRecordModeActive else {
            print("[RecordMode] Not in record mode, skipping bottom sheet")
            return
        }

        print("[RecordMode] Showing record mode bottom sheet")

        // Create bottom sheet if needed
        if recordModeBottomSheet == nil {
            recordModeBottomSheet = RecordModeBottomSheet()
            recordModeBottomSheet?.onRecordingComplete = { [weak self] in
                print("[RecordMode] Recording completed via bottom sheet")
                self?.hideRecordModeBottomSheet()
            }
        }

        guard let bottomSheet = recordModeBottomSheet else { return }
        guard let window = view.window else {
            print("[RecordMode] No window available, cannot show bottom sheet")
            return
        }

        // Add to window so it appears on top of everything
        window.addSubview(bottomSheet.view)

        // Position at bottom of window
        bottomSheet.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bottomSheet.view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            bottomSheet.view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            bottomSheet.view.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            bottomSheet.view.heightAnchor.constraint(equalToConstant: 240)
        ])

        // Bring to front
        window.bringSubviewToFront(bottomSheet.view)

        // Animate in
        bottomSheet.view.transform = CGAffineTransform(translationX: 0, y: 240)
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            bottomSheet.view.transform = CGAffineTransform.identity
        }
    }

    private func hideRecordModeBottomSheet() {
        guard let bottomSheet = recordModeBottomSheet else { return }

        print("[RecordMode] Hiding record mode bottom sheet")

        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn, animations: {
            bottomSheet.view.transform = CGAffineTransform(translationX: 0, y: 240)
        }) { (_: Bool) in
            bottomSheet.willMove(toParent: nil)
            bottomSheet.view.removeFromSuperview()
            bottomSheet.removeFromParent()
        }
    }

    // MARK: - SDK Initialize method
    private func initializeSDK(with token: String) {
        print("\n========== INITIALIZING SDK ==========")
        print("Calling Passage.shared.initialize")

        // Extract publishable key from token (if available) or use a default
        let publishableKey = extractPublishableKey(from: token) ?? defaultPublishableKey

        let options = PassageInitializeOptions(
            publishableKey: publishableKey,
            prompts: nil, // No prompts for now
            onConnectionComplete: { [weak self] (data: PassageSuccessData) in
                print("\n✅ INITIALIZE - CONNECTION COMPLETE CALLBACK TRIGGERED")
                print("Connection complete data: \(data)")
                self?.handleSuccess(data)
            },
            onError: { [weak self] (error: PassageErrorData) in
                print("\n❌ INITIALIZE - CONNECTION ERROR CALLBACK TRIGGERED")
                self?.handleError(error)
            },
            onDataComplete: { [weak self] (data: PassageDataResult) in
                print("\n📊 INITIALIZE - DATA COMPLETE CALLBACK TRIGGERED")
                self?.handleDataComplete(data)
            },
            onPromptComplete: { [weak self] (prompt: PassagePromptResponse) in
                print("\n🎯 INITIALIZE - PROMPT COMPLETE CALLBACK TRIGGERED")
                self?.handlePromptComplete(prompt)
            },
            onExit: { [weak self] (reason: String?) in
                self?.exitCallCount += 1
                print("\n🚪 INITIALIZE - EXIT CALLBACK TRIGGERED #\(self?.exitCallCount ?? 0) - Reason: \(reason ?? "unknown")")
                print("Total exit callbacks received: \(self?.exitCallCount ?? 0)")
                self?.handleClose()
            }
        )

        Task {
            do {
                try await Passage.shared.initialize(options)

                DispatchQueue.main.async { [weak self] in
                    print("✅ SDK initialized successfully")
                    self?.isInitialized = true

                    // Update button states based on current token
                    self?.updateButtonStates()

                    self?.resultTextView.text = "✅ SDK initialized successfully!\n\nYou can now open Passage with the provided token.\n\nPublishable Key: \(publishableKey)"
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    print("❌ SDK initialization failed: \(error)")

                    // Update button states to reflect failure
                    self?.updateButtonStates()

                    self?.resultTextView.text = "❌ SDK initialization failed:\n\n\(error.localizedDescription)"
                }
            }
        }
    }

    private func extractPublishableKey(from token: String) -> String? {
        // Try to extract publishable key from JWT token
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else { return nil }

        let payload = components[1]
        guard let data = Data(base64Encoded: addPadding(to: payload)) else { return nil }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let clientId = json["clientId"] as? String {
                return clientId
            }
        } catch {
            print("Failed to decode publishable key from intent token: \(error)")
        }

        return nil
    }

    // MARK: - API fetch methods
    private func fetchIntegrations() {
        guard !isLoadingIntegrations else {
            print("Integrations already loading, skipping...")
            return
        }

        isLoadingIntegrations = true

        guard let url = URL(string: "\(passageAPIUrl)/integrations") else {
            print("❌ Invalid integrations URL")
            isLoadingIntegrations = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        print("Fetching integrations from: \(url)")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoadingIntegrations = false
            }

            if let error = error {
                print("❌ Network error fetching integrations: \(error)")
                self?.fallbackToDefaultIntegrations()
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("Integrations HTTP Status Code: \(httpResponse.statusCode)")
            }

            guard let data = data else {
                print("❌ No data received from integrations endpoint")
                self?.fallbackToDefaultIntegrations()
                return
            }

            // Log the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Integrations API response: \(responseString)")
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data)

                if let integrations = json as? [[String: Any]] {
                    // Handle array of integrations
                    self?.updateIntegrationsFromAPI(integrations)
                } else if let dict = json as? [String: Any] {
                    // Handle wrapped response (e.g., {"integrations": [...]} or {"data": [...]})
                    if let integrations = dict["integrations"] as? [[String: Any]] {
                        self?.updateIntegrationsFromAPI(integrations)
                    } else if let integrations = dict["data"] as? [[String: Any]] {
                        self?.updateIntegrationsFromAPI(integrations)
                    } else {
                        print("❌ Unexpected integrations response format")
                    }
                } else {
                    print("❌ Unexpected integrations response type")
                    self?.fallbackToDefaultIntegrations()
                }

            } catch {
                print("❌ JSON parsing error for integrations: \(error)")
                self?.fallbackToDefaultIntegrations()
            }
        }.resume()
    }

    private func updateIntegrationsFromAPI(_ integrations: [[String: Any]]) {
        var newIntegrations: [(value: String, label: String)] = []

        for integration in integrations {
            // Handle both id/slug formats for integration identifier
            if let slug = integration["slug"] as? String {
                let name = integration["name"] as? String ?? integration["displayName"] as? String ?? slug.capitalized
                newIntegrations.append((value: slug, label: name))
            } else if let id = integration["id"] as? String {
                let name = integration["name"] as? String ?? integration["displayName"] as? String ?? id.capitalized
                newIntegrations.append((value: id, label: name))
            }
        }

        // Only update if we got valid data
        if !newIntegrations.isEmpty {
            DispatchQueue.main.async { [weak self] in
                print("✅ Successfully loaded \(newIntegrations.count) integrations from API")
                self?.integrationOptions = newIntegrations

                // If current selection is not in new list, reset to first option
                if let currentSelection = self?.selectedIntegration,
                   !newIntegrations.contains(where: { $0.value == currentSelection }),
                   let firstOption = newIntegrations.first {
                    self?.selectedIntegration = firstOption.value
                    self?.integrationButton.setTitle(firstOption.label, for: .normal)
                    print("Reset integration selection to: \(firstOption.label)")
                }

                // Update button title with the current selection
                self?.integrationButton.setTitle(self?.getSelectedIntegrationLabel(), for: .normal)

                // Enable the button since integrations are now loaded
                self?.integrationButton.isEnabled = true
            }
        } else {
            print("⚠️ No valid integrations found in API response, keeping default list")
            fallbackToDefaultIntegrations()
        }
    }

    private func fallbackToDefaultIntegrations() {
        DispatchQueue.main.async { [weak self] in
            print("🔄 Falling back to default integrations list")

            // Enable the button with the default selection
            self?.integrationButton.isEnabled = true
            self?.integrationButton.setTitle(self?.getSelectedIntegrationLabel(), for: .normal)
        }
    }

    private func fetchIntentToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "\(passageAPIUrl)/intent-token") else {
            completion(.failure(NSError(domain: "InvalidURL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Set headers
        request.setValue("*/*", forHTTPHeaderField: "accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "accept-language")
        request.setValue("Publishable \(defaultPublishableKey)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("u=1, i", forHTTPHeaderField: "priority")
        request.setValue("\"Not;A=Brand\";v=\"99\", \"Google Chrome\";v=\"139\", \"Chromium\";v=\"139\"", forHTTPHeaderField: "sec-ch-ua")
        request.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile")
        request.setValue("\"macOS\"", forHTTPHeaderField: "sec-ch-ua-platform")
        request.setValue("empty", forHTTPHeaderField: "sec-fetch-dest")
        request.setValue("cors", forHTTPHeaderField: "sec-fetch-mode")
        request.setValue("cross-site", forHTTPHeaderField: "sec-fetch-site")

        // Create request body with selected integration and clearAllCookies flag
        var requestBody: [String: Any] = [
            "integrationId": selectedIntegration,
            "resources": [
                "Trip": [
                    "read": [String: Any]()
                ]
            ]
        ]

        // Add clearAllCookies flag if the switch is on
        if clearCookiesSwitch.isOn {
            requestBody["clearAllCookies"] = true
        }

        // 🔑 Add record mode flag if the switch is on
        if recordModeSwitch.isOn {
            requestBody["record"] = true
        }

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
                self?.exitCallCount += 1
                print("\n🚪 EXIT CALLBACK TRIGGERED #\(self?.exitCallCount ?? 0) - Reason: \(reason ?? "unknown")")
                print("Total exit callbacks received: \(self?.exitCallCount ?? 0)")
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
                print("\n✅ OPEN CONNECTION COMPLETE CALLBACK TRIGGERED")
                print("OPEN Connection complete data: \(data)")
                self?.handleSuccess(data)
            },
            onConnectionError: { [weak self] (error: PassageErrorData) in
                print("\n❌ CONNECTION ERROR CALLBACK TRIGGERED")
                self?.handleError(error)
            },
            onDataComplete: { [weak self] (data: PassageDataResult) in
                print("\n📊 OPDATA COMPLETE CALLBACK TRIGGERED")
                self?.handleDataComplete(data)
            },
            onPromptComplete: { [weak self] (prompt: PassagePromptResponse) in
                print("\n🎯 PROMPT COMPLETE CALLBACK TRIGGERED")
                self?.handlePromptComplete(prompt)
            },
            onExit: { [weak self] (reason: String?) in
                self?.exitCallCount += 1
                print("\n🚪 EXIT CALLBACK TRIGGERED #\(self?.exitCallCount ?? 0) - Reason: \(reason ?? "unknown")")
                print("Total exit callbacks received: \(self?.exitCallCount ?? 0)")
                self?.handleClose()
            },
            onWebviewChange: { [weak self] (webviewType: String) in
                print("\n🔄 WEBVIEW CHANGE CALLBACK TRIGGERED - Type: \(webviewType)")
                self?.handleWebviewChange(webviewType)
            },
            // 🔑 Add margin at bottom if record mode is active (for record indicator)
            marginBottom: isRecordModeActive ? 240 : nil
        )

        print("Passage.shared.open called, waiting for callbacks...")
    }

    private func handleSuccess(_ data: PassageSuccessData) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let isManualMode = self.modeSegmentedControl.selectedSegmentIndex == 1

            if isManualMode {
                self.updateButtonStates()
            } else {
                self.connectButton.isEnabled = true
                self.connectButton.setTitle("Connect", for: .normal)
                self.connectButton.backgroundColor = .systemBlue
            }

            self.displayResult(data, isError: false)
        }
    }

    private func handleError(_ error: PassageErrorData) {
        print("Error details:")
        print("  - Error message: \(error.error)")
        print("  - Error data: \(String(describing: error.data))")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let isManualMode = self.modeSegmentedControl.selectedSegmentIndex == 1

            if isManualMode {
                self.updateButtonStates()
            } else {
                self.connectButton.isEnabled = true
                self.connectButton.setTitle("Connect", for: .normal)
                self.connectButton.backgroundColor = .systemBlue
            }

            self.displayResult(error, isError: true)
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

                // 🔑 Show record mode bottom sheet when automation webview is visible
                if self?.isRecordModeActive == true {
                    self?.showRecordModeBottomSheet()
                }
            } else {
                self?.connectButton.setTitle("Opening Passage...", for: .normal)

                // 🔑 Hide record mode indicator when switching to UI webview
                self?.hideRecordModeBottomSheet()
            }
        }
    }

    private func handleClose() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 🔑 Hide record mode bottom sheet on close
            self.hideRecordModeBottomSheet()

            let isManualMode = self.modeSegmentedControl.selectedSegmentIndex == 1

            if isManualMode {
                self.updateButtonStates()
            } else {
                self.connectButton.isEnabled = true
                self.connectButton.setTitle("Connect", for: .normal)
                self.connectButton.backgroundColor = .systemBlue
            }

            if self.resultTextView.text == "Opening Passage..." ||
               self.resultTextView.text?.contains("Automation Active") == true ||
               self.resultTextView.text?.contains("Opening Passage with initialized SDK") == true {
                self.resultTextView.text = "Passage closed\n\nTotal onExit callbacks received: \(self.exitCallCount)"
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
                var historyArray: [Any] = []

                for item in data.history {
                    historyArray.append(item)
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

                            if let itemDict = item as? [String: Any],
                               let title = itemDict["title"] as? String {
                                resultText += "\(index + 1). \(title)\n"
                            } else {
                                resultText += "\(index + 1). \(item)\n"
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

// MARK: - UITextViewDelegate
extension ViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        if textView == tokenTextView {
            // Update placeholder visibility
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = !textView.text.isEmpty
            }
            
            // Update button states
            updateButtonStates()
        }
    }
    
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView == tokenTextView {
            // Hide placeholder when editing begins
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = true
            }
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView == tokenTextView {
            // Show placeholder if text is empty
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = !textView.text.isEmpty
            }
        }
    }
}

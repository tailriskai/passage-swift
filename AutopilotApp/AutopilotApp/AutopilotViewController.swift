import UIKit
import PassageSDK

class AutopilotViewController: UIViewController {

    // MARK: - UI Components

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Autopilot Test App"
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Opens Passage SDK in autopilot mode"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let intentTokenField: UITextField = {
        let field = UITextField()
        field.placeholder = "Intent Token (optional for testing)"
        field.borderStyle = .roundedRect
        field.font = UIFont.systemFont(ofSize: 16)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let openButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Open Passage SDK", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Ready"
        label.font = UIFont.systemFont(ofSize: 16)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let infoLabel: UILabel = {
        let label = UILabel()
        label.text = """
        The SDK handles:
        • WebSocket connection
        • Command execution
        • State tracking (cookies, localStorage)
        • Screenshot capture
        • All autopilot functionality
        """
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .tertiaryLabel
        label.textAlignment = .left
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Autopilot"
        view.backgroundColor = .systemBackground

        setupUI()

        print("[Autopilot] View loaded - SDK already configured")
        updateStatus("Ready - SDK configured for autopilot mode")
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(intentTokenField)
        view.addSubview(openButton)
        view.addSubview(statusLabel)
        view.addSubview(infoLabel)

        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Intent Token Field
            intentTokenField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 40),
            intentTokenField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            intentTokenField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            intentTokenField.heightAnchor.constraint(equalToConstant: 44),

            // Open Button
            openButton.topAnchor.constraint(equalTo: intentTokenField.bottomAnchor, constant: 20),
            openButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            openButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            openButton.heightAnchor.constraint(equalToConstant: 56),

            // Status Label
            statusLabel.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Info Label
            infoLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 40),
            infoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        openButton.addTarget(self, action: #selector(openPassageSDK), for: .touchUpInside)

        // Add tap gesture to dismiss keyboard
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - Actions

    @objc private func openPassageSDK() {
        print("[Autopilot] Opening Passage SDK")
        updateStatus("Opening SDK...")

        // Get intent token from text field, or use nil for demo mode
        let intentToken = intentTokenField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = (intentToken?.isEmpty == false) ? intentToken : nil

        if token == nil {
            updateStatus("⚠️ No intent token provided - SDK may not open without a valid token from backend")
        }

        // Open Passage SDK - it handles all WebSocket communication,
        // command execution, and state tracking automatically
        let options = PassageOpenOptions(
            intentToken: token,
            onConnectionComplete: { [weak self] data in
                print("[Autopilot] ✅ Connection complete")
                print("[Autopilot] Connection ID: \(data.connectionId)")
                print("[Autopilot] History items: \(data.history.count)")
                self?.updateStatus("✅ Connected: \(data.connectionId)")
            },
            onConnectionError: { [weak self] error in
                print("[Autopilot] ❌ Connection error: \(error.error)")
                self?.updateStatus("❌ Error: \(error.error)")
            },
            onDataComplete: { [weak self] result in
                print("[Autopilot] 📦 Data extraction complete")
                if let data = result.data {
                    print("[Autopilot] Data: \(data)")
                }
                self?.updateStatus("📦 Data extraction complete")
            },
            onExit: { [weak self] reason in
                print("[Autopilot] 👋 SDK closed: \(reason ?? "user action")")
                self?.updateStatus("SDK closed: \(reason ?? "user action")")
            },
            onWebviewChange: { [weak self] webviewType in
                print("[Autopilot] 🔄 WebView changed: \(webviewType)")
                self?.updateStatus("WebView: \(webviewType)")
            }
        )

        // The SDK's RemoteControlManager will:
        // 1. Connect to WebSocket automatically
        // 2. Listen for commands from backend
        // 3. Execute commands (navigate, click, input, etc.)
        // 4. Capture state (cookies, localStorage, HTML, screenshots)
        // 5. Send state updates back to backend
        Passage.shared.open(options)
    }

    // MARK: - Helpers

    private func updateStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = message
        }
    }
}

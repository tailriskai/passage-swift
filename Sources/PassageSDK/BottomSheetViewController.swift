#if canImport(UIKit)
import UIKit

class BottomSheetViewController: UIViewController, UIAdaptivePresentationControllerDelegate, UITextFieldDelegate {

    private var titleText: String
    private var descriptionText: String?
    private var bulletPoints: [String]?
    private var closeButtonText: String?
    private var showInput: Bool
    private var onSubmit: ((String) -> Void)?

    // Constraint references for updates
    private var contentStackBottomConstraint: NSLayoutConstraint?
    private var buttonConstraints: [NSLayoutConstraint] = []
    private var inputFieldHeightConstraint: NSLayoutConstraint?

    // Element heights (for reference, not used in calculation)
    private let inputFieldHeight: CGFloat = 44
    private let buttonHeight: CGFloat = 50
    private let topPadding: CGFloat = 24
    private let bottomPadding: CGFloat = 12
    private let buttonSpacing: CGFloat = 24

    private var hasConfiguredSheetDetent = false
    private var currentDetentHeight: CGFloat = 0

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = false
        return scrollView
    }()

    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        label.textColor = .label
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        label.textColor = .label
        label.numberOfLines = 0
        label.textAlignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var bulletPointsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var urlTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "https://google.com"
        textField.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .URL
        textField.returnKeyType = .go
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(urlTextFieldChanged), for: .editingChanged)
        textField.delegate = self
        // Prevent text field from expanding vertically
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        return textField
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        return button
    }()

    init(title: String?, description: String?, points: [String]?, closeButtonText: String?, showInput: Bool = false, onSubmit: ((String) -> Void)? = nil) {
        self.titleText = title ?? ""
        self.descriptionText = description
        self.bulletPoints = points
        self.closeButtonText = closeButtonText ?? (showInput ? "Submit" : nil)
        self.showInput = showInput
        self.onSubmit = onSubmit
        super.init(nibName: nil, bundle: nil)

        passageLogger.debug("[BOTTOM SHEET INIT] showInput: \(showInput)")
        passageLogger.debug("[BOTTOM SHEET INIT] closeButtonText: \(String(describing: self.closeButtonText))")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        presentationController?.delegate = self
        setupUI()
    }

    deinit {
        // Clean up if needed
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        return true
    }

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(containerView)
        containerView.addSubview(contentStackView)

        if !titleText.isEmpty {
            titleLabel.text = titleText
            contentStackView.addArrangedSubview(titleLabel)
            // Reduce spacing after title
            contentStackView.setCustomSpacing(8, after: titleLabel)
        }

        if let description = descriptionText, !description.isEmpty {
            descriptionLabel.text = description
            contentStackView.addArrangedSubview(descriptionLabel)
            // Increase spacing before input field
            if showInput {
                contentStackView.setCustomSpacing(20, after: descriptionLabel)
            } else {
                contentStackView.setCustomSpacing(16, after: descriptionLabel)
            }
        }

        if let points = bulletPoints, !points.isEmpty {
            for point in points {
                let bulletLabel = createBulletLabel(text: point)
                bulletPointsStackView.addArrangedSubview(bulletLabel)
            }
            contentStackView.addArrangedSubview(bulletPointsStackView)
            // Increase spacing before input field if present
            if showInput {
                contentStackView.setCustomSpacing(20, after: bulletPointsStackView)
            }
        }

        if showInput {
            passageLogger.debug("[BOTTOM SHEET SETUP] Adding input field to initial setup")
            contentStackView.addArrangedSubview(urlTextField)
        } else {
            passageLogger.debug("[BOTTOM SHEET SETUP] showInput is false, NOT adding input field")
        }

        var constraints = [
            // Scroll view constraints to view
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Container view constraints to scroll view
            containerView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            containerView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Content stack view constraints to container
            contentStackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: topPadding),
            contentStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            contentStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        ]

        if let buttonText = closeButtonText, !buttonText.isEmpty {
            closeButton.setTitle(buttonText, for: .normal)
            if showInput {
                closeButton.isEnabled = false
                closeButton.alpha = 0.5
            }
            containerView.addSubview(closeButton)

            let stackToButtonConstraint = contentStackView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -buttonSpacing)
            contentStackBottomConstraint = stackToButtonConstraint

            let newButtonConstraints = [
                stackToButtonConstraint,
                closeButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
                closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
                closeButton.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -bottomPadding),
                closeButton.heightAnchor.constraint(equalToConstant: buttonHeight)
            ]
            buttonConstraints = newButtonConstraints
            constraints.append(contentsOf: newButtonConstraints)
        } else {
            let stackToBottomConstraint = contentStackView.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -bottomPadding)
            contentStackBottomConstraint = stackToBottomConstraint
            constraints.append(stackToBottomConstraint)
        }

        if showInput {
            let heightConstraint = urlTextField.heightAnchor.constraint(equalToConstant: inputFieldHeight)
            inputFieldHeightConstraint = heightConstraint
            constraints.append(heightConstraint)
        }

        NSLayoutConstraint.activate(constraints)
    }

    @objc private func closeButtonTapped() {
        if showInput, let url = urlTextField.text, isValidURL(url) {
            passageLogger.debug("[BOTTOM SHEET] Submit button tapped with valid URL: \(url)")
            onSubmit?(url)
            dismiss(animated: true, completion: nil)
        } else if !showInput {
            passageLogger.debug("[BOTTOM SHEET] Close button tapped")
            dismiss(animated: true, completion: nil)
        }
    }

    @objc private func urlTextFieldChanged() {
        guard showInput else { return }

        if let text = urlTextField.text, isValidURL(text) {
            closeButton.isEnabled = true
            closeButton.alpha = 1.0
        } else {
            closeButton.isEnabled = false
            closeButton.alpha = 0.5
        }
    }

    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return (url.scheme == "http" || url.scheme == "https") && url.host != nil
    }

    func updateContent(title: String?, description: String?, points: [String]?, closeButtonText: String?, showInput: Bool = false, onSubmit: ((String) -> Void)? = nil) {
        passageLogger.debug("[BOTTOM SHEET] Updating content with new title: \(title ?? "nil")")

        self.titleText = title ?? ""
        self.descriptionText = description
        self.bulletPoints = points
        self.closeButtonText = closeButtonText ?? (showInput ? "Submit" : nil)
        self.showInput = showInput
        if let onSubmit = onSubmit {
            self.onSubmit = onSubmit
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Clear existing content
            self.contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

            // Add title if not empty
            if !self.titleText.isEmpty {
                self.titleLabel.text = self.titleText
                self.contentStackView.addArrangedSubview(self.titleLabel)
                // Reduce spacing after title
                self.contentStackView.setCustomSpacing(8, after: self.titleLabel)
            }

            // Add description if present
            if let description = description, !description.isEmpty {
                self.descriptionLabel.text = description
                self.contentStackView.addArrangedSubview(self.descriptionLabel)
                // Increase spacing before input field
                if self.showInput {
                    self.contentStackView.setCustomSpacing(20, after: self.descriptionLabel)
                } else {
                    self.contentStackView.setCustomSpacing(16, after: self.descriptionLabel)
                }
            }

            // Add bullet points if present
            if let points = points, !points.isEmpty {
                self.bulletPointsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
                for point in points {
                    let bulletLabel = self.createBulletLabel(text: point)
                    self.bulletPointsStackView.addArrangedSubview(bulletLabel)
                }
                self.contentStackView.addArrangedSubview(self.bulletPointsStackView)
                // Increase spacing before input field if present
                if self.showInput {
                    self.contentStackView.setCustomSpacing(20, after: self.bulletPointsStackView)
                }
            }

            // Add input field if needed
            if self.showInput {
                passageLogger.debug("[BOTTOM SHEET] Adding input field to content stack")
                self.contentStackView.addArrangedSubview(self.urlTextField)

                // Reset text field
                self.urlTextField.text = ""
                self.urlTextFieldChanged() // Update button state
            }

            // Deactivate existing constraints
            if let existingBottomConstraint = self.contentStackBottomConstraint {
                existingBottomConstraint.isActive = false
            }
            NSLayoutConstraint.deactivate(self.buttonConstraints)
            self.buttonConstraints.removeAll()

            if let existingHeightConstraint = self.inputFieldHeightConstraint {
                existingHeightConstraint.isActive = false
                self.inputFieldHeightConstraint = nil
            }

            // Remove button from superview to clean up
            self.closeButton.removeFromSuperview()

            // Update button
            if let buttonText = self.closeButtonText, !buttonText.isEmpty {
                passageLogger.debug("[BOTTOM SHEET] Setting up button with text: \(buttonText)")
                self.closeButton.setTitle(buttonText, for: .normal)

                // Update button state for input mode
                if self.showInput {
                    self.closeButton.isEnabled = false
                    self.closeButton.alpha = 0.5
                } else {
                    self.closeButton.isEnabled = true
                    self.closeButton.alpha = 1.0
                }

                // Add button and set up constraints
                self.containerView.addSubview(self.closeButton)
                self.closeButton.isHidden = false

                // Set up constraints for button
                let stackToButtonConstraint = self.contentStackView.bottomAnchor.constraint(equalTo: self.closeButton.topAnchor, constant: -self.buttonSpacing)
                self.contentStackBottomConstraint = stackToButtonConstraint

                let newButtonConstraints = [
                    stackToButtonConstraint,
                    self.closeButton.leadingAnchor.constraint(equalTo: self.containerView.leadingAnchor, constant: 16),
                    self.closeButton.trailingAnchor.constraint(equalTo: self.containerView.trailingAnchor, constant: -16),
                    self.closeButton.bottomAnchor.constraint(equalTo: self.containerView.safeAreaLayoutGuide.bottomAnchor, constant: -self.bottomPadding),
                    self.closeButton.heightAnchor.constraint(equalToConstant: self.buttonHeight)
                ]
                self.buttonConstraints = newButtonConstraints
                NSLayoutConstraint.activate(newButtonConstraints)

                // Set up input field height constraint if needed
                if self.showInput {
                    let heightConstraint = self.urlTextField.heightAnchor.constraint(equalToConstant: self.inputFieldHeight)
                    self.inputFieldHeightConstraint = heightConstraint
                    heightConstraint.isActive = true
                }

                passageLogger.debug("[BOTTOM SHEET] Button and constraints activated")
            } else {
                passageLogger.debug("[BOTTOM SHEET] No button text, hiding button")
                self.closeButton.isHidden = true

                // Ensure content stack goes to bottom if no button
                let stackToBottomConstraint = self.contentStackView.bottomAnchor.constraint(equalTo: self.containerView.safeAreaLayoutGuide.bottomAnchor, constant: -self.bottomPadding)
                self.contentStackBottomConstraint = stackToBottomConstraint
                stackToBottomConstraint.isActive = true
            }

            self.view.layoutIfNeeded()
            self.scrollView.layoutIfNeeded()
            self.configureSheetIfNeeded(force: true)
        }
    }

    private func createBulletLabel(text: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let bulletLabel = UILabel()
        bulletLabel.text = "•"
        bulletLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        bulletLabel.textColor = .label
        bulletLabel.translatesAutoresizingMaskIntoConstraints = false

        let textLabel = UILabel()
        textLabel.text = text
        textLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        textLabel.textColor = .label
        textLabel.numberOfLines = 0
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(bulletLabel)
        container.addSubview(textLabel)

        NSLayoutConstraint.activate([
            bulletLabel.topAnchor.constraint(equalTo: container.topAnchor),
            bulletLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bulletLabel.widthAnchor.constraint(equalToConstant: 20),

            textLabel.topAnchor.constraint(equalTo: container.topAnchor),
            textLabel.leadingAnchor.constraint(equalTo: bulletLabel.trailingAnchor, constant: 4),
            textLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    private func configureSheetIfNeeded(force: Bool = false) {
        guard #available(iOS 15.0, *) else { return }
        guard let sheet = sheetPresentationController else {
            passageLogger.warn("[BOTTOM SHEET] No sheet presentation controller")
            return
        }

        let availableWidth = view.bounds.width
        guard availableWidth > 0 else { return }

        let preferredHeight = calculatePreferredHeight(for: availableWidth)

        if !force, hasConfiguredSheetDetent, abs(preferredHeight - currentDetentHeight) < 1 {
            return
        }

        currentDetentHeight = preferredHeight
        hasConfiguredSheetDetent = true

        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.preferredCornerRadius = 16
        sheet.largestUndimmedDetentIdentifier = nil

        // Enable proper keyboard avoidance
        if #available(iOS 16.0, *) {
            sheet.prefersEdgeAttachedInCompactHeight = true
        }

        if #available(iOS 16.0, *) {
            let identifier = UISheetPresentationController.Detent.Identifier("passage.compact.bottomsheet")
            let customDetent = UISheetPresentationController.Detent.custom(identifier: identifier) { context in
                min(preferredHeight, context.maximumDetentValue)
            }
            sheet.detents = [customDetent]
            sheet.selectedDetentIdentifier = identifier
        } else {
            preferredContentSize = CGSize(width: availableWidth, height: preferredHeight)
            sheet.detents = [.medium()]
        }
    }

    private func calculatePreferredHeight(for width: CGFloat) -> CGFloat {
        view.layoutIfNeeded()

        let horizontalPadding: CGFloat = 32 // 16 leading + 16 trailing
        let targetWidth = max(width - horizontalPadding, 0)
        let fittingSize = CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)

        let stackHeight = contentStackView.systemLayoutSizeFitting(
            fittingSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        var totalHeight = topPadding + stackHeight

        if let buttonText = closeButtonText, !buttonText.isEmpty {
            totalHeight += buttonSpacing + buttonHeight + bottomPadding
        } else {
            totalHeight += bottomPadding
        }

        return totalHeight
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        configureSheetIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Pre-calculate size before appearing
        view.layoutIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Sheet height is already set, no need to update
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if showInput, let url = textField.text, isValidURL(url) {
            closeButtonTapped()
        }
        return true
    }
}
#endif

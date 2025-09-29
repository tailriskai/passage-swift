#if canImport(UIKit)
import UIKit

class BottomSheetViewController: UIViewController, UIAdaptivePresentationControllerDelegate {

    private var titleText: String
    private var descriptionText: String?
    private var bulletPoints: [String]?
    private var closeButtonText: String?

    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 25, weight: .bold)
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

    init(title: String, description: String?, points: [String]?, closeButtonText: String?) {
        self.titleText = title
        self.descriptionText = description
        self.bulletPoints = points
        self.closeButtonText = closeButtonText
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        presentationController?.delegate = self
        setupUI()
        configureSheet()
    }

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        return true
    }

    private func setupUI() {
        view.addSubview(containerView)
        containerView.addSubview(contentStackView)

        titleLabel.text = titleText
        contentStackView.addArrangedSubview(titleLabel)

        if let description = descriptionText, !description.isEmpty {
            descriptionLabel.text = description
            contentStackView.addArrangedSubview(descriptionLabel)
            contentStackView.setCustomSpacing(16, after: descriptionLabel)
        }

        if let points = bulletPoints, !points.isEmpty {
            for point in points {
                let bulletLabel = createBulletLabel(text: point)
                bulletPointsStackView.addArrangedSubview(bulletLabel)
            }
            contentStackView.addArrangedSubview(bulletPointsStackView)
        }

        var constraints = [
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            contentStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            contentStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16)
        ]

        if let buttonText = closeButtonText, !buttonText.isEmpty {
            closeButton.setTitle(buttonText, for: .normal)
            containerView.addSubview(closeButton)

            constraints.append(contentsOf: [
                contentStackView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -24),
                closeButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
                closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
                closeButton.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -12),
                closeButton.heightAnchor.constraint(equalToConstant: 50)
            ])
        } else {
            constraints.append(
                contentStackView.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -12)
            )
        }

        NSLayoutConstraint.activate(constraints)
    }

    @objc private func closeButtonTapped() {
        passageLogger.info("[BOTTOM SHEET] Close button tapped")
        dismiss(animated: true, completion: nil)
    }

    func updateContent(title: String, description: String?, points: [String]?, closeButtonText: String?) {
        passageLogger.info("[BOTTOM SHEET] Updating content with new title: \(title)")

        self.titleText = title
        self.descriptionText = description
        self.bulletPoints = points
        self.closeButtonText = closeButtonText

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.titleLabel.text = title

            self.contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

            self.contentStackView.addArrangedSubview(self.titleLabel)

            if let description = description, !description.isEmpty {
                self.descriptionLabel.text = description
                self.contentStackView.addArrangedSubview(self.descriptionLabel)
                self.contentStackView.setCustomSpacing(16, after: self.descriptionLabel)
            }

            if let points = points, !points.isEmpty {
                self.bulletPointsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
                for point in points {
                    let bulletLabel = self.createBulletLabel(text: point)
                    self.bulletPointsStackView.addArrangedSubview(bulletLabel)
                }
                self.contentStackView.addArrangedSubview(self.bulletPointsStackView)
            }

            if let buttonText = closeButtonText, !buttonText.isEmpty {
                self.closeButton.setTitle(buttonText, for: .normal)
                if self.closeButton.superview == nil {
                    self.containerView.addSubview(self.closeButton)
                    self.closeButton.isHidden = false
                }
            } else {
                self.closeButton.isHidden = true
            }

            self.view.layoutIfNeeded()
            self.updateSheetHeight()
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

    private func configureSheet() {
        if #available(iOS 15.0, *) {
            if let sheet = sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                sheet.preferredCornerRadius = 16
            }
        }
    }

    private func updateSheetHeight() {
        if #available(iOS 15.0, *) {
            guard let sheet = sheetPresentationController else { return }
            guard let window = view.window else { return }

            let screenHeight = window.screen.bounds.height
            let maxHeight = screenHeight * 0.7

            view.layoutIfNeeded()

            let contentWidth = view.bounds.width - 32
            let contentHeight = contentStackView.systemLayoutSizeFitting(
                CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height

            let topPadding: CGFloat = 12
            let bottomPadding: CGFloat = (closeButtonText != nil && !closeButtonText!.isEmpty) ? 12 : 12
            let buttonHeight: CGFloat = (closeButtonText != nil && !closeButtonText!.isEmpty) ? 50 : 0
            let buttonSpacing: CGFloat = buttonHeight > 0 ? 24 : 0
            let externalBottomMargin: CGFloat = 24

            let totalHeight = topPadding + contentHeight + bottomPadding + buttonHeight + buttonSpacing + view.safeAreaInsets.bottom + externalBottomMargin

            if totalHeight < maxHeight {
                if #available(iOS 16.0, *) {
                    let customDetent = UISheetPresentationController.Detent.custom { context in
                        return totalHeight
                    }
                    sheet.detents = [customDetent]
                    sheet.selectedDetentIdentifier = customDetent.identifier
                } else {
                    sheet.detents = [.medium()]
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateSheetHeight()
    }
}
#endif
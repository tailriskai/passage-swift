//
//  RecordModeBottomSheet.swift
//  PassageExample
//
//  Created for record mode UI
//

import UIKit
import PassageSDK

class RecordModeBottomSheet: UIViewController {

    // MARK: - Properties

    private var containerView: UIView!
    private var headerView: UIView!
    private var stepLabel: UILabel!
    private var captureButton: UIButton!
    private var confirmButton: UIButton!

    private var isCapturingData = false
    private var currentStep = "Perform action in the app"

    // Callback for when recording is completed
    var onRecordingComplete: (() -> Void)?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .clear

        // Container view with white background
        containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 20
        containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: -2)
        containerView.layer.shadowOpacity = 0.1
        containerView.layer.shadowRadius = 10
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // Header view with step label
        headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(headerView)

        // Step label
        stepLabel = UILabel()
        stepLabel.text = currentStep
        stepLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        stepLabel.textColor = .label
        stepLabel.textAlignment = .center
        stepLabel.numberOfLines = 2
        stepLabel.lineBreakMode = .byWordWrapping
        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(stepLabel)

        // Capture Data button
        captureButton = UIButton(type: .system)
        captureButton.setTitle("Capture Data", for: .normal)
        captureButton.setTitleColor(.white, for: .normal)
        captureButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        captureButton.backgroundColor = .systemGreen
        captureButton.layer.cornerRadius = 12
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        containerView.addSubview(captureButton)

        // Confirm Completed button
        confirmButton = UIButton(type: .system)
        confirmButton.setTitle("Confirm completed", for: .normal)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        confirmButton.backgroundColor = .systemBlue
        confirmButton.layer.cornerRadius = 12
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(self, action: #selector(confirmButtonTapped), for: .touchUpInside)
        containerView.addSubview(confirmButton)

        // Layout constraints
        NSLayoutConstraint.activate([
            // Container view
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 240),

            // Header view
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            headerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            // Step label
            stepLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            stepLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            stepLabel.topAnchor.constraint(equalTo: headerView.topAnchor),
            stepLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            // Capture button
            captureButton.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 20),
            captureButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            captureButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            captureButton.heightAnchor.constraint(equalToConstant: 50),

            // Confirm button
            confirmButton.topAnchor.constraint(equalTo: captureButton.bottomAnchor, constant: 10),
            confirmButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            confirmButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            confirmButton.heightAnchor.constraint(equalToConstant: 50),
            confirmButton.bottomAnchor.constraint(lessThanOrEqualTo: containerView.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    // MARK: - Button Actions

    @objc private func captureButtonTapped() {
        guard !isCapturingData else {
            print("[RecordMode] Already capturing data, ignoring")
            return
        }

        print("[RecordMode] Capture Data button tapped")
        isCapturingData = true

        // Update button state
        captureButton.setTitle("Capturing...", for: .normal)
        captureButton.backgroundColor = .systemGray
        captureButton.isEnabled = false

        // Call captureRecordingData
        Task {
            do {
                let data: [String: Any] = [
                    "currentStep": currentStep,
                    "timestamp": Date().timeIntervalSince1970
                ]

                print("[RecordMode] Calling captureRecordingData with data: \(data)")
                try await Passage.shared.captureRecordingData(data: data)
                print("[RecordMode] Recording data captured successfully")

                // Reset button state after 1 second
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.isCapturingData = false
                    self?.captureButton.setTitle("Capture Data", for: .normal)
                    self?.captureButton.backgroundColor = .systemGreen
                    self?.captureButton.isEnabled = true
                }
            } catch {
                print("[RecordMode] Failed to capture recording data: \(error)")

                // Reset button state
                DispatchQueue.main.async { [weak self] in
                    self?.isCapturingData = false
                    self?.captureButton.setTitle("Capture Data", for: .normal)
                    self?.captureButton.backgroundColor = .systemGreen
                    self?.captureButton.isEnabled = true
                }
            }
        }
    }

    @objc private func confirmButtonTapped() {
        print("[RecordMode] Confirm completed button tapped")

        // Show confirmation alert
        let alert = UIAlertController(
            title: "Sure you've completed this step?",
            message: currentStep,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        alert.addAction(UIAlertAction(title: "Confirm", style: .default) { [weak self] _ in
            self?.completeRecording()
        })

        present(alert, animated: true)
    }

    private func completeRecording() {
        print("[RecordMode] Completing recording")

        // Call completeRecording
        Task {
            do {
                let data: [String: Any] = [
                    "stepsCompleted": true,
                    "processComplete": true,
                    "timestamp": Date().timeIntervalSince1970
                ]

                print("[RecordMode] Calling completeRecording with data: \(data)")
                try await Passage.shared.completeRecording(data: data)
                print("[RecordMode] Recording completed successfully")

                // Notify parent that recording is complete
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingComplete?()
                    self?.dismiss(animated: true)
                }
            } catch {
                print("[RecordMode] Failed to complete recording: \(error)")
            }
        }
    }

    // MARK: - Public Methods

    func updateStep(_ step: String) {
        currentStep = step
        stepLabel.text = step
    }
}

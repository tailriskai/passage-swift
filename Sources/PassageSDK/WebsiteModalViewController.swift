import Foundation
import SwiftUI
import WebKit

#if canImport(UIKit)
import UIKit

/// SwiftUI view that displays a website in a WKWebView
@available(iOS 16.0, *)
struct WebsiteModalView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: WebsiteModalViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // WebView with top padding for header
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: geometry.safeAreaInsets.top + 57)

                    WebViewRepresentable(url: url, viewModel: viewModel)
                }
                .ignoresSafeArea(.all)

                // Loading indicator
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.1))
                }

                // Error view
                if let error = viewModel.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)

                        Text("Failed to load website")
                            .font(.headline)

                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Dismiss") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemBackground))
                }

                // Custom header with close button (matching WebViewModalViewController style)
                VStack(spacing: 0) {
                    // Header container
                    HStack {
                        Spacer()

                        // Close button
                        Button(action: {
                            dismiss()
                        }) {
                            Text("×")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(.black)
                                .frame(width: 48, height: 48)
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 4)
                    }
                    .frame(height: 57)
                    .background(Color.white)
                    .overlay(
                        // Bottom border
                        Rectangle()
                            .fill(Color(UIColor.systemGray4))
                            .frame(height: 1.0 / UIScreen.main.scale),
                        alignment: .bottom
                    )

                    Spacer()
                }
            }
        }
    }
}

/// ViewModel for the website modal view
@available(iOS 16.0, *)
class WebsiteModalViewModel: ObservableObject {
    @Published var isLoading = true {
        didSet {
            passageLogger.info("[WEBSITE_MODAL] ViewModel isLoading changed: \(oldValue) -> \(isLoading)")
        }
    }
    @Published var error: String?
    @Published var canGoBack = false

    weak var webView: WKWebView?

    init() {
        passageLogger.info("[WEBSITE_MODAL] ViewModel initialized with isLoading = \(isLoading)")
    }

    func goBack() {
        webView?.goBack()
    }

    func updateCanGoBack() {
        canGoBack = webView?.canGoBack ?? false
    }
}

/// UIViewRepresentable wrapper for WKWebView
@available(iOS 16.0, *)
struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    @ObservedObject var viewModel: WebsiteModalViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        passageLogger.info("[WEBSITE_MODAL] makeUIView called for URL: \(url.absoluteString)")
        passageLogger.info("[WEBSITE_MODAL] viewModel.webView status: \(viewModel.webView == nil ? "NIL" : "EXISTS")")

        // Check if we already have a webView (reusing preloaded one)
        if let existingWebView = viewModel.webView {
            passageLogger.info("[WEBSITE_MODAL] 🔄 Reusing existing preloaded webView")
            passageLogger.info("[WEBSITE_MODAL]   - Existing webView.url: \(existingWebView.url?.absoluteString ?? "nil")")
            passageLogger.info("[WEBSITE_MODAL]   - Existing webView.isLoading: \(existingWebView.isLoading)")
            passageLogger.info("[WEBSITE_MODAL]   - ViewModel.isLoading: \(viewModel.isLoading)")

            existingWebView.navigationDelegate = context.coordinator

            // Check if we need to navigate to a different URL
            if let currentURL = existingWebView.url, currentURL.absoluteString != url.absoluteString {
                passageLogger.info("[WEBSITE_MODAL] ⚠️ URL changed from \(currentURL.absoluteString) to \(url.absoluteString), navigating...")
                viewModel.isLoading = true
                let request = URLRequest(url: url)
                existingWebView.load(request)
            } else {
                // Same URL - trust the ViewModel's existing isLoading state from preload
                passageLogger.info("[WEBSITE_MODAL] ✅ Same URL, using preloaded state (isLoading: \(viewModel.isLoading))")
                viewModel.updateCanGoBack()
            }

            return existingWebView
        }

        // Create new webView
        passageLogger.info("[WEBSITE_MODAL] 🆕 Creating new webView (no preload found)")

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true

        // Use default data store to share cookies and state with other webviews
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Store reference to webView in viewModel
        viewModel.webView = webView

        // Load the URL
        let request = URLRequest(url: url)
        webView.load(request)

        passageLogger.info("[WEBSITE_MODAL] ✅ Created new webView and loading URL: \(url.absoluteString)")

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No updates needed
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            passageLogger.info("[WEBSITE_MODAL] 📡 didStartProvisionalNavigation - Setting isLoading = true")
            parent.viewModel.isLoading = true
            parent.viewModel.error = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            passageLogger.info("[WEBSITE_MODAL] ✅ didFinish - Setting isLoading = false")
            passageLogger.info("[WEBSITE_MODAL]   - Final URL: \(webView.url?.absoluteString ?? "nil")")
            parent.viewModel.isLoading = false
            parent.viewModel.updateCanGoBack()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            passageLogger.error("[WEBSITE_MODAL] ❌ didFail - Setting isLoading = false")
            passageLogger.error("[WEBSITE_MODAL]   - Error: \(error.localizedDescription)")
            parent.viewModel.isLoading = false
            parent.viewModel.error = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            passageLogger.error("[WEBSITE_MODAL] ❌ didFailProvisionalNavigation - Setting isLoading = false")
            passageLogger.error("[WEBSITE_MODAL]   - Error: \(error.localizedDescription)")
            parent.viewModel.isLoading = false
            parent.viewModel.error = error.localizedDescription
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Update back button state after navigation
            parent.viewModel.updateCanGoBack()
            decisionHandler(.allow)
        }
    }
}

/// UIViewController that hosts the SwiftUI WebsiteModalView
@available(iOS 16.0, *)
class WebsiteModalViewController: UIViewController {
    private let url: URL
    private let viewModel: WebsiteModalViewModel

    init(url: URL) {
        self.url = url
        self.viewModel = WebsiteModalViewModel()
        super.init(nibName: nil, bundle: nil)
        passageLogger.info("[WEBSITE_MODAL] 🏗️ WebsiteModalViewController initialized for URL: \(url.absoluteString)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Create SwiftUI view with shared viewModel
        let websiteView = WebsiteModalView(url: url, viewModel: viewModel)
        let hostingController = UIHostingController(rootView: websiteView)

        // Add as child view controller
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        // Setup constraints
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        passageLogger.info("[WEBSITE_MODAL] View controller loaded for URL: \(url.absoluteString)")
    }
}

#endif

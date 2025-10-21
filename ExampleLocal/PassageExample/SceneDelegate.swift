import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)
        let viewController = ViewController()
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        // Handle URL if app was launched via deep link
        if let urlContext = connectionOptions.urlContexts.first {
            handleDeepLink(url: urlContext.url)
        }
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleDeepLink(url: url)
    }
    
    private func handleDeepLink(url: URL) {
        // Parse the URL to extract intentToken
        guard url.scheme == "passage-example" else { return }
        
        // Extract intentToken from URL - it could be in query parameters or path
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var intentToken: String?
        
        // First try query parameters
        if let queryToken = components?.queryItems?.first(where: { $0.name == "intentToken" })?.value {
            intentToken = queryToken
        } else {
            // Try path-based format: passage-example://intentToken=...
            let path = url.absoluteString
            if let range = path.range(of: "intentToken=") {
                let tokenStart = range.upperBound
                let tokenString = String(path[tokenStart...])
                intentToken = tokenString
            }
        }
        
        guard let token = intentToken, !token.isEmpty else { return }
        
        // Pass the token to the ViewController
        if let viewController = window?.rootViewController as? ViewController {
            viewController.handleDeepLinkIntentToken(token)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }
}


import UIKit
import PassageSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        print("========== AUTOPILOT APP STARTING ==========")

        // Configure Passage SDK
        // The SDK handles all WebSocket communication, command execution,
        // and state tracking automatically via RemoteControlManager
        let config = PassageConfig(
            uiUrl: "http://localhost:3001",
            apiUrl: "http://localhost:3000",
            socketUrl: "http://localhost:3000",
            debug: true,
            agentName: "passage-autopilot"
        )

        print("Configuring SDK with:")
        print("  - UI URL: \(config.uiUrl)")
        print("  - API URL: \(config.apiUrl)")
        print("  - Socket URL: \(config.socketUrl)")
        print("  - Agent Name: \(config.agentName)")
        print("  - Debug: \(config.debug)")

        // Configure SDK
        Passage.shared.configure(config)

        print("SDK configured successfully")

        // Initialize main window
        window = UIWindow(frame: UIScreen.main.bounds)

        // Create and set root view controller
        let autopilotVC = AutopilotViewController()
        let navController = UINavigationController(rootViewController: autopilotVC)
        window?.rootViewController = navController
        window?.makeKeyAndVisible()

        print("Autopilot app initialized")

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        print("Autopilot app terminating")
        // Clean up WebSocket connections
        NotificationCenter.default.post(name: NSNotification.Name("AppWillTerminate"), object: nil)
    }
}
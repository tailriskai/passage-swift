# Autopilot iOS App Integration Guide

## Current Status

The autopilot Swift files are ready but need to be integrated into an Xcode project.

**Location:** `/Users/mw/passage/core/passage-swift/AutopilotApp/AutopilotApp/`

**Files:**
- ✅ `AutopilotViewController.swift` - Main UI controller
- ✅ `AutopilotWebSocketManager.swift` - WebSocket communication
- ✅ `StateTracker.swift` - Browser state tracking & diff computation
- ✅ `AppDelegate.swift` - App lifecycle

**Missing:**
- ❌ Xcode project (`.xcodeproj`)
- ❌ Info.plist configuration
- ❌ Build settings

---

## Integration Options

### Option 1: Add to Existing PassageExample App (Recommended) ⭐

This is the quickest approach since you already have a working Xcode project.

**Steps:**

1. **Copy files to PassageExample:**
```bash
cd /Users/mw/passage/core/passage-swift

# Copy autopilot Swift files
cp AutopilotApp/AutopilotApp/*.swift ExampleLocal/PassageExample/
```

2. **Add files to Xcode project:**
- Open `ExampleLocal/PassageExample.xcodeproj` in Xcode
- Right-click on `PassageExample` folder
- Select "Add Files to PassageExample"
- Select the copied Swift files
- ✅ Check "Copy items if needed"
- ✅ Check "Add to targets: PassageExample"

3. **Update Podfile:**
```bash
cd ExampleLocal

# Edit Podfile and add Socket.IO
cat >> Podfile << 'EOF'

# Socket.IO for Autopilot WebSocket
pod 'Socket.IO-Client-Swift', '~> 16.0.1'
EOF

# Install
pod install
```

4. **Add UI to launch autopilot:**

Edit `ExampleLocal/PassageExample/ViewController.swift` or create a new tab:

```swift
import UIKit

class MainViewController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Original Passage example
        let passageVC = PassageExampleViewController()
        passageVC.tabBarItem = UITabBarItem(
            title: "Passage",
            image: UIImage(systemName: "arrow.right.circle"),
            tag: 0
        )

        // Autopilot tab
        let autopilotVC = AutopilotViewController()
        autopilotVC.tabBarItem = UITabBarItem(
            title: "Autopilot",
            image: UIImage(systemName: "wand.and.stars"),
            tag: 1
        )

        viewControllers = [passageVC, autopilotVC]
    }
}
```

5. **Update AppDelegate:**
```swift
// In AppDelegate.swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = UINavigationController(rootViewController: MainViewController())
    window?.makeKeyAndVisible()

    return true
}
```

6. **Run the app:**
```bash
cd ExampleLocal
open PassageExample.xcworkspace  # Important: use .xcworkspace, not .xcodeproj
# Cmd+R to run
```

---

### Option 2: Create Standalone Xcode Project

If you want a dedicated autopilot app:

**Steps:**

1. **Create project in Xcode:**
```bash
# Open Xcode
# File > New > Project
# Choose "iOS App"
# Product Name: AutopilotApp
# Interface: Storyboard (or SwiftUI)
# Language: Swift
# Location: /Users/mw/passage/core/passage-swift/AutopilotApp/
```

2. **Add existing Swift files:**
- Drag & drop the `.swift` files from `AutopilotApp/AutopilotApp/` into Xcode
- ✅ "Copy items if needed"
- ✅ "Add to targets: AutopilotApp"

3. **Add dependencies via CocoaPods:**
```bash
cd /Users/mw/passage/core/passage-swift/AutopilotApp

# Update Podfile
cat > Podfile << 'EOF'
platform :ios, '15.0'

target 'AutopilotApp' do
  use_frameworks!

  # Passage SDK
  pod 'PassageSDK', :path => '../'

  # Socket.IO
  pod 'Socket.IO-Client-Swift', '~> 16.0.1'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
EOF

# Install
pod install

# Open workspace
open AutopilotApp.xcworkspace
```

4. **Configure Info.plist:**
Add these keys:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
<key>UIApplicationSceneManifest</key>
<dict>
    <key>UIApplicationSupportsMultipleScenes</key>
    <false/>
</dict>
```

5. **Set AutopilotViewController as root:**
```swift
// In AppDelegate or SceneDelegate
let autopilotVC = AutopilotViewController()
let navController = UINavigationController(rootViewController: autopilotVC)
window?.rootViewController = navController
window?.makeKeyAndVisible()
```

---

### Option 3: Swift Package Manager (No CocoaPods)

Use modern Swift Package Manager instead:

1. **Create Package.swift:**
```bash
cd /Users/mw/passage/core/passage-swift/AutopilotApp

cat > Package.swift << 'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AutopilotApp",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "AutopilotApp",
            targets: ["AutopilotApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/socketio/socket.io-client-swift", from: "16.0.1"),
        .package(path: "../PassageSDK")
    ],
    targets: [
        .target(
            name: "AutopilotApp",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift"),
                "PassageSDK"
            ],
            path: "AutopilotApp"
        )
    ]
)
EOF
```

2. **Create Xcode project from Package:**
```bash
swift package generate-xcodeproj
open AutopilotApp.xcodeproj
```

---

## Recommended Approach ⭐

**Use Option 1** (integrate into PassageExample) because:
- ✅ Fastest to implement
- ✅ Already has PassageSDK configured
- ✅ Can test both regular Passage flow and Autopilot
- ✅ No need to duplicate configuration

**Quick Setup:**
```bash
# 1. Copy files
cd /Users/mw/passage/core/passage-swift
cp AutopilotApp/AutopilotApp/*.swift ExampleLocal/PassageExample/

# 2. Update Podfile
cd ExampleLocal
echo "  pod 'Socket.IO-Client-Swift', '~> 16.0.1'" >> Podfile
pod install

# 3. Open in Xcode
open PassageExample.xcworkspace

# 4. Add files to project (in Xcode):
#    - Select the 4 copied .swift files
#    - Right-click > Add to "PassageExample"

# 5. Run!
```

---

## Testing the Integration

Once integrated, test the autopilot:

1. **Start backend:**
```bash
cd /Users/mw/passage/core/passage-infra/apps/api
pnpm dev
```

2. **Run iOS app:**
- Launch in Xcode (Cmd+R)
- Tap "Connect to Autopilot Service"
- Should connect to `ws://localhost:3000/ws/autopilot`

3. **Verify connection:**
- Check iOS app shows "Connected"
- Check backend logs: `[Autopilot Gateway] Client registered`
- Redis should have: `KEYS autopilot:client:*`

4. **Test command flow:**
- Backend can send commands via `AutopilotGateway.sendCommand()`
- iOS app receives and logs commands
- Can open PassageSDK with intent tokens

---

## Next Steps

After integration:

1. **Add WebView State Capture**
   - Hook into PassageSDK's WebView
   - Capture HTML, cookies, localStorage on each navigation
   - Send updates via WebSocket

2. **Implement Command Execution**
   - Receive click/navigate commands from backend
   - Execute via PassageSDK browser controls
   - Report results

3. **Add Screenshot Capability**
   - Capture WebView screenshots
   - Send to backend for AI analysis

4. **Test End-to-End Flow**
   - Backend triggers autopilot
   - iOS opens URL
   - AI analyzes and sends commands
   - iOS executes commands
   - Data extracted and returned

---

## Need Help?

Check these files for reference:
- Existing example: `/Users/mw/passage/core/passage-swift/ExampleLocal/PassageExample/`
- Autopilot backend: `/Users/mw/passage/core/passage-infra/apps/api/src/autopilot/`
- Setup guide: `/Users/mw/passage/core/passage-infra/AUTOPILOT_SETUP.md`

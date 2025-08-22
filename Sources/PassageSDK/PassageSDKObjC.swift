import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Objective-C compatible wrapper for PassageSDK
/// This helps with CocoaPods distribution and module interface issues
@objc(PSGPassage)
@objcMembers
public class PassageObjC: NSObject {
    
    @objc public static let shared = PassageObjC()
    
    private override init() {
        super.init()
    }
    
    @objc public func configure(baseUrl: String?, socketUrl: String?, debug: Bool) {
        let config = PassageConfig(
            baseUrl: baseUrl,
            socketUrl: socketUrl,
            debug: debug
        )
        Passage.shared.configure(config)
    }
    
    #if canImport(UIKit)
    @objc public func open(
        token: String,
        presentationStyle: String,
        from viewController: UIViewController,
        completion: @escaping (NSError?) -> Void
    ) {
        let style: PassagePresentationStyle = presentationStyle == "fullScreen" ? .fullScreen : .modal
        
        Passage.shared.open(
            token: token,
            presentationStyle: style,
            from: viewController,
            onConnectionComplete: nil,
            onConnectionError: { errorData in
                let nsError = NSError(
                    domain: "PassageSDK",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: errorData.error]
                )
                completion(nsError)
            },
            onDataComplete: nil,
            onPromptComplete: nil,
            onExit: { errorMessage in
                if let errorMessage = errorMessage {
                    let nsError = NSError(
                        domain: "PassageSDK",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: errorMessage]
                    )
                    completion(nsError)
                } else {
                    completion(nil)
                }
            },
            onWebviewChange: nil
        )
    }
    
    @objc public func close() {
        Passage.shared.close()
    }
    #endif
}

/// Make the module properly importable
@_exported import Foundation

#if canImport(UIKit)
import UIKit
@preconcurrency import WebKit

extension WebViewModalViewController {

    struct OptimizedImageData {
        let data: Data
        let base64String: String
        let format: String
        let originalSize: CGSize
        let optimizedSize: CGSize
        let compressionQuality: Double
    }

    func setupScreenshotAccessors() {
        passageLogger.info("[WEBVIEW] ========== SETTING UP SCREENSHOT ACCESSORS ==========")

        guard let remoteControl = remoteControl else {
            passageLogger.error("[WEBVIEW] ❌ No remote control available for screenshot setup")
            return
        }

        passageLogger.info("[WEBVIEW] ✅ Remote control available, configuring screenshot accessors")

        remoteControl.setScreenshotAccessors((
            getCurrentScreenshot: { [weak self] in
                let screenshot = self?.currentScreenshot
                passageLogger.debug("[WEBVIEW ACCESSOR] getCurrentScreenshot called, returning: \(screenshot != nil ? "\(screenshot!.count) chars" : "nil")")
                return screenshot
            },
            getPreviousScreenshot: { [weak self] in
                let screenshot = self?.previousScreenshot
                passageLogger.debug("[WEBVIEW ACCESSOR] getPreviousScreenshot called, returning: \(screenshot != nil ? "\(screenshot!.count) chars" : "nil")")
                return screenshot
            }
        ))

        remoteControl.setCaptureImageFunction({ [weak self] in
            passageLogger.debug("[WEBVIEW ACCESSOR] captureImageFunction called")

            guard let self = self, let remoteControl = self.remoteControl else {
                return nil
            }

            if remoteControl.getRecordFlag() {
                passageLogger.debug("[WEBVIEW ACCESSOR] Record flag is true - capturing whole UI")
                return await self.captureWholeUIScreenshot()
            }
            else if remoteControl.getCaptureScreenshotFlag() {
                passageLogger.debug("[WEBVIEW ACCESSOR] CaptureScreenshot flag is true - capturing automation webview only")
                return await self.captureScreenshot()
            }
            else {
                passageLogger.debug("[WEBVIEW ACCESSOR] No screenshot flags enabled")
                return nil
            }
        })

        passageLogger.info("[WEBVIEW] ✅ Screenshot accessors configured successfully")
    }

    func applyImageOptimization(to image: UIImage) -> OptimizedImageData? {
        guard let remoteControl = remoteControl else {
            passageLogger.error("[IMAGE OPTIMIZATION] No remote control available")
            return nil
        }

        let imageOptParams = remoteControl.getImageOptimizationParameters()

        let quality = (imageOptParams?["quality"] as? Double) ?? 0.6
        let maxWidth = (imageOptParams?["maxWidth"] as? Double) ?? 960.0
        let maxHeight = (imageOptParams?["maxHeight"] as? Double) ?? 540.0
        let format = (imageOptParams?["format"] as? String) ?? "jpeg"

        let originalSize = image.size

        passageLogger.info("[IMAGE OPTIMIZATION] ========== APPLYING IMAGE OPTIMIZATION ==========")
        passageLogger.info("[IMAGE OPTIMIZATION] Source: Configuration (not JWT)")
        passageLogger.info("[IMAGE OPTIMIZATION] Config available: \(imageOptParams != nil)")
        passageLogger.info("[IMAGE OPTIMIZATION] Original size: \(originalSize)")
        passageLogger.info("[IMAGE OPTIMIZATION] Max dimensions: \(maxWidth)x\(maxHeight)")
        passageLogger.info("[IMAGE OPTIMIZATION] Quality: \(quality)")
        passageLogger.info("[IMAGE OPTIMIZATION] Format: \(format)")

        let aspectRatio = originalSize.width / originalSize.height
        var newWidth = originalSize.width
        var newHeight = originalSize.height

        if originalSize.width > maxWidth || originalSize.height > maxHeight {
            if aspectRatio > 1 {
                newWidth = min(originalSize.width, maxWidth)
                newHeight = newWidth / aspectRatio
            } else {
                newHeight = min(originalSize.height, maxHeight)
                newWidth = newHeight * aspectRatio
            }
        }

        let newSize = CGSize(width: newWidth, height: newHeight)
        passageLogger.info("[IMAGE OPTIMIZATION] Optimized size: \(newSize)")

        let resizedImage: UIImage
        if newSize != originalSize {
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
            passageLogger.info("[IMAGE OPTIMIZATION] ✅ Image resized from \(originalSize) to \(newSize)")
        } else {
            resizedImage = image
            passageLogger.info("[IMAGE OPTIMIZATION] ✅ No resizing needed")
        }

        let imageData: Data?
        let mimeType: String

        if format.lowercased() == "jpeg" || format.lowercased() == "jpg" {
            imageData = resizedImage.jpegData(compressionQuality: quality)
            mimeType = "data:image/jpeg;base64,"
            passageLogger.info("[IMAGE OPTIMIZATION] ✅ Converted to JPEG with quality \(quality)")
        } else {
            imageData = resizedImage.pngData()
            mimeType = "data:image/png;base64,"
            passageLogger.info("[IMAGE OPTIMIZATION] ✅ Converted to PNG (quality parameter ignored for PNG)")
        }

        guard let data = imageData else {
            passageLogger.error("[IMAGE OPTIMIZATION] ❌ Failed to convert image to \(format)")
            return nil
        }

        let base64String = mimeType + data.base64EncodedString()

        let optimizedData = OptimizedImageData(
            data: data,
            base64String: base64String,
            format: format,
            originalSize: originalSize,
            optimizedSize: newSize,
            compressionQuality: quality
        )

        passageLogger.info("[IMAGE OPTIMIZATION] ✅ Optimization complete:")
        passageLogger.info("[IMAGE OPTIMIZATION]   Original: \(Int(originalSize.width))x\(Int(originalSize.height))")
        passageLogger.info("[IMAGE OPTIMIZATION]   Optimized: \(Int(newSize.width))x\(Int(newSize.height))")
        passageLogger.info("[IMAGE OPTIMIZATION]   Data size: \(data.count) bytes")
        passageLogger.info("[IMAGE OPTIMIZATION]   Base64 length: \(base64String.count) chars")

        return optimizedData
    }

    func captureScreenshot() async -> String? {
        passageLogger.info("[WEBVIEW SCREENSHOT] ========== CAPTURING SCREENSHOT ==========")

        guard let remoteControl = remoteControl else {
            passageLogger.error("[WEBVIEW SCREENSHOT] ❌ No remote control available")
            return nil
        }

        let captureScreenshotFlag = remoteControl.getCaptureScreenshotFlag()
        passageLogger.info("[WEBVIEW SCREENSHOT] Capture screenshot flag: \(captureScreenshotFlag)")

        guard captureScreenshotFlag else {
            passageLogger.warn("[WEBVIEW SCREENSHOT] ⚠️ Screenshot capture skipped - captureScreenshot flag is false")
            return nil
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    passageLogger.error("[WEBVIEW SCREENSHOT] ❌ Self is nil")
                    continuation.resume(returning: nil)
                    return
                }

                guard let webView = self.automationWebView else {
                    passageLogger.error("[WEBVIEW SCREENSHOT] ❌ Automation webview not available for screenshot capture")
                    passageLogger.error("[WEBVIEW SCREENSHOT] automationWebView: \(self.automationWebView != nil)")
                    passageLogger.error("[WEBVIEW SCREENSHOT] uiWebView: \(self.uiWebView != nil)")
                    continuation.resume(returning: nil)
                    return
                }

                passageLogger.info("[WEBVIEW SCREENSHOT] 📸 Capturing screenshot of automation webview")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView bounds: \(webView.bounds)")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView isHidden: \(webView.isHidden)")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView alpha: \(webView.alpha)")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView URL: \(webView.url?.absoluteString ?? "nil")")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView isLoading: \(webView.isLoading)")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView estimatedProgress: \(webView.estimatedProgress)")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView hasOnlySecureContent: \(webView.hasOnlySecureContent)")

                let originalAlpha = webView.alpha
                let needsVisibility = originalAlpha == 0

                if needsVisibility {
                    passageLogger.debug("[WEBVIEW SCREENSHOT] Temporarily showing webview behind UI webview for snapshot")
                    webView.alpha = 1.0
                    if let uiWebView = self.uiWebView {
                        self.view.sendSubviewToBack(webView)
                        self.view.bringSubviewToFront(uiWebView)
                        passageLogger.debug("[WEBVIEW SCREENSHOT] Automation webview moved behind UI webview")
                    }
                }

                let config = WKSnapshotConfiguration()
                config.rect = webView.bounds
                config.afterScreenUpdates = true

                passageLogger.debug("[WEBVIEW SCREENSHOT] Using WKWebView.takeSnapshot with config - rect: \(config.rect), afterScreenUpdates: \(config.afterScreenUpdates)")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    webView.takeSnapshot(with: config) { [weak self] image, error in
                        if needsVisibility {
                            webView.alpha = originalAlpha
                            passageLogger.debug("[WEBVIEW SCREENSHOT] Restored webview to hidden state (alpha: \(originalAlpha))")
                        }

                    if let error = error {
                        passageLogger.error("[WEBVIEW SCREENSHOT] ❌ WKWebView.takeSnapshot failed: \(error)")
                        passageLogger.error("[WEBVIEW SCREENSHOT] Error details: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                        return
                    }

                    guard let image = image else {
                        passageLogger.error("[WEBVIEW SCREENSHOT] ❌ WKWebView.takeSnapshot returned nil image")
                        continuation.resume(returning: nil)
                        return
                    }

                    passageLogger.info("[WEBVIEW SCREENSHOT] ✅ WKWebView.takeSnapshot succeeded, captured image size: \(image.size)")

                    let optimizedImageData = self?.applyImageOptimization(to: image)

                    guard let optimizedData = optimizedImageData else {
                        passageLogger.error("[WEBVIEW SCREENSHOT] ❌ Failed to apply image optimization")
                        continuation.resume(returning: nil)
                        return
                    }

                    let base64String = optimizedData.base64String

                    self?.previousScreenshot = self?.currentScreenshot
                    self?.currentScreenshot = base64String

                    passageLogger.info("[WEBVIEW SCREENSHOT] ✅ Screenshot captured and optimized successfully:")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Original: \(Int(optimizedData.originalSize.width))x\(Int(optimizedData.originalSize.height))")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Optimized: \(Int(optimizedData.optimizedSize.width))x\(Int(optimizedData.optimizedSize.height))")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Format: \(optimizedData.format)")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Quality: \(optimizedData.compressionQuality)")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Final size: \(base64String.count) chars")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Method: WKWebView.takeSnapshot (proper WebView content capture)")

                        continuation.resume(returning: base64String)
                    }
                }
            }
        }
    }

    func captureWholeUIScreenshot() async -> String? {
        passageLogger.info("[WHOLE UI SCREENSHOT] ========== CAPTURING WHOLE UI SCREENSHOT ==========")

        guard let remoteControl = remoteControl else {
            passageLogger.error("[WHOLE UI SCREENSHOT] ❌ No remote control available")
            return nil
        }

        let recordFlag = remoteControl.getRecordFlag()
        passageLogger.info("[WHOLE UI SCREENSHOT] Record flag: \(recordFlag)")

        guard recordFlag else {
            passageLogger.warn("[WHOLE UI SCREENSHOT] ⚠️ Whole UI screenshot capture skipped - record flag is false")
            return nil
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    passageLogger.error("[WHOLE UI SCREENSHOT] ❌ Self is nil")
                    continuation.resume(returning: nil)
                    return
                }

                guard let view = self.view else {
                    passageLogger.error("[WHOLE UI SCREENSHOT] ❌ View is nil")
                    continuation.resume(returning: nil)
                    return
                }

                passageLogger.info("[WHOLE UI SCREENSHOT] 📸 Capturing screenshot of whole UI view")
                passageLogger.debug("[WHOLE UI SCREENSHOT] View bounds: \(view.bounds)")
                passageLogger.debug("[WHOLE UI SCREENSHOT] View frame: \(view.frame)")
                passageLogger.debug("[WHOLE UI SCREENSHOT] View isHidden: \(view.isHidden)")
                passageLogger.debug("[WHOLE UI SCREENSHOT] View alpha: \(view.alpha)")

                let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
                let image = renderer.image { context in
                    view.layer.render(in: context.cgContext)
                }

                passageLogger.info("[WHOLE UI SCREENSHOT] ✅ Whole UI screenshot captured, image size: \(image.size)")

                let optimizedImageData = self.applyImageOptimization(to: image)

                guard let optimizedData = optimizedImageData else {
                    passageLogger.error("[WHOLE UI SCREENSHOT] ❌ Failed to apply image optimization")
                    continuation.resume(returning: nil)
                    return
                }

                let base64String = optimizedData.base64String

                self.previousScreenshot = self.currentScreenshot
                self.currentScreenshot = base64String

                passageLogger.info("[WHOLE UI SCREENSHOT] ✅ Whole UI screenshot captured and optimized successfully:")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Original: \(Int(optimizedData.originalSize.width))x\(Int(optimizedData.originalSize.height))")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Optimized: \(Int(optimizedData.optimizedSize.width))x\(Int(optimizedData.optimizedSize.height))")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Format: \(optimizedData.format)")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Quality: \(optimizedData.compressionQuality)")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Final size: \(base64String.count) chars")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Method: UIGraphicsImageRenderer (captures whole UI including native elements)")

                continuation.resume(returning: base64String)
            }
        }
    }
}
#endif
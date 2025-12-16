import Foundation

/// Utility for loading environment variables from .env file
class EnvironmentConfig {
    static let shared = EnvironmentConfig()

    private var envVariables: [String: String] = [:]

    private init() {
        loadEnvFile()
    }

    private func loadEnvFile() {
        // Try to find .env file in the bundle
        guard let envPath = Bundle.main.path(forResource: ".env", ofType: nil) else {
            print("⚠️ No .env file found in bundle, using fallback values")
            return
        }

        do {
            let envContent = try String(contentsOfFile: envPath, encoding: .utf8)
            parseEnvContent(envContent)
            print("✅ Loaded .env file from: \(envPath)")
        } catch {
            print("⚠️ Failed to read .env file: \(error)")
        }
    }

    private func parseEnvContent(_ content: String) {
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            // Skip empty lines and comments
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            // Parse KEY=VALUE format
            let parts = trimmedLine.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)

            envVariables[key] = value
        }

        if !envVariables.isEmpty {
            print("📋 Loaded \(envVariables.count) environment variables:")
            for (key, _) in envVariables {
                print("  - \(key)")
            }
        }
    }

    /// Get environment variable with fallback
    func get(_ key: String, fallback: String) -> String {
        if let value = envVariables[key], !value.isEmpty {
            return value
        }
        return fallback
    }

    /// Check if a key exists in environment variables
    func has(_ key: String) -> Bool {
        return envVariables[key] != nil
    }
}

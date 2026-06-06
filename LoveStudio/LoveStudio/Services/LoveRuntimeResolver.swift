import Foundation

enum LoveRuntimeResolver {
    static let bundledRuntimeFolderName = "LoveRuntime"
    static let bundledLoveAppName = "love.app"

    // MARK: macOS

    static func bundledLoveAppURL(in bundle: Bundle = .main) -> URL? {
        // Try Resources/LoveRuntime/love.app first, then Resources/love.app directly
        let candidates: [URL?] = [
            bundle.resourceURL?
                .appendingPathComponent(bundledRuntimeFolderName)
                .appendingPathComponent(bundledLoveAppName),
            bundle.resourceURL?
                .appendingPathComponent(bundledLoveAppName)
        ]
        return candidates.compactMap { $0 }.first { isValidRuntimeApp(at: $0) }
    }

    static func systemLoveAppURL() -> URL? {
        let url = URL(fileURLWithPath: "/Applications/love.app")
        return isValidRuntimeApp(at: url) ? url : nil
    }

    static func resolve(preferredExternalURL: URL?, preferBundled: Bool) -> URL? {
        if preferBundled, let bundled = bundledLoveAppURL() {
            return bundled
        }

        if let preferredExternalURL, isValidRuntimeApp(at: preferredExternalURL) {
            return preferredExternalURL
        }

        if let bundled = bundledLoveAppURL() {
            return bundled
        }

        return systemLoveAppURL()
    }

    static func bundledRuntimeDescription(in bundle: Bundle = .main) -> String {
        if let bundled = bundledLoveAppURL(in: bundle) {
            return bundled.path
        }
        return "Bundled runtime not found in app resources."
    }

    static func executableURL(in loveAppURL: URL) -> URL {
        loveAppURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("love")
    }

    static func isValidRuntimeApp(at url: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return false }
        return fileManager.isExecutableFile(atPath: executableURL(in: url).path)
    }

    // MARK: Android

    static func androidRuntimeURL(in bundle: Bundle = .main) -> URL? {
        let candidates: [URL?] = [
            bundle.resourceURL?
                .appendingPathComponent(bundledRuntimeFolderName)
                .appendingPathComponent("love-android.apk"),
            bundle.resourceURL?
                .appendingPathComponent("love-android.apk"),
        ]
        return candidates.compactMap { $0 }.first { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    // MARK: iOS

    static func iosRuntimeURL(in bundle: Bundle = .main) -> URL? {
        let candidates: [URL?] = [
            bundle.resourceURL?
                .appendingPathComponent(bundledRuntimeFolderName)
                .appendingPathComponent("love-ios.ipa"),
            bundle.resourceURL?
                .appendingPathComponent("love-ios.ipa"),
            URL(fileURLWithPath: "/Users/\(NSUserName())/Downloads/love-ios.ipa"),
        ]
        return candidates.compactMap { $0 }.first { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    }
}

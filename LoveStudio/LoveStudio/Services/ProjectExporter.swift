import Foundation
import AppKit

// MARK: - ExportTargetFormat

enum ExportTargetFormat: String, CaseIterable, Identifiable {
    case loveArchive
    case macOSAppBundle
    case androidApk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loveArchive:    return ".love Archive"
        case .macOSAppBundle: return "macOS App Bundle"
        case .androidApk:     return "Android APK"
        }
    }

    var detail: String {
        switch self {
        case .loveArchive:
            return "Zips project content into a LÖVE-compatible archive."
        case .macOSAppBundle:
            return "Standalone macOS app bundle based on the bundled love.app runtime."
        case .androidApk:
            return "Android APK with embedded game. Requires love-android.apk runtime template."
        }
    }

    var fileExtension: String {
        switch self {
        case .loveArchive:    return "love"
        case .macOSAppBundle: return "app"
        case .androidApk:     return "apk"
        }
    }

    var systemImage: String {
        switch self {
        case .loveArchive:    return "shippingbox.fill"
        case .macOSAppBundle: return "app.badge.fill"
        case .androidApk:     return "smartphone"
        }
    }
}

// MARK: - ProjectExportMetadata

struct ProjectExportMetadata {
    var appName: String
    var bundleIdentifier: String
    var version: String
    var build: String
    var author: String
    var iconURL: URL?
    var androidPortrait: Bool

    static func defaults(for projectName: String) -> ProjectExportMetadata {
        let sanitized = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = sanitized.isEmpty ? "LoveGame" : sanitized
        let seed = name.lowercased().replacingOccurrences(of: " ", with: "-")
        return ProjectExportMetadata(
            appName: name,
            bundleIdentifier: "com.lovestudio.export.\(seed)",
            version: "1.0.0",
            build: "1",
            author: NSFullUserName(),
            iconURL: nil,
            androidPortrait: true
        )
    }
}

// MARK: - ProjectExportOptions

struct ProjectExportOptions {
    var format: ExportTargetFormat
    var destinationURL: URL
    var includeHiddenFiles: Bool
    var revealInFinder: Bool
    var runtimeAppURL: URL?
    var metadata: ProjectExportMetadata
}

// MARK: - ProjectExportError

enum ProjectExportError: LocalizedError {
    case noExportableFiles
    case missingZipTool
    case missingRuntimeTemplate
    case unwritableDestinationDirectory
    case failedToRemoveExistingFile
    case failedToCopyRuntime
    case failedToCreateFusedExecutable
    case failedToUpdateBundleMetadata
    case invalidBundleIdentifier
    case invalidVersionString
    case invalidBuildString
    case invalidIconFile
    case failedToApplyCustomIcon
    case missingAndroidRuntime
    case missingIOSRuntime
    case failedToInjectGameArchive
    case missingJava
    case apktoolFailed(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .noExportableFiles:
            return "There are no exportable project files."
        case .missingZipTool:
            return "The system zip tool couldn't be found at /usr/bin/zip."
        case .missingRuntimeTemplate:
            return "No LÖVE runtime is available. Build Love Studio with the bundled runtime or install love.app in /Applications."
        case .unwritableDestinationDirectory:
            return "The selected output folder isn't writable."
        case .failedToRemoveExistingFile:
            return "Couldn't replace the existing export file."
        case .failedToCopyRuntime:
            return "Couldn't copy the LÖVE runtime into the exported app bundle."
        case .failedToCreateFusedExecutable:
            return "Couldn't create the fused game executable."
        case .failedToUpdateBundleMetadata:
            return "Couldn't update the exported app bundle metadata (Info.plist)."
        case .invalidBundleIdentifier:
            return "Bundle identifier is invalid. Use reverse-domain style like com.yourname.game."
        case .invalidVersionString:
            return "Version is invalid. Use a value like 1.0.0."
        case .invalidBuildString:
            return "Build number is invalid. Use a numeric value like 1."
        case .invalidIconFile:
            return "Custom app icon must be an .icns file."
        case .failedToApplyCustomIcon:
            return "Couldn't copy the custom icon into the exported app bundle."
        case .missingAndroidRuntime:
            return "No love-android.apk runtime found. Download it from love2d.org and place it in ~/Downloads or in the app's LoveRuntime resources folder."
        case .missingJava:
            return "Java is required for Android export but was not found. Install a JDK (e.g. via Homebrew: brew install --cask zulu@17)."
        case .apktoolFailed(let msg):
            return "apktool failed: \(msg)"
        case .missingIOSRuntime:
            return "iOS export is not supported."
        case .failedToInjectGameArchive:
            return "Couldn't inject the game archive into the mobile runtime."
        case .processFailed(let message):
            return message
        }
    }
}

// MARK: - ProjectExporter

struct ProjectExporter {

    func export(project: Project, options: ProjectExportOptions) throws -> URL {
        switch options.format {
        case .loveArchive:
            return try exportLoveArchive(project: project, options: options)
        case .macOSAppBundle:
            return try exportMacOSAppBundle(project: project, options: options)
        case .androidApk:
            return try exportAndroidApk(project: project, options: options)
        }
    }

    // MARK: .love Archive

    private func exportLoveArchive(project: Project, options: ProjectExportOptions) throws -> URL {
        try createLoveArchive(project: project,
                              destinationURL: options.destinationURL,
                              includeHiddenFiles: options.includeHiddenFiles)
        if options.revealInFinder {
            NSWorkspace.shared.selectFile(options.destinationURL.path, inFileViewerRootedAtPath: "")
        }
        return options.destinationURL
    }

    // MARK: macOS App Bundle

    private func exportMacOSAppBundle(project: Project, options: ProjectExportOptions) throws -> URL {
        let fm = FileManager.default
        try validate(metadata: options.metadata)

        let runtimeURL = options.runtimeAppURL
            ?? LoveRuntimeResolver.bundledLoveAppURL()
            ?? LoveRuntimeResolver.systemLoveAppURL()
        guard let runtimeURL, fm.fileExists(atPath: runtimeURL.path) else {
            throw ProjectExportError.missingRuntimeTemplate
        }

        let destDir = options.destinationURL.deletingLastPathComponent()
        guard fm.fileExists(atPath: destDir.path),
              fm.isWritableFile(atPath: destDir.path) else {
            throw ProjectExportError.unwritableDestinationDirectory
        }

        if fm.fileExists(atPath: options.destinationURL.path) {
            do { try fm.removeItem(at: options.destinationURL) }
            catch { throw ProjectExportError.failedToRemoveExistingFile }
        }

        do { try fm.copyItem(at: runtimeURL, to: options.destinationURL) }
        catch { throw ProjectExportError.failedToCopyRuntime }

        let tempLoveURL = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("love")

        do {
            try createLoveArchive(project: project,
                                  destinationURL: tempLoveURL,
                                  includeHiddenFiles: options.includeHiddenFiles)
            try fuseLoveArchive(intoAppBundleAt: options.destinationURL,
                                projectName: project.name,
                                loveArchiveURL: tempLoveURL,
                                metadata: options.metadata)
        } catch {
            try? fm.removeItem(at: options.destinationURL)
            try? fm.removeItem(at: tempLoveURL)
            throw error
        }

        try? fm.removeItem(at: tempLoveURL)

        if options.revealInFinder {
            NSWorkspace.shared.selectFile(options.destinationURL.path, inFileViewerRootedAtPath: "")
        }
        return options.destinationURL
    }

    // MARK: Android APK

    private func exportAndroidApk(project: Project, options: ProjectExportOptions) throws -> URL {
        let fm = FileManager.default

        let runtimeURL = LoveRuntimeResolver.androidRuntimeURL()
        guard let runtimeURL else { throw ProjectExportError.missingAndroidRuntime }

        let destDir = options.destinationURL.deletingLastPathComponent()
        guard fm.fileExists(atPath: destDir.path),
              fm.isWritableFile(atPath: destDir.path) else {
            throw ProjectExportError.unwritableDestinationDirectory
        }

        if fm.fileExists(atPath: options.destinationURL.path) {
            do { try fm.removeItem(at: options.destinationURL) }
            catch { throw ProjectExportError.failedToRemoveExistingFile }
        }

        // Build .love archive first
        let tempLoveURL = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("love")
        defer { try? fm.removeItem(at: tempLoveURL) }

        try createLoveArchive(project: project,
                              destinationURL: tempLoveURL,
                              includeHiddenFiles: options.includeHiddenFiles)

        // Base APK is pre-patched (GameActivity=launcher, SelectorActivity=disabled).
        // Just inject game files and sign - no apktool needed at export time.
        let unsignedURL = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("apk")
        defer { try? fm.removeItem(at: unsignedURL) }

        do { try fm.copyItem(at: runtimeURL, to: unsignedURL) }
        catch { throw ProjectExportError.failedToCopyRuntime }

        try injectGameIntoAPK(apkURL: unsignedURL, loveArchiveURL: tempLoveURL)

        let keystore = ensureDebugKeystore()
        try signAPK(unsignedURL: unsignedURL,
                    signedURL: options.destinationURL,
                    keystoreURL: keystore)

        if options.revealInFinder {
            NSWorkspace.shared.selectFile(options.destinationURL.path, inFileViewerRootedAtPath: "")
        }
        return options.destinationURL
    }

    /// Full apktool-based export: decompile → patch manifest → inject game → recompile → sign.
    private func exportAndroidWithApktool(project: Project,
                                          runtimeURL: URL,
                                          loveArchiveURL: URL,
                                          destinationURL: URL,
                                          metadata: ProjectExportMetadata,
                                          javaURL: URL,
                                          apktoolJar: URL) throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let decompDir = tempDir.appendingPathComponent("decompiled")
        let recompApk = tempDir.appendingPathComponent("recompiled.apk")
        defer { try? fm.removeItem(at: tempDir) }

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 1. Decompile
        try runProcess(javaURL, args: [
            "-Djava.io.tmpdir=/private/tmp",
            "-jar", apktoolJar.path,
            "d", runtimeURL.path,
            "-o", decompDir.path,
            "-f"
        ])

        // 2. Patch AndroidManifest.xml
        let manifestURL = decompDir.appendingPathComponent("AndroidManifest.xml")
        guard var manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw ProjectExportError.apktoolFailed("Could not read AndroidManifest.xml")
        }

        let appName   = metadata.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pkgName   = sanitizedAndroidPackage(from: metadata.bundleIdentifier)
        let orient    = metadata.androidPortrait ? "portrait" : "landscape"

        // Package name
        manifest = manifest.replacingOccurrences(of: "package=\"org.love2d.android\"",
                                                  with: "package=\"\(pkgName)\"")
        // App & activity labels
        manifest = manifest.replacingOccurrences(of: "android:label=\"L\u{00D6}VE for Android\"",
                                                  with: "android:label=\"\(appName)\"")
        manifest = manifest.replacingOccurrences(of: "android:label=\"L\u{00D6}VE Loader\"",
                                                  with: "android:label=\"\(appName)\"")
        // Screen orientation
        manifest = manifest.replacingOccurrences(of: "android:screenOrientation=\"landscape\"",
                                                  with: "android:screenOrientation=\"\(orient)\"")
        // Disable SelectorActivity
        manifest = manifest.replacingOccurrences(
            of: "android:enabled=\"@bool/selector_active\"",
            with: "android:enabled=\"false\""
        )
        // Move LAUNCHER intent from SelectorActivity to GameActivity so it launches directly.
        // Remove MAIN+LAUNCHER from SelectorActivity's intent-filter block, then add it to GameActivity.
        manifest = manifest.replacingOccurrences(
            of: "<action android:name=\"android.intent.action.MAIN\"/>\n                <category android:name=\"android.intent.category.LAUNCHER\"/>",
            with: ""
        )
        manifest = manifest.replacingOccurrences(
            of: "<action android:name=\"android.intent.action.VIEW\"/>",
            with: "<action android:name=\"android.intent.action.MAIN\"/>\n                <action android:name=\"android.intent.action.VIEW\"/>\n                <category android:name=\"android.intent.category.LAUNCHER\"/>"
        )

        try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)

        // 3. Unzip game.love directly into decompiled assets/ so Love2D Android
        //    finds main.lua etc. directly (it does not load .love archives from assets).
        let assetsDir = decompDir.appendingPathComponent("assets")
        // Remove any leftover game.love from the runtime APK
        try? fm.removeItem(at: assetsDir.appendingPathComponent("game.love"))
        try runProcess(URL(fileURLWithPath: "/usr/bin/unzip"), args: [
            "-o", loveArchiveURL.path,
            "-d", assetsDir.path
        ], allowedExitCodes: [0, 1])

        // 4. Recompile
        try runProcess(javaURL, args: [
            "-Djava.io.tmpdir=/private/tmp",
            "-jar", apktoolJar.path,
            "b", decompDir.path,
            "-o", recompApk.path
        ])

        // 5. Auto-sign with debug keystore
        let signedApk = tempDir.appendingPathComponent("signed.apk")
        let keystore  = ensureDebugKeystore()
        try signAPK(unsignedURL: recompApk, signedURL: signedApk, keystoreURL: keystore)

        // 6. Move to destination
        try fm.copyItem(at: signedApk, to: destinationURL)
    }

    /// Injects game files directly into assets/ of an APK.
    /// Love2D Android loads Lua files directly from assets/, not from a .love archive.
    private func injectGameIntoAPK(apkURL: URL, loveArchiveURL: URL) throws {
        let zipURL = URL(fileURLWithPath: "/usr/bin/zip")
        let unzipURL = URL(fileURLWithPath: "/usr/bin/unzip")
        guard FileManager.default.isExecutableFile(atPath: zipURL.path) else {
            throw ProjectExportError.missingZipTool
        }

        let removeSig = Process()
        removeSig.executableURL = zipURL
        removeSig.arguments = ["-d", apkURL.path, "META-INF/*"]
        removeSig.standardOutput = Pipe()
        removeSig.standardError = Pipe()
        try? removeSig.run()
        removeSig.waitUntilExit()

        // Extract game.love into a staging assets/ folder
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let assetsDir  = stagingDir.appendingPathComponent("assets")
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        do {
            try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        } catch { throw ProjectExportError.failedToInjectGameArchive }

        // Unzip game.love directly into assets/ so Love2D finds main.lua etc.
        let unzip = Process()
        unzip.executableURL = unzipURL
        unzip.arguments = ["-o", loveArchiveURL.path, "-d", assetsDir.path]
        unzip.standardOutput = Pipe()
        unzip.standardError = Pipe()
        try? unzip.run()
        unzip.waitUntilExit()

        // Remove any .love archive that ended up in assets (we want raw files only)
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: nil) {
            files.filter { $0.pathExtension == "love" }.forEach { try? fm.removeItem(at: $0) }
        }

        // Add all extracted game files into the APK under assets/
        let inject = Process()
        inject.executableURL = zipURL
        inject.currentDirectoryURL = stagingDir
        inject.arguments = ["-0", "-r", apkURL.path, "assets"]
        inject.standardOutput = Pipe()
        let errPipe = Pipe()
        inject.standardError = errPipe
        do { try inject.run() } catch { throw ProjectExportError.failedToInjectGameArchive }
        inject.waitUntilExit()

        guard inject.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ProjectExportError.processFailed(msg.isEmpty ? "Failed to inject game into APK." : msg)
        }
    }

    // MARK: Android Signing

    /// Creates a debug keystore at ~/love-studio-debug.keystore if it doesn't exist.
    @discardableResult
    private func ensureDebugKeystore() -> URL {
        let ks = realHomeDirectory().appendingPathComponent("love-studio-debug.keystore")
        guard !FileManager.default.fileExists(atPath: ks.path) else { return ks }

        let keytool = resolveKeytool() ?? URL(fileURLWithPath: "/usr/bin/keytool")
        let p = Process()
        p.executableURL = keytool
        p.arguments = [
            "-genkey", "-v",
            "-keystore", ks.path,
            "-alias", "lovestudio",
            "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
            "-storepass", "lovestudio", "-keypass", "lovestudio",
            "-dname", "CN=Love Studio Debug, O=Love Studio, C=US"
        ]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return ks
    }

    private func signAPK(unsignedURL: URL, signedURL: URL, keystoreURL: URL) throws {
        guard let apksigner = resolveApksigner() else {
            // No apksigner found - copy unsigned
            try FileManager.default.copyItem(at: unsignedURL, to: signedURL)
            return
        }

        let errPipe = Pipe()
        let p = Process()
        p.executableURL = apksigner
        p.arguments = [
            "sign",
            "--ks", keystoreURL.path,
            "--ks-key-alias", "lovestudio",
            "--ks-pass", "pass:lovestudio",
            "--key-pass", "pass:lovestudio",
            "--out", signedURL.path,
            unsignedURL.path
        ]
        // apksigner is a shell script - it needs JAVA_HOME and PATH to find java
        var env = ProcessInfo.processInfo.environment
        if let javaHome = resolveJavaHome() {
            env["JAVA_HOME"] = javaHome
            env["PATH"] = "\(javaHome)/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        }
        p.environment = env
        p.standardOutput = Pipe()
        p.standardError = errPipe
        do { try p.run() } catch { throw ProjectExportError.processFailed(error.localizedDescription) }
        p.waitUntilExit()

        guard p.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ProjectExportError.processFailed(msg.isEmpty ? "APK signing failed." : msg)
        }
    }

    // MARK: Process helpers

    @discardableResult
    private func runProcess(_ executableURL: URL, args: [String], allowedExitCodes: Set<Int32> = [0]) throws -> String {
        let outPipe = Pipe()
        let errPipe = Pipe()
        let p = Process()
        p.executableURL = executableURL
        p.arguments = args
        p.standardOutput = outPipe
        p.standardError = errPipe
        // Use /private/tmp as TMPDIR so apktool can extract and execute its bundled tools
        // (macOS blocks execution from within the app container's tmp folder)
        var env = ProcessInfo.processInfo.environment
        env["TMPDIR"] = "/private/tmp"
        if let jh = resolveJavaHome() {
            env["JAVA_HOME"] = jh
            env["PATH"] = "\(jh)/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        }
        p.environment = env
        do { try p.run() } catch { throw ProjectExportError.processFailed(error.localizedDescription) }
        p.waitUntilExit()
        guard allowedExitCodes.contains(p.terminationStatus) else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ProjectExportError.apktoolFailed(err.isEmpty ? "Exit code \(p.terminationStatus)" : err)
        }
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Returns the real user home directory - works even inside a macOS app sandbox
    /// where NSHomeDirectory() returns the container path instead of ~/
    private func realHomeDirectory() -> URL {
        URL(fileURLWithPath: "/Users/\(NSUserName())")
    }

    private func resolveApksigner() -> URL? {
        let sdkRoot = realHomeDirectory().appendingPathComponent("Library/Android/sdk/build-tools")
        let fm = FileManager.default
        // Pick the highest available build-tools version
        let versions = (try? fm.contentsOfDirectory(atPath: sdkRoot.path))?
            .sorted().reversed() ?? []
        for version in versions {
            let candidate = sdkRoot.appendingPathComponent(version).appendingPathComponent("apksigner")
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func resolveJavaHome() -> String? {
        let jdkRoots = [
            "/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home",
            "/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home",
            "/opt/homebrew/opt/openjdk",
        ]
        return jdkRoots.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func resolveJava() -> URL? {
        let candidates = [
            "/usr/bin/java",
            "/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home/bin/java",
            "/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home/bin/java",
            "/opt/homebrew/opt/openjdk/bin/java",
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func resolveKeytool() -> URL? {
        let candidates = [
            "/usr/bin/keytool",
            "/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home/bin/keytool",
            "/opt/homebrew/opt/openjdk/bin/keytool",
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func sanitizedAndroidPackage(from raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_."))
        var result = raw.lowercased().unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
        // Ensure each segment starts with a letter
        result = result.components(separatedBy: ".").map { seg -> String in
            guard let first = seg.first, first.isNumber || first == "_" else { return seg }
            return "a" + seg
        }.joined(separator: ".")
        return result.isEmpty ? "com.lovestudio.game" : result
    }

    // MARK: iOS IPA

    private func exportIOSIpa(project: Project, options: ProjectExportOptions) throws -> URL {
        let fm = FileManager.default

        let runtimeURL = LoveRuntimeResolver.iosRuntimeURL()
        guard let runtimeURL else { throw ProjectExportError.missingIOSRuntime }

        let destDir = options.destinationURL.deletingLastPathComponent()
        guard fm.fileExists(atPath: destDir.path),
              fm.isWritableFile(atPath: destDir.path) else {
            throw ProjectExportError.unwritableDestinationDirectory
        }

        if fm.fileExists(atPath: options.destinationURL.path) {
            do { try fm.removeItem(at: options.destinationURL) }
            catch { throw ProjectExportError.failedToRemoveExistingFile }
        }

        do { try fm.copyItem(at: runtimeURL, to: options.destinationURL) }
        catch { throw ProjectExportError.failedToCopyRuntime }

        let tempLoveURL = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("love")

        do {
            try createLoveArchive(project: project,
                                  destinationURL: tempLoveURL,
                                  includeHiddenFiles: options.includeHiddenFiles)
            try injectGameIntoIPA(ipaURL: options.destinationURL,
                                  loveArchiveURL: tempLoveURL)
        } catch {
            try? fm.removeItem(at: options.destinationURL)
            try? fm.removeItem(at: tempLoveURL)
            throw error
        }

        try? fm.removeItem(at: tempLoveURL)

        if options.revealInFinder {
            NSWorkspace.shared.selectFile(options.destinationURL.path, inFileViewerRootedAtPath: "")
        }
        return options.destinationURL
    }

    /// Injects game.love into Payload/love.app/ inside an IPA.
    /// IPAs are ZIP files; LÖVE iOS looks for game.love in its bundle at startup.
    private func injectGameIntoIPA(ipaURL: URL, loveArchiveURL: URL) throws {
        let zipURL = URL(fileURLWithPath: "/usr/bin/zip")
        guard FileManager.default.isExecutableFile(atPath: zipURL.path) else {
            throw ProjectExportError.missingZipTool
        }

        // Discover the .app folder name inside Payload/ without extracting the whole IPA.
        let listProcess = Process()
        listProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        listProcess.arguments = ["-Z1", ipaURL.path]
        let listPipe = Pipe()
        listProcess.standardOutput = listPipe
        listProcess.standardError = Pipe()
        try? listProcess.run()
        listProcess.waitUntilExit()

        let listing = String(data: listPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let appFolder = listing.split(separator: "\n")
            .map(String.init)
            .first { $0.hasPrefix("Payload/") && $0.hasSuffix(".app/") }
            ?? "Payload/love.app/"

        let payloadAppPath = appFolder.hasSuffix("/") ? appFolder : appFolder + "/"

        // Stage game.love at the correct nested path so zip preserves the hierarchy.
        let stagingDir  = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let appDir      = stagingDir.appendingPathComponent(payloadAppPath)
        let stagedGame  = appDir.appendingPathComponent("game.love")

        do {
            try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: loveArchiveURL, to: stagedGame)
        } catch {
            throw ProjectExportError.failedToInjectGameArchive
        }

        defer { try? FileManager.default.removeItem(at: stagingDir) }

        let inject = Process()
        inject.executableURL = zipURL
        inject.currentDirectoryURL = stagingDir
        inject.arguments = ["-r", ipaURL.path, "\(payloadAppPath)game.love"]
        inject.standardOutput = Pipe()
        let errPipe = Pipe()
        inject.standardError = errPipe
        do { try inject.run() } catch { throw ProjectExportError.failedToInjectGameArchive }
        inject.waitUntilExit()

        guard inject.terminationStatus == 0 else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ProjectExportError.processFailed(msg.isEmpty ? "Failed to inject game into IPA." : msg)
        }
    }

    // MARK: Create .love archive

    private func createLoveArchive(project: Project, destinationURL: URL, includeHiddenFiles: Bool) throws {
        let zipURL = URL(fileURLWithPath: "/usr/bin/zip")
        guard FileManager.default.isExecutableFile(atPath: zipURL.path) else {
            throw ProjectExportError.missingZipTool
        }

        let paths = exportableRelativePaths(in: project.rootURL, includeHiddenFiles: includeHiddenFiles)
        guard !paths.isEmpty else { throw ProjectExportError.noExportableFiles }

        let destDir = destinationURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: destDir.path),
              FileManager.default.isWritableFile(atPath: destDir.path) else {
            throw ProjectExportError.unwritableDestinationDirectory
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            do { try FileManager.default.removeItem(at: destinationURL) }
            catch { throw ProjectExportError.failedToRemoveExistingFile }
        }

        let errPipe = Pipe()
        let p = Process()
        p.executableURL = zipURL
        p.currentDirectoryURL = project.rootURL
        p.standardOutput = Pipe()
        p.standardError = errPipe
        p.arguments = ["-q", "-r", destinationURL.path] + paths

        do { try p.run() } catch { throw ProjectExportError.processFailed(error.localizedDescription) }
        p.waitUntilExit()

        guard p.terminationStatus == 0 else {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let msg = errText.isEmpty
                ? "zip exited with code \(p.terminationStatus)."
                : errText
            throw ProjectExportError.processFailed(msg)
        }
    }

    // MARK: Fuse

    private func fuseLoveArchive(intoAppBundleAt appURL: URL,
                                  projectName: String,
                                  loveArchiveURL: URL,
                                  metadata: ProjectExportMetadata) throws {
        let fm = FileManager.default
        let macosDir = appURL.appendingPathComponent("Contents/MacOS")
        let originalExec = macosDir.appendingPathComponent("love")
        let displayName = metadata.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? projectName : metadata.appName
        let execName = sanitizedExecutableName(from: displayName)
        let fusedExec = macosDir.appendingPathComponent(execName)
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")

        guard fm.fileExists(atPath: originalExec.path),
              let runtimeData = try? Data(contentsOf: originalExec),
              let archiveData = try? Data(contentsOf: loveArchiveURL) else {
            throw ProjectExportError.failedToCreateFusedExecutable
        }

        var fused = Data()
        fused.append(runtimeData)
        fused.append(archiveData)

        do {
            try fused.write(to: fusedExec, options: .atomic)
            try fm.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))],
                                 ofItemAtPath: fusedExec.path)
            if execName != "love" { try? fm.removeItem(at: originalExec) }
        } catch {
            throw ProjectExportError.failedToCreateFusedExecutable
        }

        guard let info = NSMutableDictionary(contentsOf: infoPlist) else {
            throw ProjectExportError.failedToUpdateBundleMetadata
        }

        let bundleID = sanitizedBundleIdentifier(from: metadata.bundleIdentifier)
        info["CFBundleExecutable"]        = execName
        info["CFBundleName"]              = displayName
        info["CFBundleDisplayName"]       = displayName
        info["CFBundleIdentifier"]        = bundleID
        info["CFBundleShortVersionString"] = metadata.version
        info["CFBundleVersion"]           = metadata.build
        let author = metadata.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty { info["NSHumanReadableCopyright"] = "© \(author)" }

        if let iconURL = metadata.iconURL {
            let iconName = try applyCustomIcon(iconURL, toAppBundleAt: appURL)
            info["CFBundleIconFile"] = iconName
        }

        guard info.write(to: infoPlist, atomically: true) else {
            throw ProjectExportError.failedToUpdateBundleMetadata
        }
    }

    private func applyCustomIcon(_ iconURL: URL, toAppBundleAt appURL: URL) throws -> String {
        guard iconURL.pathExtension.lowercased() == "icns" else {
            throw ProjectExportError.invalidIconFile
        }
        let dest = appURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: iconURL, to: dest)
            return "AppIcon"
        } catch {
            throw ProjectExportError.failedToApplyCustomIcon
        }
    }

    // MARK: Helpers

    private func exportableRelativePaths(in rootURL: URL, includeHiddenFiles: Bool) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var paths: [String] = []
        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            guard !relative.isEmpty else { continue }
            if shouldSkip(relativePath: relative, includeHiddenFiles: includeHiddenFiles) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                paths.append(relative)
            }
        }
        return paths.sorted()
    }

    private func shouldSkip(relativePath: String, includeHiddenFiles: Bool) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        if !includeHiddenFiles, components.contains(where: { $0.hasPrefix(".") }) { return true }
        let excluded: Set<String> = [".DS_Store", "__MACOSX"]
        return components.contains(where: excluded.contains)
    }

    private func sanitizedExecutableName(from raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var result = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" as Character })
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return result.isEmpty ? "Game" : result
    }

    private func sanitizedBundleIdentifier(from raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        var result = String(raw.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" as Character })
        while result.contains("..") { result = result.replacingOccurrences(of: "..", with: ".") }
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return result.isEmpty ? "com.lovestudio.export.game" : result
    }

    private func validate(metadata: ProjectExportMetadata) throws {
        let id = metadata.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let ver = metadata.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = metadata.build.trimmingCharacters(in: .whitespacesAndNewlines)

        guard id.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil else {
            throw ProjectExportError.invalidBundleIdentifier
        }
        guard ver.range(of: #"^\d+(?:\.\d+){0,2}$"#, options: .regularExpression) != nil else {
            throw ProjectExportError.invalidVersionString
        }
        guard build.range(of: #"^\d+$"#, options: .regularExpression) != nil else {
            throw ProjectExportError.invalidBuildString
        }
        if let iconURL = metadata.iconURL, iconURL.pathExtension.lowercased() != "icns" {
            throw ProjectExportError.invalidIconFile
        }
    }
}

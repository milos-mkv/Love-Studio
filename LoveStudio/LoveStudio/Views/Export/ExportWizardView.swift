import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportWizardView: View {

    let project: Project

    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ExportTargetFormat = .loveArchive
    @State private var destinationURL: URL?
    @State private var includeHiddenFiles = false
    @State private var revealInFinder = true
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var exportSuccess: String?
    @State private var metadata: ProjectExportMetadata

    private var resolvedRuntime: URL? {
        switch selectedFormat {
        case .loveArchive:    return nil
        case .macOSAppBundle: return LoveRuntimeResolver.resolve(preferredExternalURL: nil, preferBundled: true)
        case .androidApk:     return LoveRuntimeResolver.androidRuntimeURL()
        }
    }

    private var requiresRuntime: Bool {
        selectedFormat == .macOSAppBundle || selectedFormat == .androidApk
    }

    private var runtimeMissingMessage: String {
        switch selectedFormat {
        case .androidApk:
            return "Download love-android.apk from love2d.org and place it in ~/Downloads."
        default:
            return "Install love.app in /Applications or build Love Studio with the embedded runtime."
        }
    }

    init(project: Project) {
        self.project = project
        _metadata = State(initialValue: ProjectExportMetadata.defaults(for: project.name))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    formatSection
                    destinationSection
                    optionsSection
                    if selectedFormat == .macOSAppBundle {
                        metadataSection
                    }
                    if selectedFormat == .androidApk {
                        androidMetadataSection
                        mobileInfoSection
                    }
                    statusSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            destinationURL = suggestedDestinationURL(for: selectedFormat)
        }
        .onChange(of: selectedFormat) {
            destinationURL = destinationURL
                .map { $0.deletingPathExtension().appendingPathExtension(selectedFormat.fileExtension) }
                ?? suggestedDestinationURL(for: selectedFormat)
            exportError = nil
            exportSuccess = nil
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Export Project")
                .font(.title2.weight(.semibold))
            Text("Package \(project.name) for sharing or distribution.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    // MARK: Format

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Format")
            VStack(spacing: 10) {
                ForEach(ExportTargetFormat.allCases) { format in
                    Button { selectedFormat = format } label: {
                        HStack(spacing: 12) {
                            Image(systemName: format.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(format.title).font(.headline).foregroundStyle(.primary)
                                Text(format.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selectedFormat == format ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedFormat == format ? Color.accentColor : Color.secondary.opacity(0.7))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedFormat == format ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    selectedFormat == format ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Destination

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Output")
            VStack(alignment: .leading, spacing: 10) {
                Text(destinationURL?.path ?? "Choose an output location")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(destinationURL == nil ? .tertiary : .secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                HStack(spacing: 10) {
                    Button("Choose Location") { chooseDestination() }
                        .buttonStyle(.borderedProminent)
                    if let url = destinationURL {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text("Default export location is the project folder.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Options")
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Reveal exported file in Finder", isOn: $revealInFinder)
                Toggle(".love only: include hidden files", isOn: $includeHiddenFiles)
                    .disabled(selectedFormat != .loveArchive)
                if requiresRuntime {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Runtime Template")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(resolvedRuntime?.path ?? "No runtime found")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(resolvedRuntime == nil ? Color(NSColor.systemRed) : .secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }

    // MARK: Bundle Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Bundle Metadata")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    labeledField(title: "App Name", text: $metadata.appName)
                    labeledField(title: "Author", text: $metadata.author)
                }
                labeledField(title: "Bundle Identifier", text: $metadata.bundleIdentifier)
                HStack(spacing: 12) {
                    labeledField(title: "Version", text: $metadata.version)
                    labeledField(title: "Build", text: $metadata.build)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom App Icon (.icns)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Text(metadata.iconURL?.lastPathComponent ?? "No custom icon selected")
                            .font(.caption)
                            .foregroundStyle(metadata.iconURL == nil ? .tertiary : .secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Choose Icon") { chooseIcon() }.buttonStyle(.bordered)
                        if metadata.iconURL != nil {
                            Button("Clear") { metadata.iconURL = nil }.buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }

    // MARK: Android Metadata

    private var androidMetadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("App Info")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    labeledField(title: "App Name", text: $metadata.appName)
                    labeledField(title: "Package ID", text: $metadata.bundleIdentifier)
                }
                Toggle("Portrait orientation", isOn: $metadata.androidPortrait)
                    .toggleStyle(.switch)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }

    // MARK: Mobile Info

    private var mobileInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Android Notes")
            VStack(alignment: .leading, spacing: 10) {
                infoRow(icon: "checkmark.circle", text: "APK je auto-potpisan debug keystoreom — spreman za adb install.")
                infoRow(icon: "checkmark.circle", text: "App name, package ID i orijentacija su upisani u manifest.")
                infoRow(icon: "exclamationmark.triangle", text: "Za Play Store distribuciju potrebno je potpisati sa release keystoreom.")
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusSection: some View {
        if let exportError {
            statusCard(title: "Export failed", message: exportError, tint: .red)
        } else if let exportSuccess {
            statusCard(title: "Export complete", message: exportSuccess, tint: .green)
        } else if selectedFormat == .macOSAppBundle && !isBundleIdentifierValid {
            statusCard(
                title: "Bundle identifier looks invalid",
                message: "Use reverse-domain style, e.g. com.yourname.\(project.name.lowercased()).",
                tint: .orange
            )
        } else if requiresRuntime && resolvedRuntime == nil {
            statusCard(
                title: "Runtime required",
                message: runtimeMissingMessage,
                tint: .orange
            )
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if isExporting {
                ProgressView().scaleEffect(0.75).padding(.trailing, 4)
            }
            Button("Export") { exportProject() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting || destinationURL == nil || !canExport)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
    }

    private func statusCard(title: String, message: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline).foregroundStyle(tint)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.2), lineWidth: 1))
    }

    private func labeledField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(title, text: text).textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canExport: Bool {
        if selectedFormat == .macOSAppBundle {
            return resolvedRuntime != nil
                && isBundleIdentifierValid
                && !metadata.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !metadata.build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if selectedFormat == .androidApk {
            return resolvedRuntime != nil
        }
        return true
    }

    private var isBundleIdentifierValid: Bool {
        metadata.bundleIdentifier.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#,
                                        options: .regularExpression) != nil
    }

    private func suggestedDestinationURL(for format: ExportTargetFormat) -> URL {
        project.rootURL
            .appendingPathComponent(project.name)
            .appendingPathExtension(format.fileExtension)
    }

    // MARK: Actions

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.title = "Export \(project.name)"
        panel.nameFieldStringValue = "\(project.name).\(selectedFormat.fileExtension)"
        panel.allowedContentTypes = []
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = destinationURL?.deletingLastPathComponent() ?? project.rootURL
        if panel.runModal() == .OK, let url = panel.url {
            destinationURL = url.deletingPathExtension().appendingPathExtension(selectedFormat.fileExtension)
            exportError = nil
            exportSuccess = nil
        }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.title = "Choose App Icon"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "icns")].compactMap { $0 }
        if panel.runModal() == .OK { metadata.iconURL = panel.url }
    }

    private func exportProject() {
        guard let destinationURL else { return }
        isExporting = true
        exportError = nil
        exportSuccess = nil

        let runtime = resolvedRuntime
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try ProjectExporter().export(
                    project: project,
                    options: ProjectExportOptions(
                        format: selectedFormat,
                        destinationURL: destinationURL,
                        includeHiddenFiles: includeHiddenFiles,
                        revealInFinder: revealInFinder,
                        runtimeAppURL: runtime,
                        metadata: metadata
                    )
                )
            }
            DispatchQueue.main.async {
                isExporting = false
                switch result {
                case .success(let url):
                    exportSuccess = successMessage(for: url)
                case .failure(let error):
                    exportError = error.localizedDescription
                }
            }
        }
    }

    private func successMessage(for url: URL) -> String {
        switch selectedFormat {
        case .macOSAppBundle:
            return "Created \(url.lastPathComponent)\nBundle ID: \(metadata.bundleIdentifier)\nVersion: \(metadata.version) (\(metadata.build))\nLocation: \(url.path)"
        case .androidApk:
            return "Created \(url.lastPathComponent)\nSigned with debug keystore — ready to install.\nadb install \"\(url.path)\"\nLocation: \(url.path)"
        default:
            return "Created \(url.lastPathComponent)\nLocation: \(url.path)"
        }
    }
}

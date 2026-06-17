import SwiftUI
import AppKit
import AVFoundation
import Combine
import CoreText

// MARK: - Cache

private let assetPreviewCache = AssetPreviewCache.shared

// MARK: - Enums

private enum AssetFilter: String, CaseIterable, Identifiable {
    case all = "All", images = "Images", audio = "Audio", fonts = "Fonts"
    var id: String { rawValue }

    func matches(_ item: ProjectItem) -> Bool {
        switch self {
        case .all:    return item.kind == .image || item.kind == .audio || item.kind == .font
        case .images: return item.kind == .image
        case .audio:  return item.kind == .audio
        case .fonts:  return item.kind == .font
        }
    }
}

private enum AssetSort: String, CaseIterable, Identifiable {
    case name = "Name", type = "Type", size = "Size", recent = "Recent"
    var id: String { rawValue }
}

private enum ImagePreviewZoom: String, CaseIterable, Identifiable {
    case fit = "Fit", fifty = "50%", hundred = "100%", twoHundred = "200%"
    var id: String { rawValue }
    var scaleFactor: CGFloat? {
        switch self {
        case .fit: return nil
        case .fifty: return 0.5
        case .hundred: return 1.0
        case .twoHundred: return 2.0
        }
    }
}

private struct AssetGroup: Identifiable {
    let id: String
    let title: String
    let items: [ProjectItem]
}

// MARK: - AssetBrowserView

struct AssetBrowserView: View {

    let project: Project

    private static let favoriteAssetsKey = "favoriteAssetPaths"
    private static let recentAssetsKey   = "recentAssetPaths"

    @State private var selectedFilter: AssetFilter = .all
    @State private var selectedSort:   AssetSort   = .name
    @State private var selectedAssetURL: String?
    @State private var searchText = ""
    @State private var imageZoom: ImagePreviewZoom = .fit
    @State private var fontSampleText  = "The quick brown fox jumps over the lazy dog"
    @State private var fontPreviewSize: Double = 20
    @State private var favoriteAssetPaths: [String] = []
    @State private var recentAssetPaths:   [String] = []
    @State private var visibleAssets: [ProjectItem] = []
    @State private var groupedImageAssets:        [AssetGroup] = []
    @State private var groupedAudioAndFontAssets: [AssetGroup] = []
    @State private var groupedFavoriteAssets:     [AssetGroup] = []
    @State private var groupedRecentAssets:       [AssetGroup] = []
    @StateObject private var audioPlayer = AssetAudioPreviewPlayer()

    private var selectedAsset: ProjectItem? {
        if let url = selectedAssetURL {
            return visibleAssets.first(where: { $0.url.path == url })
                ?? collectAllAssets(from: project.items).first(where: { $0.url.path == url })
        }
        return visibleAssets.first
    }

    private var imageColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 100, maximum: 180), spacing: 8),
            GridItem(.flexible(minimum: 100, maximum: 180), spacing: 8)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if visibleAssets.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    browserArea
                    Divider()
                    previewArea
                        .frame(maxWidth: .infinity, maxHeight: 350, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadAssetPreferences()
            rebuildAssetCollections()
            syncSelection()
        }
        .onChange(of: selectedFilter) { rebuildAssetCollections(); syncSelection() }
        .onChange(of: selectedSort)   { rebuildAssetCollections(); syncSelection() }
        .onChange(of: searchText)     { rebuildAssetCollections(); syncSelection() }
        .onChange(of: favoriteAssetPaths) { rebuildAssetCollections(); syncSelection() }
        .onChange(of: recentAssetPaths)   { rebuildAssetCollections(); syncSelection() }
        .onDisappear { audioPlayer.stop() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Assets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                badge("\(favoriteAssetPaths.count)", tint: .yellow)
                badge("\(visibleAssets.count)", tint: .secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search assets", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))

            VStack(alignment: .leading, spacing: 6) {
                Text("Asset Filter")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)

                HStack(alignment: .center, spacing: 8) {
                    Picker("", selection: $selectedFilter) {
                        ForEach(AssetFilter.allCases) { f in Text(f.rawValue).tag(f) }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)

                    Menu {
                        ForEach(AssetSort.allCases) { s in
                            Button(s.rawValue) { selectedSort = s }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(selectedSort.rawValue)
                        }
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Browser Area

    private var browserArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !groupedFavoriteAssets.isEmpty {
                    groupedSection("Favorites", groups: groupedFavoriteAssets, includeImagesAsGrid: true)
                }
                if !groupedRecentAssets.isEmpty {
                    groupedSection("Recent", groups: groupedRecentAssets, includeImagesAsGrid: true)
                }
                if !groupedImageAssets.isEmpty {
                    groupedSection("Images", groups: groupedImageAssets, includeImagesAsGrid: true)
                }
                if !groupedAudioAndFontAssets.isEmpty {
                    groupedSection("Audio & Fonts", groups: groupedAudioAndFontAssets, includeImagesAsGrid: false)
                }
            }
            .padding(8)
        }
    }

    // MARK: Preview Area

    private var previewArea: some View {
        Group {
            if let asset = selectedAsset {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        previewHeader(for: asset)
                        previewBody(for: asset)
                        metadataBlock(for: asset)
                    }
                    .padding(10)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.person.crop")
                        .font(.system(size: 24)).foregroundStyle(.secondary)
                    Text("Select an asset to preview")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white.opacity(0.015))
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34)).foregroundStyle(.secondary)
            Text("No asset files")
                .font(.headline).foregroundStyle(.secondary)
            Text("Add images, audio or fonts to your project folder.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Grouped Section

    @ViewBuilder
    private func groupedSection(_ title: String, groups: [AssetGroup], includeImagesAsGrid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            assetSectionTitle(title)
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    folderHeader(group.title, count: group.items.count)
                    if includeImagesAsGrid, group.items.allSatisfy({ $0.kind == .image }) {
                        LazyVGrid(columns: imageColumns, spacing: 8) {
                            ForEach(group.items) { item in imageCard(for: item) }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(group.items) { item in assetRow(for: item) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Image Card

    private func imageCard(for item: ProjectItem) -> some View {
        Button { selectAsset(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AssetThumbnailView(item: item)
                        .frame(height: 96).frame(maxWidth: .infinity)
                    if isFavorite(item) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10)).foregroundStyle(.yellow).padding(8)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.caption.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(relativePath(of: item))
                        .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedAssetURL == item.url.path ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selectedAssetURL == item.url.path ? Color.accentColor.opacity(0.24) : Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain).contentShape(Rectangle())
        .contextMenu { assetContextMenu(for: item) }
        .onDrag { NSItemProvider(object: relativePath(of: item) as NSString) }
    }

    // MARK: Asset Row

    private func assetRow(for item: ProjectItem) -> some View {
        Button { selectAsset(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.kind.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(kindColor(item.kind))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.caption.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(relativePath(of: item))
                        .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if isFavorite(item) {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                }
                if item.kind == .audio, audioPlayer.isPlaying(item.url) {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 11)).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedAssetURL == item.url.path ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.03))
            )
        }
        .buttonStyle(.plain).contentShape(Rectangle())
        .contextMenu { assetContextMenu(for: item) }
        .onDrag { NSItemProvider(object: relativePath(of: item) as NSString) }
    }

    // MARK: Context Menu

    @ViewBuilder
    private func assetContextMenu(for item: ProjectItem) -> some View {
        Button(isFavorite(item) ? "Remove from Favorites" : "Add to Favorites") { toggleFavorite(item) }
        Button("Copy Relative Path") { copyRelativePath(item) }
        Button("Reveal in Finder")   { revealInFinder(item) }
    }

    // MARK: Preview Header

    private func previewHeader(for asset: ProjectItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: asset.kind.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(kindColor(asset.kind))
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name)
                    .font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(relativePath(of: asset))
                    .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(2)
            }
            Spacer()
            HStack(spacing: 6) {
                tinyIconButton(systemName: isFavorite(asset) ? "star.fill" : "star") { toggleFavorite(asset) }
                    .foregroundStyle(isFavorite(asset) ? Color.yellow : Color.secondary)
                tinyIconButton(systemName: "doc.on.doc") { copyRelativePath(asset) }
                    .foregroundStyle(.secondary)
                tinyIconButton(systemName: "folder") { revealInFinder(asset) }
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Preview Body

    @ViewBuilder
    private func previewBody(for asset: ProjectItem) -> some View {
        switch asset.kind {
        case .image: imagePreview(for: asset)
        case .audio: audioPreview(for: asset)
        case .font:  fontPreview(for: asset)
        default: EmptyView()
        }
    }

    private func imagePreview(for asset: ProjectItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Image Preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Picker("Zoom", selection: $imageZoom) {
                    ForEach(ImagePreviewZoom.allCases) { z in Text(z.rawValue).tag(z) }
                }
                .pickerStyle(.segmented).frame(width: 220)
            }

            if let image = assetPreviewCache.image(for: asset.url) {
                let sz = image.size
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                        .overlay {
                            GeometryReader { proxy in
                                if let scale = imageZoom.scaleFactor {
                                    ScrollView([.horizontal, .vertical]) {
                                        Image(nsImage: image)
                                            .resizable().interpolation(.none)
                                            .frame(width: max(1, sz.width * scale), height: max(1, sz.height * scale))
                                            .padding(16)
                                    }
                                } else {
                                    let fit = min(
                                        max((proxy.size.width - 32) / max(sz.width, 1), 0.1),
                                        max((proxy.size.height - 32) / max(sz.height, 1), 0.1)
                                    )
                                    Image(nsImage: image)
                                        .resizable().interpolation(.none)
                                        .frame(width: max(1, sz.width * fit), height: max(1, sz.height * fit))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .overlay {
                            CheckerboardBackground()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .allowsHitTesting(false).opacity(0.5)
                        }

                    Text("\(Int(sz.width)) x \(Int(sz.height))")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.45)))
                        .padding(10)
                }
                .frame(maxWidth: .infinity).frame(height: 240)
            } else {
                placeholderBlock("Image preview unavailable", systemImage: "photo")
            }
        }
    }

    private func audioPreview(for asset: ProjectItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Audio Preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(audioPlayer.isPlaying(asset.url) ? "Now Playing" : "Ready")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(audioPlayer.isPlaying(asset.url) ? Color.green : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button { audioPlayer.toggle(url: asset.url) } label: {
                        Label(
                            audioPlayer.isPlaying(asset.url) ? "Stop" : "Play",
                            systemImage: audioPlayer.isPlaying(asset.url) ? "stop.fill" : "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button { audioPlayer.stop() } label: {
                        Image(systemName: "speaker.slash.fill").frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!audioPlayer.isPlaying(asset.url))
                }

                VStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { min(audioPlayer.currentTime, max(audioPlayer.duration, 0.01)) },
                            set: { audioPlayer.seek(to: $0) }
                        ),
                        in: 0...max(audioPlayer.duration, 0.01)
                    )
                    .disabled(audioPlayer.duration <= 0)

                    HStack {
                        Text(audioPlayer.formattedTime(audioPlayer.currentTime))
                        Spacer()
                        Text(audioPlayer.formattedTime(audioPlayer.duration))
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
                }

                Toggle("Loop playback", isOn: Binding(
                    get:  { audioPlayer.isLooping },
                    set:  { audioPlayer.isLooping = $0 }
                ))
                .toggleStyle(.switch)

                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.1.fill").foregroundStyle(.secondary)
                    Slider(
                        value: Binding(get: { audioPlayer.volume }, set: { audioPlayer.volume = $0 }),
                        in: 0...1
                    )
                    Text("\(Int(audioPlayer.volume * 100))%")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        }
    }

    private func fontPreview(for asset: ProjectItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Font Preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fontPreviewSize)) pt").font(.caption).foregroundStyle(.tertiary)
            }

            TextField("Sample text", text: $fontSampleText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))

            HStack(spacing: 10) {
                Text("Size").font(.caption).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
                Slider(value: $fontPreviewSize, in: 10...42)
            }

            if let primaryFont = assetPreviewCache.previewFont(for: asset.url, size: fontPreviewSize) {
                VStack(alignment: .leading, spacing: 8) {
                    if let titleFont = assetPreviewCache.previewFont(for: asset.url, size: fontPreviewSize + 10) {
                        fontPreviewCard(text: fontSampleText, font: titleFont)
                    }
                    fontPreviewCard(text: fontSampleText, font: primaryFont)
                    if let smallFont = assetPreviewCache.previewFont(for: asset.url, size: max(12, fontPreviewSize - 4)) {
                        fontPreviewCard(text: "0123456789  AaBbCcDdEe  !?@#%&*", font: smallFont)
                    }
                }
            } else {
                placeholderBlock("Font preview unavailable", systemImage: "textformat")
            }
        }
    }

    private func fontPreviewCard(text: String, font: NSFont) -> some View {
        Text(text)
            .font(Font(font)).id(font.pointSize)
            .foregroundStyle(.primary).lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    // MARK: Metadata

    private func metadataBlock(for asset: ProjectItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 6) {
                metadataRow("File",   value: asset.name)
                metadataRow("Path",   value: relativePath(of: asset))
                metadataRow("Format", value: asset.url.pathExtension.uppercased())
                metadataRow("Size",   value: ByteCountFormatter.string(fromByteCount: fileSize(for: asset.url), countStyle: .file))
                if let mod = modifiedDate(for: asset.url) {
                    metadataRow("Modified", value: mod)
                }
                if asset.kind == .image, let sz = assetPreviewCache.imageSize(for: asset.url) {
                    metadataRow("Dimensions", value: "\(Int(sz.width)) x \(Int(sz.height)) px")
                }
                if asset.kind == .audio {
                    if let dur = assetPreviewCache.audioMetadata(for: asset.url)?.duration {
                        metadataRow("Duration", value: dur)
                    }
                    if let fmt = assetPreviewCache.audioMetadata(for: asset.url)?.format {
                        metadataRow("Sample Rate", value: fmt.sampleRate)
                        metadataRow("Channels",    value: fmt.channels)
                    }
                }
                if asset.kind == .font {
                    if let name = assetPreviewCache.fontName(for: asset.url) {
                        metadataRow("Font", value: name)
                    }
                    if let ps = assetPreviewCache.postScriptFontName(for: asset.url) {
                        metadataRow("PostScript", value: ps)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.03)))
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Helpers

    private func badge(_ value: String, tint: Color) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func assetSectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary).padding(.horizontal, 2)
    }

    private func folderHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.05)))
        }
        .padding(.horizontal, 2)
    }

    private func placeholderBlock(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private func tinyIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private func kindColor(_ kind: FileKind) -> Color {
        switch kind {
        case .image: return .purple
        case .audio: return .green
        case .font:  return .blue
        case .lua:   return .orange
        case .other: return .secondary
        }
    }

    private func relativePath(of item: ProjectItem) -> String {
        let full   = item.url.path
        let root   = project.rootURL.path
        if full.hasPrefix(root) {
            let rel = String(full.dropFirst(root.count))
            return rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
        }
        return item.url.lastPathComponent
    }

    private func fileSize(for url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    private func modifiedDate(for url: URL) -> String? {
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        return Self.modifiedDateFormatter.string(from: date)
    }

    private static let modifiedDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    // MARK: Collections

    private func collectAllAssets(from items: [ProjectItem]) -> [ProjectItem] {
        var result: [ProjectItem] = []
        for item in items {
            if item.isFolder { result.append(contentsOf: collectAllAssets(from: item.children)) }
            else if item.kind == .image || item.kind == .audio || item.kind == .font { result.append(item) }
        }
        return result
    }

    private func rebuildAssetCollections() {
        let all = collectAllAssets(from: project.items)
        let filtered = sortItems(all.filter { item in
            selectedFilter.matches(item) && matchesSearch(item)
        })
        visibleAssets             = filtered
        groupedImageAssets        = groupedAssets(from: filtered.filter { $0.kind == .image })
        groupedAudioAndFontAssets = groupedAssets(from: filtered.filter { $0.kind == .audio || $0.kind == .font })
        groupedFavoriteAssets     = groupedAssets(from: filtered.filter { favoriteAssetPaths.contains($0.url.path) })
        groupedRecentAssets       = groupedAssets(
            from: filtered
                .filter { recentAssetPaths.contains($0.url.path) && !favoriteAssetPaths.contains($0.url.path) }
                .sorted { recentIndex(of: $0.url.path) < recentIndex(of: $1.url.path) }
        )
    }

    private func groupedAssets(from items: [ProjectItem]) -> [AssetGroup] {
        let grouped = Dictionary(grouping: items) { folderLabel(for: $0) }
        return grouped.keys.sorted().map { title in
            AssetGroup(id: title, title: title, items: grouped[title] ?? [])
        }
    }

    private func folderLabel(for item: ProjectItem) -> String {
        let rel = relativePath(of: item)
        let folder = (rel as NSString).deletingLastPathComponent
        return folder.isEmpty ? "Root" : folder
    }

    private func sortItems(_ items: [ProjectItem]) -> [ProjectItem] {
        switch selectedSort {
        case .name:
            return items.sorted { relativePath(of: $0).localizedCaseInsensitiveCompare(relativePath(of: $1)) == .orderedAscending }
        case .type:
            return items.sorted {
                let ka = $0.kind.icon; let kb = $1.kind.icon
                if ka == kb { return relativePath(of: $0).localizedCaseInsensitiveCompare(relativePath(of: $1)) == .orderedAscending }
                return ka < kb
            }
        case .size:
            return items.sorted { fileSize(for: $0.url) > fileSize(for: $1.url) }
        case .recent:
            return items.sorted {
                let li = recentIndex(of: $0.url.path); let ri = recentIndex(of: $1.url.path)
                if li == ri { return relativePath(of: $0).localizedCaseInsensitiveCompare(relativePath(of: $1)) == .orderedAscending }
                return li < ri
            }
        }
    }

    private func matchesSearch(_ item: ProjectItem) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return item.name.lowercased().contains(q) || relativePath(of: item).lowercased().contains(q)
    }

    private func recentIndex(of path: String) -> Int {
        recentAssetPaths.firstIndex(of: path) ?? Int.max
    }

    private func syncSelection() {
        if let sel = selectedAssetURL, visibleAssets.contains(where: { $0.url.path == sel }) { return }
        selectedAssetURL = visibleAssets.first?.url.path
    }

    private func selectAsset(_ item: ProjectItem) {
        selectedAssetURL = item.url.path
        recordRecent(item)
    }

    private func isFavorite(_ item: ProjectItem) -> Bool { favoriteAssetPaths.contains(item.url.path) }

    private func toggleFavorite(_ item: ProjectItem) {
        if let i = favoriteAssetPaths.firstIndex(of: item.url.path) { favoriteAssetPaths.remove(at: i) }
        else { favoriteAssetPaths.insert(item.url.path, at: 0) }
        favoriteAssetPaths = Array(favoriteAssetPaths.prefix(20))
        persistAssetPreferences()
    }

    private func recordRecent(_ item: ProjectItem) {
        recentAssetPaths.removeAll { $0 == item.url.path }
        recentAssetPaths.insert(item.url.path, at: 0)
        recentAssetPaths = Array(recentAssetPaths.prefix(20))
        persistAssetPreferences()
    }

    private func copyRelativePath(_ item: ProjectItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(relativePath(of: item), forType: .string)
        recordRecent(item)
    }

    private func revealInFinder(_ item: ProjectItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
        recordRecent(item)
    }

    private func loadAssetPreferences() {
        favoriteAssetPaths = UserDefaults.standard.stringArray(forKey: Self.favoriteAssetsKey) ?? []
        recentAssetPaths   = UserDefaults.standard.stringArray(forKey: Self.recentAssetsKey)   ?? []
    }

    private func persistAssetPreferences() {
        UserDefaults.standard.set(favoriteAssetPaths, forKey: Self.favoriteAssetsKey)
        UserDefaults.standard.set(recentAssetPaths,   forKey: Self.recentAssetsKey)
    }
}

// MARK: - AssetThumbnailView

private struct AssetThumbnailView: View, Equatable {
    let item: ProjectItem

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.item.url == rhs.item.url }

    @StateObject private var loader: AssetThumbnailLoader

    init(item: ProjectItem) {
        self.item = item
        _loader = StateObject(wrappedValue: AssetThumbnailLoader(url: item.url))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                ZStack {
                    CheckerboardBackground()
                    Image(nsImage: image)
                        .resizable().interpolation(.none).scaledToFit()
                        .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.22)))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .onAppear { loader.load() }
    }
}

private final class AssetThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    private let url: URL
    private var hasLoaded = false

    init(url: URL) { self.url = url }

    func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let cached = assetPreviewCache.cachedImage(for: url) { image = cached; return }
        image = assetPreviewCache.image(for: url)
    }
}

// MARK: - AssetPreviewCache

private final class AssetPreviewCache {
    static let shared = AssetPreviewCache()

    typealias AudioFormat   = (sampleRate: String, channels: String)
    typealias AudioMetadata = (duration: String?, format: AudioFormat?)

    private let lock            = NSLock()
    private let imageCache      = NSCache<NSURL, NSImage>()
    private let imageSizeCache  = NSCache<NSURL, NSValue>()
    private let fontCache       = NSCache<NSString, NSFont>()
    private var cgFonts:        [String: CGFont]        = [:]
    private var audioMetaCache: [String: AudioMetadata] = [:]

    private init() { imageCache.countLimit = 300; imageSizeCache.countLimit = 300; fontCache.countLimit = 120 }

    func cachedImage(for url: URL) -> NSImage? { imageCache.object(forKey: url as NSURL) }

    func image(for url: URL) -> NSImage? {
        if let c = cachedImage(for: url) { return c }
        guard let img = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(img, forKey: url as NSURL)
        imageSizeCache.setObject(NSValue(size: img.size), forKey: url as NSURL)
        return img
    }

    func imageSize(for url: URL) -> NSSize? {
        if let c = imageSizeCache.object(forKey: url as NSURL) { return c.sizeValue }
        return image(for: url)?.size
    }

    func audioMetadata(for url: URL) -> AudioMetadata? {
        let key = url.standardizedFileURL.path
        lock.lock(); if let c = audioMetaCache[key] { lock.unlock(); return c }; lock.unlock()
        guard let af = try? AVAudioFile(forReading: url) else { return nil }
        let fmt = af.processingFormat
        var dur: String?
        if let p = try? AVAudioPlayer(contentsOf: url), p.duration.isFinite, p.duration > 0 {
            dur = AssetAudioPreviewPlayer.formattedTime(p.duration)
        }
        let meta: AudioMetadata = (dur, ("\(Int(fmt.sampleRate)) Hz", "\(fmt.channelCount)"))
        lock.lock(); audioMetaCache[key] = meta; lock.unlock()
        return meta
    }

    func cgFont(for url: URL) -> CGFont? {
        let key = url.standardizedFileURL.path
        lock.lock(); if let c = cgFonts[key] { lock.unlock(); return c }; lock.unlock()
        guard let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) else { return nil }
        lock.lock(); cgFonts[key] = font; lock.unlock()
        return font
    }

    func fontName(for url: URL) -> String? {
        guard let f = cgFont(for: url) else { return nil }
        return (f.fullName as String?) ?? (f.postScriptName as String?)
    }

    func postScriptFontName(for url: URL) -> String? { cgFont(for: url).flatMap { $0.postScriptName as String? } }

    func previewFont(for url: URL, size: Double) -> NSFont? {
        let key = "\(url.standardizedFileURL.path)#\(String(format: "%.2f", size))" as NSString
        if let c = fontCache.object(forKey: key) { return c }
        guard let cg = cgFont(for: url) else { return nil }
        let font = CTFontCreateWithGraphicsFont(cg, CGFloat(size), nil, nil) as NSFont
        fontCache.setObject(font, forKey: key)
        return font
    }
}

// MARK: - AssetAudioPreviewPlayer

final class AssetAudioPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var currentURL:  URL?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration:    TimeInterval = 0
    @Published var isLooping = false { didSet { player?.numberOfLoops = isLooping ? -1 : 0 } }
    @Published var volume: Double = 1 { didSet { player?.volume = Float(volume) } }

    private var player: AVAudioPlayer?
    private var timer:  Timer?

    func toggle(url: URL) { isPlaying(url) ? stop() : play(url: url) }

    func play(url: URL) {
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self; p.numberOfLoops = isLooping ? -1 : 0; p.volume = Float(volume)
        p.prepareToPlay(); p.play()
        player = p; currentURL = url.standardizedFileURL; duration = p.duration; currentTime = p.currentTime
        startTimer()
    }

    func stop() {
        timer?.invalidate(); timer = nil; player?.stop(); player = nil
        currentURL = nil; currentTime = 0; duration = 0
    }

    func seek(to time: TimeInterval) {
        guard let p = player else { return }
        let t = min(max(0, time), duration); p.currentTime = t; currentTime = t
    }

    func isPlaying(_ url: URL) -> Bool { currentURL == url.standardizedFileURL && player?.isPlaying == true }

    func formattedTime(_ s: TimeInterval) -> String { Self.formattedTime(s) }
    static func formattedTime(_ s: TimeInterval) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let t = Int(s.rounded(.down)); return String(format: "%d:%02d", t / 60, t % 60)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { stop() }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let p = self.player else { return }
            self.currentTime = p.currentTime; self.duration = p.duration
        }
    }
}

// MARK: - CheckerboardBackground

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 12
            for row in 0..<Int(ceil(size.height / cell)) {
                for col in 0..<Int(ceil(size.width / cell)) {
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    ctx.fill(Path(rect), with: .color((row + col).isMultiple(of: 2) ? Color.white.opacity(0.05) : Color.white.opacity(0.015)))
                }
            }
        }
        .drawingGroup()
    }
}

import SwiftUI
import AppKit
import AVFoundation
import Combine
import CoreText

// MARK: - AssetPreviewSheet

struct AssetPreviewSheet: View {
    let item: ProjectItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: item.kind.icon)
                    .foregroundStyle(kindColor)
                Text(item.name)
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            switch item.kind {
            case .image: ImagePreviewContent(item: item)
            case .audio: AudioPreviewContent(item: item)
            case .font:  FontPreviewContent(item: item)
            default:     EmptyView()
            }
        }
        .frame(width: 480)
    }

    private var kindColor: Color {
        switch item.kind {
        case .image: return .purple
        case .audio: return .teal
        case .font:  return .blue
        default:     return .secondary
        }
    }
}

// MARK: - Image Preview

private struct ImagePreviewContent: View {
    let item: ProjectItem
    @State private var image: NSImage? = nil

    private var fileSize: String {
        let bytes = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                SheetCheckerboardView()
                if let img = image {
                    Image(nsImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                } else {
                    ProgressView()
                }
            }
            .frame(height: 260)
            .clipped()

            Divider()

            VStack(spacing: 0) {
                if let img = image {
                    let rep = img.representations.first
                    let w = rep?.pixelsWide ?? Int(img.size.width)
                    let h = rep?.pixelsHigh ?? Int(img.size.height)
                    infoRow("Dimensions", value: "\(w) × \(h) px")
                }
                infoRow("Format",  value: item.url.pathExtension.uppercased())
                infoRow("Size",    value: fileSize)
                infoRow("Path",    value: item.url.path)
            }
            .padding(.vertical, 4)
        }
        .task {
            image = NSImage(contentsOf: item.url)
        }
    }
}

// MARK: - Audio Preview

private struct AudioPreviewContent: View {
    let item: ProjectItem
    @StateObject private var player = SheetAudioPlayer()

    private var fileSize: String {
        let bytes = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                VStack(spacing: 18) {
                    Image(systemName: "waveform")
                        .font(.system(size: 44))
                        .foregroundStyle(.teal.opacity(0.5))

                    HStack(spacing: 24) {
                        Button { player.seek(to: 0) } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain).help("Rewind")

                        Button { player.toggle(url: item.url) } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.teal)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: player.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Slider(value: $player.volume, in: 0...1)
                            .frame(width: 140)
                            .onChange(of: player.volume) { _, v in player.applyVolume() }
                        Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }

                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { player.currentTime },
                                set: { player.seek(to: $0) }
                            ),
                            in: 0...(player.duration ?? 1)
                        )
                        .tint(.teal)
                        .frame(width: 340)

                        HStack {
                            Text(formatDuration(player.currentTime))
                            Spacer()
                            Text(formatDuration(player.duration ?? 0))
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 340)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 260)

            Divider()

            VStack(spacing: 0) {
                infoRow("Format", value: item.url.pathExtension.uppercased())
                infoRow("Size",   value: fileSize)
                if let dur = player.duration {
                    infoRow("Duration", value: formatDuration(dur))
                }
                infoRow("Path", value: item.url.path)
            }
            .padding(.vertical, 4)
        }
        .onDisappear { player.stop() }
    }

    private func formatDuration(_ s: Double) -> String {
        let t = Int(s); return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Font Preview

private struct FontPreviewContent: View {
    let item: ProjectItem
    @State private var customFont: NSFont? = nil

    private let previewText = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789  !@#$%^&*()"

    private var fileSize: String {
        let bytes = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                if let font = customFont {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("The quick brown fox jumps over the lazy dog")
                                .font(.custom(font.fontName, size: 22))
                                .foregroundStyle(.primary)
                                .padding(.horizontal)
                            Text(previewText)
                                .font(.custom(font.fontName, size: 14))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        }
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "textformat")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue.opacity(0.6))
                        Text("Loading font…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 220)

            Divider()

            VStack(spacing: 0) {
                if let font = customFont {
                    infoRow("Font Name", value: font.fontName)
                }
                infoRow("Format", value: item.url.pathExtension.uppercased())
                infoRow("Size",   value: fileSize)
                infoRow("Path",   value: item.url.path)
            }
            .padding(.vertical, 4)
        }
        .onAppear { loadFont() }
    }

    private func loadFont() {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(item.url as CFURL, .process, &error)
            if let provider = CGDataProvider(url: item.url as CFURL),
               let cgFont = CGFont(provider),
               let psName = cgFont.postScriptName as String? {
                let font = NSFont(name: psName, size: 16)
                DispatchQueue.main.async { customFont = font }
            }
        }
    }
}

// MARK: - Shared info row

private func infoRow(_ label: String, value: String) -> some View {
    HStack {
        Text(label)
            .font(.caption).foregroundStyle(.secondary)
            .frame(width: 90, alignment: .trailing)
        Text(value)
            .font(.caption.monospaced())
            .foregroundStyle(.primary)
            .lineLimit(1).truncationMode(.middle)
        Spacer()
    }
    .padding(.horizontal, 16).padding(.vertical, 5)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
}

// MARK: - Checkerboard

private struct SheetCheckerboardView: NSViewRepresentable {
    func makeNSView(context: Context) -> SheetCheckerNSView { SheetCheckerNSView() }
    func updateNSView(_ nsView: SheetCheckerNSView, context: Context) {}
}

private class SheetCheckerNSView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let size: CGFloat = 12
        let light = NSColor(white: 0.85, alpha: 1)
        let dark  = NSColor(white: 0.70, alpha: 1)
        for col in 0..<Int(ceil(bounds.width / size)) {
            for row in 0..<Int(ceil(bounds.height / size)) {
                ((col + row) % 2 == 0 ? light : dark).setFill()
                NSRect(x: CGFloat(col) * size, y: CGFloat(row) * size, width: size, height: size).fill()
            }
        }
    }
}

// MARK: - Audio Player

private class SheetAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying   = false
    @Published var duration:  Double? = nil
    @Published var currentTime: Double = 0
    @Published var volume:      Double = 0.8

    private var player: AVAudioPlayer?
    private var timer:  AnyCancellable?

    func toggle(url: URL) { isPlaying ? pause() : play(url: url) }

    func play(url: URL) {
        if player == nil {
            guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
            p.delegate = self; p.prepareToPlay(); p.volume = Float(volume)
            player = p; duration = p.duration
        }
        player?.play(); isPlaying = true; startTimer()
    }

    func pause() { player?.pause(); isPlaying = false; timer?.cancel() }

    func stop() {
        player?.stop(); player = nil
        isPlaying = false; currentTime = 0; timer?.cancel()
    }

    func seek(to time: Double) { player?.currentTime = time; currentTime = time }
    func applyVolume() { player?.volume = Float(volume) }

    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
            }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false; self.currentTime = 0
            self.player?.currentTime = 0; self.timer?.cancel()
        }
    }
}

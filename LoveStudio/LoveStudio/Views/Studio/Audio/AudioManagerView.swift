import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Accelerate

// MARK: - Waveform loader

/// Reads PCM samples from an audio file and returns a normalised [0,1] amplitude
/// array of `targetSamples` buckets. Runs off the main thread.
private func loadWaveform(url: URL, targetSamples: Int) -> [Float] {
    guard let file = try? AVAudioFile(forReading: url) else { return [] }

    // Use the file's own processing format - guarantees read() succeeds.
    let fmt        = file.processingFormat
    // Cap at 10 M frames so we don't OOM on very long tracks.
    let frameCount = AVAudioFrameCount(min(file.length, 10_000_000))
    guard frameCount > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount),
          (try? file.read(into: buffer)) != nil,
          let channelData = buffer.floatChannelData
    else { return [] }

    let total    = Int(buffer.frameLength)
    let channels = Int(fmt.channelCount)
    let bucketSz = max(1, total / targetSamples)
    var result   = [Float](repeating: 0, count: targetSamples)

    for i in 0 ..< targetSamples {
        let start = i * bucketSz
        let end   = min(start + bucketSz, total)
        guard end > start else { break }
        // Average RMS across all channels (handles mono & stereo alike)
        var rmsSum: Float = 0
        for ch in 0 ..< channels {
            var rms: Float = 0
            vDSP_rmsqv(channelData[ch] + start, 1, &rms, vDSP_Length(end - start))
            rmsSum += rms
        }
        result[i] = rmsSum / Float(channels)
    }

    // Normalise to 0–1
    var maxVal = result.max() ?? 1
    if maxVal < 1e-6 { maxVal = 1 }
    vDSP_vsdiv(result, 1, &maxVal, &result, 1, vDSP_Length(result.count))
    return result
}

// MARK: - Waveform view (SwiftUI Canvas)

private struct WaveformView: View {
    let samples:     [Float]
    let progress:    Double   // 0–1 playhead position
    let accentColor: Color

    var body: some View {
        Canvas { ctx, size in
            guard !samples.isEmpty else { return }

            let barW  = size.width / CGFloat(samples.count)
            let midY  = size.height / 2
            let playX = size.width * CGFloat(progress)

            for (i, amp) in samples.enumerated() {
                let x    = CGFloat(i) * barW
                let h    = max(1, CGFloat(amp) * size.height * 0.9)
                let rect = CGRect(x: x, y: midY - h / 2, width: max(1, barW - 0.5), height: h)

                // Played portion = accent color, unplayed = dimmed
                let color = x < playX ? accentColor : accentColor.opacity(0.25)
                ctx.fill(Path(rect), with: .color(color))
            }

            // Playhead line
            if progress > 0 && progress < 1 {
                var line = Path()
                line.move(to:    CGPoint(x: playX, y: 0))
                line.addLine(to: CGPoint(x: playX, y: size.height))
                ctx.stroke(line, with: .color(.white.opacity(0.8)), lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Audio player helper (AVFoundation preview)

@Observable
final class AudioPreviewPlayer {

    // MARK: - Public state
    private(set) var isPlaying        = false
    private(set) var playingPath      = ""
    private(set) var currentTime:     Double = 0
    private(set) var duration:        Double = 0
    private(set) var activeEffectName = ""

    var progress: Double {
        get { duration > 0 ? currentTime / duration : 0 }
        set { seek(to: newValue * duration) }
    }

    // MARK: - Graph
    // playerNode → varispeedNode → [effectNode?] → mainMixerNode → output
    // AVAudioUnitVarispeed changes both pitch AND speed together - same as LÖVE2D source:setPitch()
    private let engine          = AVAudioEngine()
    private let playerNode      = AVAudioPlayerNode()
    private let pitchNode       = AVAudioUnitVarispeed()
    private var effectNode: AVAudioUnit? = nil
    var pendingEffect:      AudioEffect? = nil

    // MARK: - State
    private var audioFile:   AVAudioFile? = nil
    private var ticker:      Timer?       = nil
    private var generation   = 0   // incremented on every schedule; stale completions ignored
    // currentTime tracking for seek
    private var seekOffset:  Double = 0   // the time we seeked to
    private var nodeTimeAtSeek: AVAudioTime? = nil  // node render time at seek moment

    init() {
        engine.attach(playerNode)
        engine.attach(pitchNode)
    }

    // MARK: - Play

    func play(fileURL: URL) {
        fullStop()

        guard let file = try? AVAudioFile(forReading: fileURL) else { return }
        audioFile   = file
        duration    = Double(file.length) / file.processingFormat.sampleRate
        currentTime = 0
        seekOffset  = 0
        playingPath = fileURL.path

        buildGraph(format: file.processingFormat)
        guard (try? engine.start()) != nil else { return }

        scheduleFromStart(file: file)
        playerNode.play()
        isPlaying = true
        startTicker()
    }

    // MARK: - Stop  (play/stop button)

    func stop() {
        fullStop()
    }

    // MARK: - Dismiss cleanup (onDisappear - swallowed if called during seek)

    func stopOnDismiss() {
        fullStop()
    }

    // MARK: - Volume / Pitch

    func applyVolume(_ v: Double) {
        playerNode.volume = Float(max(0, min(1, v)))
    }

    func applyPitch(_ p: Double) {
        // Varispeed.rate == LÖVE2D source:setPitch() - 1.0 = normal, 2.0 = double speed+pitch
        pitchNode.rate = Float(max(0.25, min(4.0, p)))
    }

    // MARK: - Seek
    // Rule: NEVER stop the engine. Only stop/restart the playerNode.

    func seek(to time: Double) {
        guard let file = audioFile, isPlaying else { return }
        let t        = max(0, min(time, duration))
        let framePos = AVAudioFramePosition(t * file.processingFormat.sampleRate)
        let left     = AVAudioFrameCount(max(0, file.length - framePos))
        guard left > 0 else { fullStop(); return }

        generation += 1
        let gen = generation
        seekOffset       = t
        nodeTimeAtSeek   = playerNode.lastRenderTime

        // Stop node only (engine keeps running)
        playerNode.stop()
        playerNode.scheduleSegment(
            file,
            startingFrame: framePos,
            frameCount:    left,
            at:            nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.generation == gen else { return }
                self?.fullStop()
            }
        }
        playerNode.play()
        currentTime = t
    }

    // MARK: - Effect hot-swap (requires engine restart to rebuild graph)

    func applyEffect(_ fx: AudioEffect?) {
        pendingEffect = fx
        guard isPlaying, let file = audioFile else { return }

        let savedTime = currentTime
        playerNode.stop()
        engine.stop()

        buildGraph(format: file.processingFormat)
        guard (try? engine.start()) != nil else { fullStop(); return }

        let framePos = AVAudioFramePosition(savedTime * file.processingFormat.sampleRate)
        let left     = AVAudioFrameCount(max(0, file.length - framePos))
        guard left > 0 else { fullStop(); return }

        generation += 1
        let gen = generation
        seekOffset = savedTime

        playerNode.scheduleSegment(
            file,
            startingFrame: framePos,
            frameCount:    left,
            at:            nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.generation == gen else { return }
                self?.fullStop()
            }
        }
        playerNode.play()
    }

    // MARK: - Private

    private func scheduleFromStart(file: AVAudioFile) {
        generation += 1
        let gen = generation
        file.framePosition = 0
        playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.generation == gen else { return }
                self?.fullStop()
            }
        }
    }

    private func fullStop() {
        ticker?.invalidate(); ticker = nil
        generation += 1        // invalidate any pending callbacks
        playerNode.stop()
        if engine.isRunning { engine.stop() }
        isPlaying   = false
        currentTime = 0
        duration    = 0
        seekOffset  = 0
    }

    private func buildGraph(format: AVAudioFormat) {
        if let old = effectNode {
            engine.disconnectNodeOutput(old)
            engine.detach(old)
            effectNode       = nil
            activeEffectName = ""
        }
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(pitchNode)

        if let fx = pendingEffect, let unit = makeAVUnit(for: fx) {
            engine.attach(unit)
            engine.connect(playerNode, to: pitchNode,            format: format)
            engine.connect(pitchNode,  to: unit,                 format: format)
            engine.connect(unit,       to: engine.mainMixerNode, format: format)
            effectNode       = unit
            activeEffectName = fx.name
        } else {
            engine.connect(playerNode, to: pitchNode,            format: format)
            engine.connect(pitchNode,  to: engine.mainMixerNode, format: format)
            activeEffectName = ""
        }
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            // Use seekOffset + elapsed-since-seek for accurate position after seek
            guard let nodeTime   = self.playerNode.lastRenderTime,
                  let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime)
            else { return }
            let elapsedSinceSeek = Double(playerTime.sampleTime) / playerTime.sampleRate
            let t = min(self.duration, max(0, self.seekOffset + elapsedSinceSeek))
            self.currentTime = t
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    // MARK: - AVAudioUnit factory

    private func makeAVUnit(for fx: AudioEffect) -> AVAudioUnit? {
        let p = fx.params
        switch fx.type {
        case .reverb:
            let u = AVAudioUnitReverb()
            u.loadFactoryPreset(.largeChamber)
            u.wetDryMix = max(0, min(100, Float(min(1.0, p.decayTime / 10.0) * p.diffusion * p.density * 100)))
            return u
        case .lowpass:
            let u = AVAudioUnitEQ(numberOfBands: 1)
            u.bands[0].filterType = .lowPass
            u.bands[0].frequency  = max(20, min(20_000, Float(200.0 * pow(100.0, p.highGain))))
            u.bands[0].bypass     = false
            return u
        case .highpass:
            let u = AVAudioUnitEQ(numberOfBands: 1)
            u.bands[0].filterType = .highPass
            u.bands[0].frequency  = max(20, min(20_000, Float(20.0 * pow(400.0, p.lowGain))))
            u.bands[0].bypass     = false
            return u
        case .echo:
            let u = AVAudioUnitDelay()
            u.delayTime = p.delay
            u.feedback  = Float(p.feedback * 100)
            u.wetDryMix = Float(p.volume * 50)
            return u
        case .chorus:
            let u = AVAudioUnitDistortion()
            u.loadFactoryPreset(.multiEcho1)
            u.wetDryMix = Float(p.depth * 30)
            return u
        }
    }
}

// MARK: - Audio Manager View

// MARK: - Left-panel selection

private enum LeftSelection: Equatable {
    case source(AudioEntry.ID)
    case effect(AudioEffect.ID)
}

struct AudioManagerView: View {
    let projectURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var config      = AudioManagerConfig()
    @State private var leftSel: LeftSelection? = nil
    @State private var saveStatus  = ""
    @State private var searchText  = ""
    @State private var savedConfigs: [AudioManagerConfig] = []

    @State private var player = AudioPreviewPlayer()
    @State private var waveformSamples: [Float] = []
    @State private var waveformPath: String = ""
    @State private var isDragOver = false

    // Derived convenience
    private var selected: AudioEntry.ID? {
        if case .source(let id) = leftSel { return id }
        return nil
    }
    private var selectedEntry: Binding<AudioEntry>? {
        guard case .source(let id) = leftSel,
              let idx = config.entries.firstIndex(where: { $0.id == id })
        else { return nil }
        return $config.entries[idx]
    }
    private var selectedEffect: Binding<AudioEffect>? {
        guard case .effect(let id) = leftSel,
              let idx = config.effects.firstIndex(where: { $0.id == id })
        else { return nil }
        return $config.effects[idx]
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            HStack(spacing: 0) {
                leftColumn
                Divider()
                rightArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            globalVolumesBar
        }
        .frame(minWidth: 740, minHeight: 500)
        .onAppear {
            savedConfigs = AudioStore.loadAll(from: projectURL)
            if let first = savedConfigs.first { config = first }
        }
        .onDisappear { player.stopOnDismiss() }
    }

    @ViewBuilder
    private var rightArea: some View {
        if let entry = selectedEntry {
            rightColumn(entry: entry)
        } else if let effect = selectedEffect {
            effectColumn(effect: effect)
        } else {
            emptyState
        }
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform").foregroundStyle(.teal)
            Text("Audio Manager").font(.headline)

            Spacer()

            if !saveStatus.isEmpty {
                Text(saveStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            // Save
            Button {
                do {
                    try AudioStore.save(config, to: projectURL)
                    savedConfigs = AudioStore.loadAll(from: projectURL)
                    flash("Saved")
                } catch {
                    flash("Save failed: \(error.localizedDescription)")
                }
            } label: {
                Label("Save", systemImage: "tray.and.arrow.up")
                    .font(.system(size: 12))
            }

            // Export Lua
            Button {
                let code = AudioCodeGenerator.generate(config: config)
                do {
                    let url = try AudioStore.exportLua(code, managerName: config.managerName, to: projectURL)
                    flash("Exported → \(url.lastPathComponent)")
                } catch {
                    flash("Export failed: \(error.localizedDescription)")
                }
            } label: {
                Label("Export Lua", systemImage: "arrow.up.doc")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Left column - sources + effects

    private var leftColumn: some View {
        VStack(spacing: 0) {

            // ── SOURCES ───────────────────────────────────────────────────────
            HStack {
                Text("SOURCES").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(config.entries.count)").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            TextField("Search…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            List(selection: Binding(
                get: { selected },
                set: { newID in
                    if let id = newID { leftSel = .source(id) } else { leftSel = nil }
                }
            )) {
                let filtered = config.entries.filter {
                    searchText.isEmpty
                    || $0.name.localizedCaseInsensitiveContains(searchText)
                    || URL(fileURLWithPath: $0.filePath).lastPathComponent.localizedCaseInsensitiveContains(searchText)
                }
                ForEach(filtered) { entry in
                    if let idx = config.entries.firstIndex(where: { $0.id == entry.id }) {
                        AudioEntryRow(entry: config.entries[idx], isPlaying: player.isPlaying && player.playingPath.hasSuffix(entry.filePath), projectURL: projectURL)
                            .tag(entry.id)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                }
                .onMove { from, to in
                    config.entries.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { idx in
                    if let sel = selected,
                       idx.contains(config.entries.firstIndex(where: { $0.id == sel }) ?? -1) {
                        leftSel = nil
                    }
                    config.entries.remove(atOffsets: idx)
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if isDragOver {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.teal, lineWidth: 2)
                        .background(Color.teal.opacity(0.07).clipShape(RoundedRectangle(cornerRadius: 6)))
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "waveform.badge.plus")
                                    .font(.system(size: 22)).foregroundStyle(.teal)
                                Text("Drop audio files").font(.caption).foregroundStyle(.teal)
                            }
                        }
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers); return true
            }

            // Sources toolbar
            HStack(spacing: 4) {
                Button {
                    let entry = AudioEntry(name: "sound_\(config.entries.count + 1)")
                    config.entries.append(entry)
                    leftSel = .source(entry.id)
                } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).padding(6)

                Button {
                    duplicateSelected()
                } label: { Image(systemName: "plus.square.on.square") }
                .buttonStyle(.plain).padding(6)
                .disabled(selected == nil)

                Button {
                    guard case .source(let id) = leftSel,
                          let idx = config.entries.firstIndex(where: { $0.id == id })
                    else { return }
                    config.entries.remove(at: idx)
                    leftSel = nil
                } label: { Image(systemName: "minus") }
                .buttonStyle(.plain).padding(6)
                .disabled(selected == nil)

                Spacer()

                Button {
                    guard case .source(let id) = leftSel,
                          let idx = config.entries.firstIndex(where: { $0.id == id }), idx > 0
                    else { return }
                    config.entries.swapAt(idx, idx - 1)
                } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain).padding(6).disabled(selected == nil)

                Button {
                    guard case .source(let id) = leftSel,
                          let idx = config.entries.firstIndex(where: { $0.id == id }),
                          idx < config.entries.count - 1
                    else { return }
                    config.entries.swapAt(idx, idx + 1)
                } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain).padding(6).disabled(selected == nil)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)

            Divider()

            // ── EFFECTS ───────────────────────────────────────────────────────
            HStack {
                Text("EFFECTS").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Text("\(config.effects.count)").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)

            List(selection: Binding(
                get: { selectedEffect.map { $0.wrappedValue.id } },
                set: { newID in
                    if let id = newID { leftSel = .effect(id) } else { leftSel = nil }
                }
            )) {
                ForEach($config.effects) { $fx in
                    AudioEffectRow(effect: fx)
                        .tag(fx.id)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .onDelete { idx in
                    if case .effect(let id) = leftSel,
                       idx.contains(config.effects.firstIndex(where: { $0.id == id }) ?? -1) {
                        leftSel = nil
                    }
                    config.effects.remove(atOffsets: idx)
                }
            }
            .listStyle(.sidebar)
            .frame(minHeight: 80, maxHeight: 200)

            // Effects toolbar
            HStack(spacing: 4) {
                Menu {
                    ForEach(AudioEffectType.allCases) { t in
                        Button {
                            let fx = AudioEffect(
                                name: t.rawValue + "_\(config.effects.count + 1)",
                                type: t
                            )
                            config.effects.append(fx)
                            leftSel = .effect(fx.id)
                        } label: {
                            Label(t.displayName, systemImage: t.sfSymbol)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .padding(6)

                Button {
                    guard case .effect(let id) = leftSel,
                          let idx = config.effects.firstIndex(where: { $0.id == id })
                    else { return }
                    config.effects.remove(at: idx)
                    leftSel = nil
                } label: { Image(systemName: "minus") }
                .buttonStyle(.plain).padding(6)
                .disabled({ if case .effect = leftSel { return false }; return true }())

                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .frame(width: 230)
    }

    // MARK: - Right column - entry config

    @ViewBuilder
    private func rightColumn(entry: Binding<AudioEntry>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                entryHeader(entry: entry)
                Divider().padding(.vertical, 8)
                fileSection(entry: entry)
                Divider().padding(.vertical, 8)
                sourceTypeSection(entry: entry)
                Divider().padding(.vertical, 8)
                volumePitchSection(entry: entry)
                Divider().padding(.vertical, 8)
                optionsSection(entry: entry)
                Divider().padding(.vertical, 8)
                variationSection(entry: entry)
                Divider().padding(.vertical, 8)
                fadeSection(entry: entry)
                Divider().padding(.vertical, 8)
                spatialSection(entry: entry)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func entryHeader(entry: Binding<AudioEntry>) -> some View {
        let fileURL    = projectURL.appendingPathComponent(entry.wrappedValue.filePath)
        let canPreview = !entry.wrappedValue.filePath.isEmpty
            && FileManager.default.fileExists(atPath: fileURL.path)
        let isActive   = player.isPlaying && player.playingPath == fileURL.path

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(groupColor(entry.wrappedValue.group).opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: entry.wrappedValue.group.sfSymbol)
                            .foregroundStyle(groupColor(entry.wrappedValue.group))
                    }

                VStack(alignment: .leading, spacing: 2) {
                    TextField("Name", text: entry.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                    Text("Lua key: \(luaIdent(entry.wrappedValue.name))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Play / Stop button
                Button {
                    if isActive {
                        player.stop()
                    } else {
                        // Set effect BEFORE play() so graph is built correctly on first start
                        let fxName = entry.wrappedValue.effectName
                        let fx = fxName.isEmpty ? nil : config.effects.first(where: { $0.name == fxName && $0.enabled })
                        player.pendingEffect = fx
                        player.play(fileURL: fileURL)
                        applyEffectiveVolume()
                        player.applyPitch(entry.wrappedValue.pitch)
                    }
                } label: {
                    Image(systemName: isActive ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canPreview ? .teal : .secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(!canPreview)
                .help(canPreview ? (isActive ? "Stop preview" : "Preview audio") : "File not found on disk")

                // Play with variation button
                if (entry.wrappedValue.pitchVariation > 0 || entry.wrappedValue.volumeVariation > 0) && canPreview {
                    Button {
                        let pv = entry.wrappedValue.pitchVariation
                        let vv = entry.wrappedValue.volumeVariation
                        let fxName = entry.wrappedValue.effectName
                        let fx = fxName.isEmpty ? nil : config.effects.first(where: { $0.name == fxName && $0.enabled })
                        player.pendingEffect = fx
                        player.play(fileURL: fileURL)
                        // Apply volume variation
                        if vv > 0 {
                            let variedVol = max(0, min(1, entry.wrappedValue.volume * (1.0 + Double.random(in: -vv...vv))))
                            player.applyVolume(variedVol)
                        } else {
                            applyEffectiveVolume()
                        }
                        // Apply pitch variation
                        let variedPitch = entry.wrappedValue.pitch * (1.0 + Double.random(in: -pv...pv))
                        player.applyPitch(max(0.25, min(4.0, variedPitch)))
                    } label: {
                        Image(systemName: "dice")
                            .font(.system(size: 22))
                            .foregroundStyle(.orange)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .help("Play with random variation applied")
                }
            }

            // Waveform + seek - visible whenever a file is loaded (playing or stopped)
            if canPreview {
                VStack(spacing: 4) {
                    // Waveform canvas - tap/drag to seek
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .textBackgroundColor))

                            if waveformSamples.isEmpty || waveformPath != fileURL.path {
                                // Loading placeholder
                                HStack {
                                    Spacer()
                                    ProgressView().controlSize(.small)
                                    Spacer()
                                }
                            } else {
                                WaveformView(
                                    samples:     waveformSamples,
                                    progress:    isActive ? player.progress : 0,
                                    accentColor: groupColor(entry.wrappedValue.group)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { val in
                                        let p = val.location.x / geo.size.width
                                        if isActive { player.progress = max(0, min(1, Double(p))) }
                                    }
                                )
                            }
                        }
                    }
                    .frame(height: 44)
                    .onAppear  { loadWaveformIfNeeded(url: fileURL) }
                    .onChange(of: entry.wrappedValue.filePath) { _, _ in
                        loadWaveformIfNeeded(url: fileURL)
                    }
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        providers.first?.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                            guard let data = data,
                                  let url = URL(dataRepresentation: data, relativeTo: nil)
                            else { return }
                            DispatchQueue.main.async {
                                let rel: String
                                if url.path.hasPrefix(projectURL.path + "/") {
                                    rel = String(url.path.dropFirst(projectURL.path.count + 1))
                                } else {
                                    guard let r = try? importAudioFile(url) else { return }
                                    rel = r
                                }
                                entry.filePath.wrappedValue = rel
                                waveformSamples = []
                                waveformPath    = ""
                                loadWaveformIfNeeded(url: projectURL.appendingPathComponent(rel))
                            }
                        }
                        return true
                    }

                    // Time labels + active effect badge
                    HStack {
                        Text(isActive ? formatTime(player.currentTime) : "0:00")
                        Spacer()
                        if isActive && !player.activeEffectName.isEmpty {
                            Label(player.activeEffectName, systemImage: "waveform.path.ecg")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Color.purple.opacity(0.15)))
                        }
                        Spacer()
                        Text(isActive ? formatTime(player.duration) : formatTime(fileDuration(fileURL)))
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                    // Approximate preview note
                    if isActive && !player.activeEffectName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                            Text("Preview is approximate - final sound depends on LÖVE2D's OpenAL engine.")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)
                        .transition(.opacity)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: canPreview)
    }

    // File picker
    private func fileSection(entry: Binding<AudioEntry>) -> some View {
        SectionCard(title: "FILE", icon: "folder") {
            HStack(spacing: 8) {
                TextField("sounds/example.wav", text: entry.filePath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .textBackgroundColor)))

                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = audioTypes
                    panel.directoryURL = projectURL
                    panel.canChooseFiles       = true
                    panel.canChooseDirectories = false
                    guard panel.runModal() == .OK, let url = panel.url else { return }

                    if url.path.hasPrefix(projectURL.path + "/") {
                        entry.filePath.wrappedValue = String(url.path.dropFirst(projectURL.path.count + 1))
                    } else {
                        do {
                            let rel = try importAudioFile(url)
                            entry.filePath.wrappedValue = rel
                            flash("Copied → \(rel)")
                        } catch {
                            flash("Copy failed: \(error.localizedDescription)")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12))
            }

            // File status indicator
            let fileURL = projectURL.appendingPathComponent(entry.wrappedValue.filePath)
            let exists  = !entry.wrappedValue.filePath.isEmpty
                && FileManager.default.fileExists(atPath: fileURL.path)
            HStack(spacing: 4) {
                Circle()
                    .fill(exists ? Color.green : (entry.wrappedValue.filePath.isEmpty ? Color.secondary : Color.red))
                    .frame(width: 6, height: 6)
                Text(exists ? "File found" : (entry.wrappedValue.filePath.isEmpty ? "No file selected" : "File not found"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    // Source type + group
    private func sourceTypeSection(entry: Binding<AudioEntry>) -> some View {
        SectionCard(title: "SOURCE TYPE & GROUP", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type").font(.caption).foregroundStyle(.secondary)
                    Picker("Type", selection: entry.sourceType) {
                        ForEach(AudioSourceType.allCases) { t in
                            Label(t.displayName, systemImage: t.sfSymbol).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(entry.wrappedValue.sourceType == .static
                         ? "Loaded fully - ideal for short SFX (< 1 MB)"
                         : "Decoded on-the-fly - ideal for music / long clips")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Group").font(.caption).foregroundStyle(.secondary)
                    Picker("Group", selection: entry.group) {
                        ForEach(AudioGroup.allCases) { g in
                            Label(g.displayName, systemImage: g.sfSymbol).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
    }

    // Volume + pitch
    private func volumePitchSection(entry: Binding<AudioEntry>) -> some View {
        let fileURL  = projectURL.appendingPathComponent(entry.wrappedValue.filePath)
        let isActive = player.isPlaying && player.playingPath == fileURL.path

        return SectionCard(title: "VOLUME & PITCH", icon: "speaker.wave.2") {
            VStack(spacing: 10) {
                LabeledSlider(
                    label: "Volume",
                    value: entry.volume,
                    range: 0...1,
                    format: { String(format: "%.0f%%", $0 * 100) }
                )
                .onChange(of: entry.wrappedValue.volume) { _, _ in
                    if isActive { applyEffectiveVolume() }
                }

                LabeledSlider(
                    label: "Pitch",
                    value: entry.pitch,
                    range: 0.25...4.0,
                    format: { String(format: "×%.2f", $0) }
                )
                .onChange(of: entry.wrappedValue.pitch) { _, p in
                    if isActive { player.applyPitch(p) }
                }
            }
        }
    }

    // Loop + effect options
    private func optionsSection(entry: Binding<AudioEntry>) -> some View {
        SectionCard(title: "OPTIONS", icon: "gearshape") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Loop", isOn: entry.looping)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Divider()

                // Effect assignment
                VStack(alignment: .leading, spacing: 6) {
                    Text("Audio Effect").font(.caption).foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Picker("", selection: entry.effectName) {
                            Text("None").tag("")
                            ForEach(config.effects.filter { $0.enabled }) { fx in
                                Label(fx.name, systemImage: fx.type.sfSymbol)
                                    .tag(fx.name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                        if !entry.wrappedValue.effectName.isEmpty {
                            Button {
                                entry.effectName.wrappedValue = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if config.effects.isEmpty {
                        Text("No effects defined - add one in the Effects panel")
                            .font(.caption2).foregroundStyle(.tertiary)
                    } else if !entry.wrappedValue.effectName.isEmpty,
                              let fx = config.effects.first(where: { $0.name == entry.wrappedValue.effectName }) {
                        Label(fx.type.description, systemImage: "info.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // VARIATION section
    private func variationSection(entry: Binding<AudioEntry>) -> some View {
        let fileURL2  = projectURL.appendingPathComponent(entry.wrappedValue.filePath)
        let isActive2 = player.isPlaying && player.playingPath == fileURL2.path

        return SectionCard(title: "VARIATION", icon: "dice") {
            LabeledSlider(label: "Pitch ±",  value: entry.pitchVariation,  range: 0...0.5,
                          format: { String(format: "%.0f%%", $0 * 100) })
            .onChange(of: entry.wrappedValue.pitchVariation) { _, pv in
                guard isActive2 else { return }
                let base   = entry.wrappedValue.pitch
                let varied = base * (1.0 + Double.random(in: -pv...pv))
                player.applyPitch(max(0.25, min(4.0, varied)))
            }

            LabeledSlider(label: "Volume ±", value: entry.volumeVariation, range: 0...0.5,
                          format: { String(format: "%.0f%%", $0 * 100) })
            .onChange(of: entry.wrappedValue.volumeVariation) { _, vv in
                guard isActive2 else { return }
                let varied = max(0, min(1, entry.wrappedValue.volume
                                        * (1.0 + Double.random(in: -vv...vv))))
                player.applyVolume(varied)
            }

            Text("Sliders apply a random sample to the preview while playing")
                .font(.caption2).foregroundStyle(.tertiary)

            Divider()

            HStack {
                Text("Max instances").font(.system(size: 12))
                Spacer()
                Stepper(entry.maxInstances.wrappedValue == 0
                        ? "Unlimited"
                        : "\(entry.maxInstances.wrappedValue)",
                        value: entry.maxInstances, in: 0...16)
                    .labelsHidden()
                Text(entry.maxInstances.wrappedValue == 0 ? "∞" : "\(entry.maxInstances.wrappedValue)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
            Text("Max simultaneous copies of this source (0 = unlimited)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // FADE section
    private func fadeSection(entry: Binding<AudioEntry>) -> some View {
        SectionCard(title: "FADE", icon: "water.waves") {
            LabeledSlider(label: "Fade in",  value: entry.fadeInDuration,  range: 0...5,
                          format: { $0 == 0 ? "off" : String(format: "%.1fs", $0) })
            LabeledSlider(label: "Fade out", value: entry.fadeOutDuration, range: 0...5,
                          format: { $0 == 0 ? "off" : String(format: "%.1fs", $0) })
            Text("Call Audio:update(dt) in love.update for fades to work")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // SPATIAL section
    private func spatialSection(entry: Binding<AudioEntry>) -> some View {
        SectionCard(title: "SPATIAL AUDIO", icon: "dot.radiowaves.left.and.right") {
            Toggle("Enable spatial audio", isOn: entry.spatial)
                .toggleStyle(.switch).controlSize(.small)

            if entry.wrappedValue.spatial {
                Divider()
                LabeledSlider(label: "Min dist", value: entry.minDistance, range: 10...500,
                              format: { String(format: "%.0fpx", $0) })
                LabeledSlider(label: "Max dist", value: entry.maxDistance, range: 50...2000,
                              format: { String(format: "%.0fpx", $0) })
                LabeledSlider(label: "Rolloff",  value: entry.rolloff,     range: 0...5,
                              format: { String(format: "%.1f", $0) })
                Text("Call Audio:play(\"name\", x, y) and Audio:setListenerPosition(lx, ly)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Effect column

    @ViewBuilder
    private func effectColumn(effect: Binding<AudioEffect>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: effect.wrappedValue.type.sfSymbol)
                                .foregroundStyle(.purple)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Effect name", text: effect.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .semibold))
                        Text(effect.wrappedValue.type.displayName)
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: effect.enabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("Enable / disable this effect")
                }

                Divider().padding(.vertical, 10)

                // Type picker
                SectionCard(title: "EFFECT TYPE", icon: "waveform.path.ecg") {
                    Picker("Type", selection: effect.type) {
                        ForEach(AudioEffectType.allCases) { t in
                            Label(t.displayName, systemImage: t.sfSymbol).tag(t)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    Text(effect.wrappedValue.type.description)
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                Divider().padding(.vertical, 10)

                // Parameters - live-update preview while playing
                SectionCard(title: "PARAMETERS", icon: "slider.horizontal.3") {
                    effectParamsSection(effect: effect)
                        .onChange(of: effect.wrappedValue.params) { _, _ in
                            reapplyEffectIfPlaying(effect.wrappedValue)
                        }
                        .onChange(of: effect.wrappedValue.type) { _, _ in
                            reapplyEffectIfPlaying(effect.wrappedValue)
                        }
                }

                Divider().padding(.vertical, 10)

                // Assigned sources
                let assigned = config.entries.filter { $0.effectName == effect.wrappedValue.name }
                if !assigned.isEmpty {
                    SectionCard(title: "ASSIGNED SOURCES", icon: "speaker.wave.2") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(assigned) { e in
                                HStack(spacing: 6) {
                                    Image(systemName: e.group.sfSymbol)
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Text(e.name).font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func effectParamsSection(effect: Binding<AudioEffect>) -> some View {
        let p = effect.params

        VStack(spacing: 10) {
            LabeledSlider(label: "Volume", value: p.volume, range: 0...1,
                          format: { String(format: "%.0f%%", $0 * 100) })

            Divider()

            switch effect.wrappedValue.type {
            case .reverb:
                LabeledSlider(label: "Decay", value: p.decayTime, range: 0.1...20,
                              format: { String(format: "%.1fs", $0) })
                LabeledSlider(label: "Density", value: p.density, range: 0...1,
                              format: { String(format: "%.2f", $0) })
                LabeledSlider(label: "Diffusion", value: p.diffusion, range: 0...1,
                              format: { String(format: "%.2f", $0) })

            case .lowpass:
                LabeledSlider(label: "High gain", value: p.highGain, range: 0...1,
                              format: { String(format: "%.2f", $0) })
                Text("0 = fully muffled · 1 = unfiltered")
                    .font(.caption2).foregroundStyle(.tertiary)

            case .highpass:
                LabeledSlider(label: "Low gain", value: p.lowGain, range: 0...1,
                              format: { String(format: "%.2f", $0) })
                Text("0 = no bass · 1 = unfiltered")
                    .font(.caption2).foregroundStyle(.tertiary)

            case .echo:
                LabeledSlider(label: "Delay", value: p.delay, range: 0...0.5,
                              format: { String(format: "%.3fs", $0) })
                LabeledSlider(label: "Feedback", value: p.feedback, range: 0...1,
                              format: { String(format: "%.2f", $0) })
                LabeledSlider(label: "Spread", value: p.spread, range: 0...1,
                              format: { String(format: "%.2f", $0) })
                Text("Spread: stereo widening for the delay tail")
                    .font(.caption2).foregroundStyle(.tertiary)

            case .chorus:
                LabeledSlider(label: "Delay", value: p.delay, range: 0...0.016,
                              format: { String(format: "%.4fs", $0) })
                LabeledSlider(label: "Feedback", value: p.feedback, range: 0...1,
                              format: { String(format: "%.2f", $0) })
                LabeledSlider(label: "Rate", value: p.rate, range: 0...10,
                              format: { String(format: "%.1f Hz", $0) })
                LabeledSlider(label: "Depth", value: p.depth, range: 0...1,
                              format: { String(format: "%.2f", $0) })
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a source to configure it")
                .foregroundStyle(.secondary)
            Button("Add Source") {
                let entry = AudioEntry(name: "sound_\(config.entries.count + 1)")
                config.entries.append(entry)
                leftSel = .source(entry.id)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Global volumes bar

    private var globalVolumesBar: some View {
        HStack(spacing: 20) {
            Text("GLOBAL VOLUMES").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            CompactVolumeSlider(label: "Master", value: $config.masterVolume, color: .white)
                .onChange(of: config.masterVolume) { _, _ in applyEffectiveVolume() }
            CompactVolumeSlider(label: "SFX",    value: $config.sfxVolume,    color: .yellow)
                .onChange(of: config.sfxVolume)    { _, _ in applyEffectiveVolume() }
            CompactVolumeSlider(label: "Music",  value: $config.musicVolume,  color: .teal)
                .onChange(of: config.musicVolume)  { _, _ in applyEffectiveVolume() }
            CompactVolumeSlider(label: "Ambient",value: $config.ambientVolume,color: .green)
                .onChange(of: config.ambientVolume){ _, _ in applyEffectiveVolume() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Recalculates effective volume for the currently playing entry:
    /// effectiveVolume = entry.volume × groupVolume × masterVolume
    private func applyEffectiveVolume() {
        guard player.isPlaying,
              let entry = config.entries.first(where: {
                  projectURL.appendingPathComponent($0.filePath).path == player.playingPath
              })
        else { return }

        let groupVol: Double
        switch entry.group {
        case .sfx:     groupVol = config.sfxVolume
        case .music:   groupVol = config.musicVolume
        case .ambient: groupVol = config.ambientVolume
        }
        player.applyVolume(entry.volume * groupVol * config.masterVolume)
    }

    // MARK: - Helpers

    // MARK: - Import helpers

    /// Copies an audio file into `<project>/audio/`, renaming if a file with the
    /// same name already exists: `beat.wav` → `beat_2.wav` → `beat_3.wav` …
    @discardableResult
    private func importAudioFile(_ url: URL) throws -> String {
        let audioDir = projectURL.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let base = url.deletingPathExtension().lastPathComponent
        let ext  = url.pathExtension
        var dest = audioDir.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = audioDir.appendingPathComponent("\(base)_\(counter).\(ext)")
            counter += 1
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return "audio/\(dest.lastPathComponent)"
    }

    /// Handles a multi-file drop: each audio file becomes a new AudioEntry.
    private func handleDrop(providers: [NSItemProvider]) {
        let audioExts = Set(["mp3", "ogg", "wav", "flac", "aiff", "aif", "m4a", "opus"])
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url  = URL(dataRepresentation: data, relativeTo: nil),
                      audioExts.contains(url.pathExtension.lowercased())
                else { return }

                DispatchQueue.main.async {
                    let rel: String
                    if url.path.hasPrefix(self.projectURL.path + "/") {
                        rel = String(url.path.dropFirst(self.projectURL.path.count + 1))
                    } else {
                        guard let r = try? self.importAudioFile(url) else { return }
                        rel = r
                    }

                    // Derive a clean Lua name from the file stem
                    let stem   = url.deletingPathExtension().lastPathComponent
                    let luaKey = stem
                        .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "_")).inverted)
                        .joined(separator: "_")
                        .trimmingCharacters(in: .init(charactersIn: "_"))

                    // Deduplicate entry name
                    var name    = luaKey.isEmpty ? "sound" : luaKey
                    var counter = 2
                    while self.config.entries.contains(where: { $0.name == name }) {
                        name = "\(luaKey)_\(counter)"; counter += 1
                    }

                    var entry      = AudioEntry(name: name)
                    entry.filePath = rel
                    // Auto-pick stream for large-ish files
                    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                       size > 1_000_000 {
                        entry.sourceType = .stream
                        entry.group      = .music
                    }

                    self.config.entries.append(entry)
                    self.leftSel = .source(entry.id)
                }
            }
        }
    }

    /// Waveform: load samples async if the file changed.
    private func loadWaveformIfNeeded(url: URL) {
        guard url.path != waveformPath else { return }
        waveformSamples = []
        waveformPath    = url.path
        DispatchQueue.global(qos: .utility).async {
            let samples = loadWaveform(url: url, targetSamples: 300)
            DispatchQueue.main.async {
                guard self.waveformPath == url.path else { return }
                self.waveformSamples = samples
            }
        }
    }

    /// Returns the duration of a file without playing it (used before playback).
    private func fileDuration(_ url: URL) -> Double {
        guard let asset = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(asset.length) / asset.fileFormat.sampleRate
    }

    /// Reapplies an effect to the currently playing preview if that effect is the active one.
    private func reapplyEffectIfPlaying(_ fx: AudioEffect) {
        guard player.isPlaying, player.activeEffectName == fx.name else { return }
        player.applyEffect(fx)
    }

    private func duplicateSelected() {
        guard case .source(let id) = leftSel,
              let original = config.entries.first(where: { $0.id == id })
        else { return }
        var copy = original
        copy.id = UUID()
        // Deduplicate name with _copy suffix
        var baseName = original.name + "_copy"
        var counter = 2
        while config.entries.contains(where: { $0.name == baseName }) {
            baseName = original.name + "_copy\(counter)"
            counter += 1
        }
        copy.name = baseName
        config.entries.append(copy)
        leftSel = .source(copy.id)
    }

    private func flash(_ msg: String) {
        saveStatus = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if saveStatus == msg { saveStatus = "" }
        }
    }

    private func groupColor(_ group: AudioGroup) -> Color {
        switch group {
        case .sfx:     return .yellow
        case .music:   return .teal
        case .ambient: return .green
        }
    }

    private func luaIdent(_ name: String) -> String {
        let safe = name
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "_")).inverted)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let result = safe.isEmpty ? "sound" : safe
        return result.first?.isNumber == true ? "_\(result)" : result
    }

    private func formatTime(_ t: Double) -> String {
        let total = max(0, Int(t))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var audioTypes: [UTType] {
        [.audio, UTType("public.mp3")!, .wav,
         UTType("public.ogg-vorbis")  ?? .audio,
         UTType("public.flac")        ?? .audio,
         UTType("com.microsoft.waveform-audio") ?? .wav]
            .compactMap { $0 }
    }
}

// MARK: - Audio entry row

private struct AudioEntryRow: View {
    let entry: AudioEntry
    let isPlaying: Bool
    let projectURL: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.group.sfSymbol)
                .foregroundStyle(groupColor)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name.isEmpty ? "untitled" : entry.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(entry.filePath.isEmpty ? "no file" : URL(fileURLWithPath: entry.filePath).lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !entry.filePath.isEmpty {
                    Text("\(durationString)  ·  \(sizeString)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isPlaying {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.teal)
            }

            Text(entry.sourceType == .static ? "sfx" : "str")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var fileURL: URL {
        projectURL.appendingPathComponent(entry.filePath)
    }

    private var durationString: String {
        guard let file = try? AVAudioFile(forReading: fileURL) else { return "0:00" }
        let secs = Int(Double(file.length) / file.fileFormat.sampleRate)
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    private var sizeString: String {
        guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "-" }
        if size >= 1_000_000 {
            return String(format: "%.1f MB", Double(size) / 1_000_000)
        } else {
            return "\(size / 1_000) KB"
        }
    }

    private var groupColor: Color {
        switch entry.group {
        case .sfx:     return .yellow
        case .music:   return .teal
        case .ambient: return .green
        }
    }
}

// MARK: - Audio effect row

private struct AudioEffectRow: View {
    let effect: AudioEffect

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: effect.type.sfSymbol)
                .foregroundStyle(.purple)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(effect.name.isEmpty ? "unnamed" : effect.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(effect.enabled ? .primary : .secondary)
                Text(effect.type.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !effect.enabled {
                Text("off")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Section card

private struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Labeled slider

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 52, alignment: .leading)
            Slider(value: $value, in: range)
            Text(format(value))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 46, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Compact volume slider (bottom bar)

private struct CompactVolumeSlider: View {
    let label: String
    @Binding var value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Slider(value: $value, in: 0...1)
                .tint(color)
                .frame(width: 90)
            Text(String(format: "%.0f%%", value * 100))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

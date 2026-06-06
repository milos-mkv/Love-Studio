import SwiftUI
import AppKit

// MARK: - Layout constants
private let kNodeW: CGFloat = 168
private let kNodeH: CGFloat = 56
private let kHGap:  CGFloat = 80
private let kVGap:  CGFloat = 60

// MARK: - Node Canvas

struct NodeCanvasView: View {

    @Binding var entries:    [SceneEntry]
    @Binding var selectedID: SceneEntry.ID?

    @State private var canvasSize:    CGSize = .zero
    @State private var didAutoLayout: Bool   = false

    private let space = "nodeCanvas"

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Grid
                gridLayer

                // Scene nodes
                ForEach($entries) { $entry in
                    SceneNodeView(
                        entry:      $entry,
                        isSelected: selectedID == entry.id,
                        spaceName:  space,
                        onTap: { selectedID = entry.id },
                        onMoved: { entry.nodePosition = $0 },
                        onSetInitial: {
                            for i in entries.indices { entries[i].isInitial = false }
                            if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                                entries[i].isInitial = true
                            }
                        },
                        onDelete: {
                            entries.removeAll { $0.id == entry.id }
                            if selectedID == entry.id { selectedID = nil }
                        }
                    )
                }

                // Empty state
                if entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 40)).foregroundStyle(.tertiary)
                        Text("Add scenes using the + button")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .coordinateSpace(name: space)
            .onChange(of: geo.size) { _, s in
                canvasSize = s
                if !didAutoLayout && s != .zero {
                    didAutoLayout = true
                    autoLayout(in: s)
                }
            }
            .onChange(of: entries.count) { old, new in
                guard new > old else { return }
                if let last = entries.last, last.nodePosition == .zero {
                    positionNewEntry(index: entries.count - 1, in: canvasSize)
                }
            }
        }
    }

    // MARK: - Grid

    private var gridLayer: some View {
        Canvas { ctx, size in
            let step: CGFloat = 28
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width  { path.move(to: .init(x: x, y: 0)); path.addLine(to: .init(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)); y += step }
            ctx.stroke(path, with: .color(Color.primary.opacity(0.035)), lineWidth: 0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Auto layout

    private func autoLayout(in size: CGSize) {
        let needsLayout = entries.allSatisfy { $0.nodePosition == .zero }
        guard needsLayout, !entries.isEmpty, size != .zero else { return }
        let cols = max(1, Int((size.width - 40) / (kNodeW + kHGap)))
        for (i, _) in entries.enumerated() {
            entries[i].nodePosition = CGPoint(
                x: kNodeW / 2 + 40 + CGFloat(i % cols) * (kNodeW + kHGap),
                y: kNodeH / 2 + 40 + CGFloat(i / cols) * (kNodeH + kVGap)
            )
        }
    }

    private func positionNewEntry(index: Int, in size: CGSize) {
        let cols = max(1, Int((size.width - 40) / (kNodeW + kHGap)))
        entries[index].nodePosition = CGPoint(
            x: kNodeW / 2 + 40 + CGFloat(index % cols) * (kNodeW + kHGap),
            y: kNodeH / 2 + 40 + CGFloat(index / cols) * (kNodeH + kVGap)
        )
    }
}

// MARK: - Scene Node View

private struct SceneNodeView: View {

    @Binding var entry: SceneEntry
    let isSelected:  Bool
    let spaceName:   String
    let onTap:        () -> Void
    let onMoved:      (CGPoint) -> Void
    let onSetInitial: () -> Void
    let onDelete:     () -> Void

    @State private var dragStart: CGPoint? = nil

    var body: some View {
        ZStack {
            // Card
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(isSelected ? 0.22 : 0.10),
                        radius: isSelected ? 9 : 4, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

            // Content
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(entry.isInitial ? Color.green.opacity(0.15) : Color.primary.opacity(0.07))
                        .frame(width: 32, height: 32)
                    Image(systemName: entry.isInitial ? "flag.fill" : "rectangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(entry.isInitial ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        if entry.isInitial {
                            Text("init")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(Color.green.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(entry.name)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
        }
        .frame(width: kNodeW, height: kNodeH)
        .position(entry.nodePosition)
        .onTapGesture { onTap() }
        .simultaneousGesture(
            DragGesture(coordinateSpace: .named(spaceName))
                .onChanged { v in
                    if dragStart == nil { dragStart = entry.nodePosition }
                    if let s = dragStart {
                        onMoved(CGPoint(x: s.x + v.translation.width,
                                        y: s.y + v.translation.height))
                    }
                }
                .onEnded { _ in dragStart = nil }
        )
        .contextMenu {
            Button {
                onSetInitial()
            } label: {
                Label("Set as Initial", systemImage: "flag.fill")
            }
            .disabled(entry.isInitial)
            Divider()
            Button("Delete Scene", role: .destructive) { onDelete() }
        }
    }
}

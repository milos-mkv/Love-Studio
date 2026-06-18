import SwiftUI
import AppKit

// MARK: - Root

struct GitPanelView: View {
    let git: GitStatusService
    let projectURL: URL

    var body: some View {
        if !git.isGitRepo {
            noRepoView
        } else {
            repoView
        }
    }

    // MARK: - No repo

    @State private var initStatus: String? = nil
    @State private var initRunning = false

    private var noRepoView: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Not a Git repository")
                .font(.headline)

            Text(projectURL.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let status = initStatus {
                Text(status)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(status.contains("✓") ? Color.green : Color.red)
                    .padding(.horizontal, 12)
                    .multilineTextAlignment(.center)
            } else {
                Text("Run git init from Terminal in the project folder,\nor press the button below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 10) {
                Button {
                    runGitInit()
                } label: {
                    if initRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("git init", systemImage: "plus.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(initRunning)

                Button {
                    git.refresh()
                } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Check if .git folder exists now")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runGitInit() {
        initRunning = true
        initStatus = nil
        Task {
            let (out, err) = await Task.detached(priority: .utility) {
                GitCommands.gitWithError(["init"], in: self.projectURL)
            }.value
            initRunning = false
            if let out {
                initStatus = "✓ " + out.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let detail = err?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
                initStatus = "✗ \(detail)"
            }
            try? await Task.sleep(for: .milliseconds(500))
            git.refresh()
        }
    }

    // MARK: - Repo view

    @State private var selectedTab: GitTab = .changes
    @State private var remoteActionStatus: String? = nil
    @State private var remoteActionFailed = false

    private var repoView: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(GitTab.allCases, id: \.self) { tab in
                    GitTabButton(tab: tab, isSelected: selectedTab == tab, badge: badge(for: tab)) {
                        selectedTab = tab
                    }
                }

                Spacer()

                if git.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.horizontal, 6)
                }

                Button {
                    git.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .help("Refresh")
            }
            .frame(height: 32)
            .background(.bar)

            Divider()

            HStack(spacing: 8) {
                GitToolbarPill(
                    systemImage: "arrow.triangle.branch",
                    text: git.currentBranch.isEmpty ? "No branch" : git.currentBranch
                )

                GitRemoteSummary(
                    upstreamBranch: git.upstreamBranch,
                    aheadCount: git.aheadCount,
                    behindCount: git.behindCount,
                    hasRemotes: !git.remotes.isEmpty
                )

                Spacer(minLength: 8)

                Button {
                    git.fetch(completion: handleRemoteAction)
                } label: {
                    Label("Fetch", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(git.isBusy || git.remotes.isEmpty)

                Button {
                    git.pull(completion: handleRemoteAction)
                } label: {
                    Label("Pull", systemImage: "arrow.down.backward.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(git.isBusy || git.upstreamBranch.isEmpty)

                Button {
                    if git.upstreamBranch.isEmpty {
                        git.publishCurrentBranch(completion: handleRemoteAction)
                    } else {
                        git.push(completion: handleRemoteAction)
                    }
                } label: {
                    Label(git.upstreamBranch.isEmpty ? "Publish" : "Push", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(git.isBusy || git.currentBranch.isEmpty || (git.upstreamBranch.isEmpty && git.remotes.isEmpty))
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(Color(nsColor: .controlBackgroundColor))

            if let status = remoteActionStatus {
                Divider()

                HStack {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(remoteActionFailed ? Color.red : Color.green)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minHeight: 22)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            Divider()

            // Content
            switch selectedTab {
            case .changes:  GitChangesView(git: git)
            case .history:  GitHistoryView(git: git)
            case .branches: GitBranchesView(git: git)
            }
        }
    }

    private func badge(for tab: GitTab) -> Int? {
        switch tab {
        case .changes:  let c = git.statuses.count; return c > 0 ? c : nil
        case .history:  return nil
        case .branches: return nil
        }
    }

    private func handleRemoteAction(_ ok: Bool, _ message: String) {
        let prefix = ok ? "✓" : "✗"
        remoteActionFailed = !ok
        remoteActionStatus = "\(prefix) \(message)"

        let statusSnapshot = remoteActionStatus
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if remoteActionStatus == statusSnapshot {
                remoteActionStatus = nil
                remoteActionFailed = false
            }
        }
    }
}

// MARK: - Tab

private enum GitTab: String, CaseIterable {
    case changes  = "Changes"
    case history  = "History"
    case branches = "Branches"
}

private struct GitTabButton: View {
    let tab: GitTab
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                if let b = badge {
                    Text("\(b)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.7)))
                        .foregroundStyle(.white)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

private struct GitToolbarPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.secondary.opacity(0.08)))
    }
}

private struct GitRemoteSummary: View {
    let upstreamBranch: String
    let aheadCount: Int
    let behindCount: Int
    let hasRemotes: Bool

    var body: some View {
        Group {
            if !upstreamBranch.isEmpty {
                HStack(spacing: 6) {
                    GitToolbarPill(systemImage: "point.topleft.down.curvedto.point.bottomright.up", text: upstreamBranch)

                    if aheadCount > 0 {
                        GitStateBadge(text: "↑\(aheadCount)", tint: Color.green.opacity(0.75))
                    }
                    if behindCount > 0 {
                        GitStateBadge(text: "↓\(behindCount)", tint: Color.orange.opacity(0.85))
                    }
                    if aheadCount == 0 && behindCount == 0 {
                        GitStateBadge(text: "Up to date", tint: Color.blue.opacity(0.75))
                    }
                }
            } else if hasRemotes {
                GitStateBadge(text: "No upstream", tint: Color.orange.opacity(0.85))
            } else {
                GitStateBadge(text: "No remotes", tint: Color.secondary.opacity(0.55))
            }
        }
    }
}

// MARK: - Changes tab

private struct GitChangesView: View {
    let git: GitStatusService

    @State private var selectedFile: String? = nil
    @State private var commitMessage = ""
    @State private var commitResult: String? = nil
    @State private var commitResultFailed = false

    var body: some View {
        HSplitView {
            // Left: file list + commit
            VStack(spacing: 0) {
                if git.statuses.isEmpty {
                    Text("No changes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(sortedPaths, id: \.self, selection: $selectedFile) { path in
                        GitFileRow(git: git, path: path, state: git.statuses[path]!)
                    }
                    .listStyle(.plain)
                    .onChange(of: selectedFile) { _, path in
                        if let p = path {
                            git.loadDiff(for: p)
                        } else {
                            git.clearDiff()
                        }
                    }
                }

                Divider()

                VStack(spacing: 6) {
                    if !git.conflictedPaths.isEmpty {
                        HStack(spacing: 8) {
                            let label = git.currentOperation?.displayName ?? "Conflict"
                            Text("\(label) conflicts in \(git.conflictedPaths.count) file(s)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)

                            Spacer()

                            if git.currentOperation != nil {
                                Button("Abort \(label)") {
                                    git.abortCurrentOperation(completion: handleResult)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(git.isBusy)
                            }
                        }
                    }

                    if selectedFileIsConflicted {
                        HStack(spacing: 8) {
                            Button("Accept Current") {
                                if let selectedFile {
                                    git.resolveConflict(selectedFile, using: .ours, completion: handleResult)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(selectedFile == nil || git.isBusy)

                            Button("Accept Incoming") {
                                if let selectedFile {
                                    git.resolveConflict(selectedFile, using: .theirs, completion: handleResult)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(selectedFile == nil || git.isBusy)

                            Button("Accept Both") {
                                if let selectedFile {
                                    git.resolveConflict(selectedFile, using: .both, completion: handleResult)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(selectedFile == nil || git.isBusy)

                            Button("Mark Resolved") {
                                if let selectedFile {
                                    git.resolveConflict(selectedFile, using: .markResolved, completion: handleResult)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(selectedFile == nil || git.isBusy)

                            Spacer()
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            if let selectedFile { git.stageFile(selectedFile) }
                        } label: {
                            Label("Stage", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(selectedFileState?.hasUnstagedChanges != true || selectedFileIsConflicted || git.isBusy)

                        Button {
                            if let selectedFile {
                                git.unstageFile(selectedFile)
                                handleResult(true, "Unstaged \(selectedFile)")
                            }
                        } label: {
                            Label("Unstage", systemImage: "arrow.uturn.backward.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(selectedFileState?.hasStagedChanges != true || git.isBusy)

                        Button(role: .destructive) {
                            if let selectedFile {
                                git.discardFile(selectedFile, completion: handleResult)
                            }
                        } label: {
                            Label("Discard", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(selectedFile == nil || git.isBusy)

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Button("Stage All") {
                            git.stageAll()
                            handleResult(true, "Staged all changes")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(git.statuses.isEmpty || git.isBusy)

                        Button("Unstage All") {
                            git.unstageAll(completion: handleResult)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!git.statuses.values.contains(where: \.hasStagedChanges) || git.isBusy)

                        Button("Discard All", role: .destructive) {
                            git.discardAll(completion: handleResult)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(git.statuses.isEmpty || git.isBusy)

                        Spacer()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Commit section
                VStack(spacing: 6) {
                    TextField("Commit message…", text: $commitMessage, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .lineLimit(3)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(6)

                    HStack {
                        if let result = commitResult {
                            Text(result)
                                .font(.system(size: 10))
                                .foregroundStyle(commitResultFailed ? Color.red : Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Commit") {
                            git.commit(message: commitMessage) { ok, msg in
                                handleCommitResult(ok, ok ? "Committed" : msg, clearMessageOnSuccess: ok)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || git.isBusy)

                        Button("Commit All") {
                            git.commitAll(message: commitMessage) { ok, msg in
                                handleCommitResult(ok, ok ? "Committed all changes" : msg, clearMessageOnSuccess: ok)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || git.statuses.isEmpty || git.isBusy)

                        Button("Amend Last") {
                            git.amendLastCommit(message: commitMessage) { ok, msg in
                                handleCommitResult(ok, ok ? "Amended last commit" : msg, clearMessageOnSuccess: false)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(git.commits.isEmpty || git.isBusy)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)

            // Right: diff
            DiffView(diff: git.diff, placeholder: diffPlaceholder)
        }
    }

    private var diffPlaceholder: String {
        if selectedFile == nil { return "Select a file to see diff" }
        if git.isLoadingDiff { return "Loading…" }
        return "No diff available for this file"
    }

    private var selectedFileState: GitFileState? {
        guard let selectedFile else { return nil }
        return git.statuses[selectedFile]
    }

    private var selectedFileIsConflicted: Bool {
        guard let state = selectedFileState else { return false }
        if case .unmerged = state.status { return true }
        return false
    }

    private var sortedPaths: [String] {
        git.statuses.keys.sorted { lhs, rhs in
            let leftConflict = conflictRank(for: lhs)
            let rightConflict = conflictRank(for: rhs)
            if leftConflict != rightConflict { return leftConflict < rightConflict }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private func conflictRank(for path: String) -> Int {
        guard let state = git.statuses[path] else { return 1 }
        if case .unmerged = state.status { return 0 }
        return 1
    }

    private func handleResult(_ ok: Bool, _ message: String) {
        commitResultFailed = !ok
        commitResult = "\(ok ? "✓" : "✗") \(message)"

        let snapshot = commitResult
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if commitResult == snapshot {
                commitResult = nil
                commitResultFailed = false
            }
        }
    }

    private func handleCommitResult(_ ok: Bool, _ message: String, clearMessageOnSuccess: Bool) {
        handleResult(ok, message)
        if ok, clearMessageOnSuccess {
            commitMessage = ""
        }
    }
}

private struct GitFileRow: View {
    let git: GitStatusService
    let path: String
    let state: GitFileState

    var body: some View {
        HStack(spacing: 6) {
            let c = state.status.color
            Text(state.status.label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: c.r, green: c.g, blue: c.b))
                .frame(width: 14)

            Text((path as NSString).lastPathComponent)
                .font(.system(size: 11))
                .lineLimit(1)

            if state.hasStagedChanges {
                GitStateBadge(text: "Staged", tint: Color.green.opacity(0.75))
            }
            if state.hasUnstagedChanges {
                GitStateBadge(text: "Unstaged", tint: Color.orange.opacity(0.85))
            }
            if case .unmerged = state.status {
                GitStateBadge(text: "Conflict", tint: Color.pink.opacity(0.85))
            }

            Spacer()

            Text((path as NSString).deletingLastPathComponent)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Stage") { git.stageFile(path) }
                .disabled(!state.hasUnstagedChanges)
            Button("Unstage") { git.unstageFile(path) }
                .disabled(!state.hasStagedChanges)
            Button("Discard", role: .destructive) {
                git.discardFile(path) { _, _ in }
            }
            if case .unmerged = state.status {
                Divider()
                Button("Accept Current") {
                    git.resolveConflict(path, using: .ours) { _, _ in }
                }
                Button("Accept Incoming") {
                    git.resolveConflict(path, using: .theirs) { _, _ in }
                }
                Button("Accept Both") {
                    git.resolveConflict(path, using: .both) { _, _ in }
                }
                Button("Mark Resolved") {
                    git.resolveConflict(path, using: .markResolved) { _, _ in }
                }
            }
        }
    }
}

struct GitStateBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint))
    }
}

// MARK: - Diff view

private struct DiffView: View {
    let diff: String
    let placeholder: String

    var body: some View {
        if diff.isEmpty {
            Text(placeholder)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        DiffLine(text: line)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private struct DiffLine: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(lineColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lineBg)
    }

    private var lineColor: Color {
        if text.hasPrefix("+") && !text.hasPrefix("+++") { return Color(red: 0.2, green: 0.7, blue: 0.3) }
        if text.hasPrefix("-") && !text.hasPrefix("---") { return Color(red: 0.85, green: 0.3, blue: 0.3) }
        if text.hasPrefix("@@") { return .cyan }
        if text.hasPrefix("diff") || text.hasPrefix("index") || text.hasPrefix("---") || text.hasPrefix("+++") { return .secondary }
        return .primary
    }

    private var lineBg: Color {
        if text.hasPrefix("+") && !text.hasPrefix("+++") { return Color.green.opacity(0.06) }
        if text.hasPrefix("-") && !text.hasPrefix("---") { return Color.red.opacity(0.06) }
        return Color.clear
    }
}

// MARK: - Graph model

private struct GitGraphRow: Identifiable {
    var id: String { commit.id }
    let commit: GitCommit
    let lane: Int
    let color: Color
    let laneCount: Int
    let topLines: [(from: Int, to: Int, color: Color)]
    let bottomLines: [(from: Int, to: Int, color: Color)]
}

private struct GitGraphLane {
    let hash: String
    let color: Color
    let priority: Int
}

private let graphPalette: [Color] = [
    Color(red: 0.42, green: 0.68, blue: 1.00),
    Color(red: 1.00, green: 0.58, blue: 0.25),
    Color(red: 0.38, green: 0.85, blue: 0.50),
    Color(red: 0.80, green: 0.45, blue: 0.95),
    Color(red: 1.00, green: 0.42, blue: 0.42),
    Color(red: 0.28, green: 0.88, blue: 0.88),
    Color(red: 1.00, green: 0.82, blue: 0.28),
    Color(red: 1.00, green: 0.50, blue: 0.72),
]

private func normalizedGraphBranchName(_ name: String) -> String {
    if name.hasPrefix("remotes/") {
        return String(name.dropFirst("remotes/".count))
    }
    return name
}

private func isGraphHeadRef(_ ref: String, knownBranches: Set<String>) -> Bool {
    if ref == "HEAD" || ref.hasPrefix("HEAD -> ") { return true }
    if ref.hasPrefix("tag: ") { return false }

    if let arrowRange = ref.range(of: " -> ") {
        let source = String(ref[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let target = String(ref[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        if knownBranches.isEmpty { return true }
        return knownBranches.contains(source) || knownBranches.contains(target)
    }

    if knownBranches.isEmpty { return true }
    return knownBranches.contains(ref)
}

private func graphLanePriority(for ref: String) -> Int? {
    if ref.hasPrefix("tag: ") { return nil }

    let trimmed = ref.trimmingCharacters(in: .whitespaces)
    let canonical: String
    let isCurrentHead = trimmed == "HEAD" || trimmed.hasPrefix("HEAD -> ")

    if trimmed.hasPrefix("HEAD -> ") {
        canonical = String(trimmed.dropFirst("HEAD -> ".count))
    } else if let arrowRange = trimmed.range(of: " -> ") {
        canonical = String(trimmed[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    } else {
        canonical = trimmed
    }

    let isRemote = canonical.contains("/")
    let branchName = canonical.split(separator: "/").last.map(String.init) ?? canonical

    switch branchName {
    case "main", "master", "trunk":
        return isRemote ? 500 : 900
    default:
        break
    }

    if isCurrentHead { return 750 }
    if isRemote { return 300 }
    return 600
}

private func buildGraph(_ commits: [GitCommit], branches: [GitBranch]) -> [GitGraphRow] {
    var lanes: [GitGraphLane?] = []
    var colorIdx = 0
    var rows: [GitGraphRow] = []
    let knownBranches = Set(branches.map { normalizedGraphBranchName($0.name) })

    func nextColor() -> Color {
        let c = graphPalette[colorIdx % graphPalette.count]
        colorIdx += 1
        return c
    }

    func trimTrailingEmptyLanes() {
        while lanes.last == nil { lanes.removeLast() }
    }

    func activeLaneCount(_ lanes: [GitGraphLane?]) -> Int {
        lanes.lastIndex(where: { $0 != nil }).map { $0 + 1 } ?? 0
    }

    func firstEmptyLane(near anchor: Int) -> Int? {
        guard !lanes.isEmpty else { return nil }
        if lanes.indices.contains(anchor), lanes[anchor] == nil { return anchor }

        for offset in 1...lanes.count {
            let right = anchor + offset
            if right < lanes.count, lanes[right] == nil { return right }

            let left = anchor - offset
            if left >= 0, lanes[left] == nil { return left }
        }
        return nil
    }

    func ensureLane(for hash: String, preferredColor: Color? = nil, preferredPriority: Int? = nil, near anchor: Int? = nil) -> Int {
        if let existing = lanes.firstIndex(where: { $0?.hash == hash }) {
            if let preferredPriority, let lane = lanes[existing], preferredPriority > lane.priority {
                lanes[existing] = GitGraphLane(hash: lane.hash, color: lane.color, priority: preferredPriority)
            }
            return existing
        }

        let laneIndex: Int
        if let anchor, let nearby = firstEmptyLane(near: anchor) {
            laneIndex = nearby
        } else if let empty = lanes.firstIndex(where: { $0 == nil }) {
            laneIndex = empty
        } else {
            laneIndex = lanes.count
            lanes.append(nil)
        }

        lanes[laneIndex] = GitGraphLane(
            hash: hash,
            color: preferredColor ?? nextColor(),
            priority: preferredPriority ?? 0
        )
        return laneIndex
    }

    var seenHeadCommits = Set<String>()
    for commit in commits where commit.refs.contains(where: { isGraphHeadRef($0, knownBranches: knownBranches) }) {
        guard seenHeadCommits.insert(commit.id).inserted else { continue }
        let priority = commit.refs.compactMap(graphLanePriority).max() ?? 0
        _ = ensureLane(for: commit.id, preferredPriority: priority)
    }

    if lanes.isEmpty, let firstCommit = commits.first {
        _ = ensureLane(for: firstCommit.id)
    }

    for commit in commits {
        var rowStart = lanes
        var matching = rowStart.indices.filter { rowStart[$0]?.hash == commit.id }

        if matching.isEmpty {
            _ = ensureLane(for: commit.id)
            rowStart = lanes
            matching = rowStart.indices.filter { rowStart[$0]?.hash == commit.id }
        }

        let preferredLane = matching.sorted { lhs, rhs in
            let left = rowStart[lhs]?.priority ?? 0
            let right = rowStart[rhs]?.priority ?? 0
            if left == right { return lhs > rhs }
            return left > right
        }.first
        guard let myLane = preferredLane, let myColor = rowStart[myLane]?.color else { continue }
        let myPriority = rowStart[myLane]?.priority ?? 0

        var topLines: [(from: Int, to: Int, color: Color)] = []
        for (i, lane) in rowStart.enumerated() {
            guard let lane else { continue }
            let targetLane = lane.hash == commit.id ? myLane : i
            topLines.append((i, targetLane, lane.color))
        }

        lanes = rowStart
        for index in matching {
            lanes[index] = nil
        }

        var bottomLines: [(from: Int, to: Int, color: Color)] = []

        if let p0 = commit.parents.first {
            let inherited = lanes.compactMap { $0 }.first(where: { $0.hash == p0 })?.color ?? myColor
            let parentPriority = max(lanes.compactMap { $0 }.first(where: { $0.hash == p0 })?.priority ?? 0, myPriority)
            lanes[myLane] = GitGraphLane(hash: p0, color: inherited, priority: parentPriority)
            bottomLines.append((myLane, myLane, inherited))
        }

        for parent in commit.parents.dropFirst() {
            let parentLane = ensureLane(for: parent, preferredPriority: myPriority, near: myLane)
            let parentColor = lanes[parentLane]?.color ?? myColor
            bottomLines.append((myLane, parentLane, parentColor))
        }

        for (i, lane) in lanes.enumerated() {
            guard let lane else { continue }
            guard !bottomLines.contains(where: { $0.from == i && $0.to == i }) else { continue }
            bottomLines.append((i, i, lane.color))
        }

        trimTrailingEmptyLanes()

        let laneCount = max(max(activeLaneCount(rowStart), activeLaneCount(lanes)), myLane + 1)
        rows.append(GitGraphRow(commit: commit, lane: myLane, color: myColor,
                                laneCount: laneCount,
                                topLines: topLines, bottomLines: bottomLines))
    }
    return rows
}

// MARK: - History tab

private let laneW: CGFloat = 14
private let dotR:  CGFloat = 4.5

private struct GitHistoryView: View {
    let git: GitStatusService

    @State private var selectedCommit: String? = nil
    @State private var historyActionStatus: String? = nil
    @State private var historyActionFailed = false
    @State private var newTagName = ""
    @State private var compareFromRef = ""
    @State private var compareToRef = ""

    private var graphRows: [GitGraphRow] { buildGraph(git.commits, branches: git.branches) }
    private var selectedCommitModel: GitCommit? {
        guard let selectedCommit else { return nil }
        return git.commits.first { $0.id == selectedCommit }
    }

    var body: some View {
        if git.commits.isEmpty {
            Text("No commits yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let rows     = graphRows
            let maxLanes = rows.map(\.laneCount).max() ?? 1
            let gWidth   = CGFloat(maxLanes) * laneW + laneW

            HSplitView {
                List(rows, selection: $selectedCommit) { row in
                    GraphCommitRow(row: row, graphWidth: gWidth)
                        .tag(row.id)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8))
                        .contextMenu {
                            Button("Cherry-pick") {
                                git.cherryPickCommit(row.commit.id, completion: handleHistoryAction)
                            }
                            Button("Create Tag at Commit") {
                                selectedCommit = row.commit.id
                            }
                        }
                }
                .listStyle(.plain)
                .frame(minWidth: 280, idealWidth: 360)

                HistoryCommitDetailView(
                    git: git,
                    commit: selectedCommitModel,
                    newTagName: $newTagName,
                    compareFromRef: $compareFromRef,
                    compareToRef: $compareToRef,
                    actionStatus: historyActionStatus,
                    actionFailed: historyActionFailed,
                    onCherryPick: {
                        guard let selectedCommit else { return }
                        git.cherryPickCommit(selectedCommit, completion: handleHistoryAction)
                    },
                    onCreateTag: {
                        guard let selectedCommit else { return }
                        let tagName = newTagName
                        git.createTag(tagName, at: selectedCommit) { ok, message in
                            handleHistoryAction(ok, message)
                            if ok { newTagName = "" }
                        }
                    },
                    onCompare: {
                        git.loadCompareResult(from: compareFromRef, to: compareToRef)
                    },
                    onClearCompare: {
                        git.clearCompareResult()
                    }
                )
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                guard selectedCommit == nil, let first = git.commits.first?.id else { return }
                selectedCommit = first
                compareToRef = first
                git.loadCommitDetail(for: first)
            }
            .onChange(of: selectedCommit) { _, newValue in
                if let newValue {
                    compareToRef = newValue
                    git.clearCompareResult()
                    git.loadCommitDetail(for: newValue)
                } else {
                    compareToRef = ""
                    git.clearCompareResult()
                    git.clearCommitDetail()
                }
            }
            .onChange(of: git.commits.map(\.id)) { _, ids in
                guard !ids.isEmpty else {
                    selectedCommit = nil
                    compareToRef = ""
                    git.clearCompareResult()
                    git.clearCommitDetail()
                    return
                }
                if let selectedCommit, ids.contains(selectedCommit) { return }
                self.selectedCommit = ids.first
                if let first = ids.first {
                    compareToRef = first
                    git.clearCompareResult()
                    git.loadCommitDetail(for: first)
                }
            }
        }
    }

    private func handleHistoryAction(_ ok: Bool, _ message: String) {
        historyActionFailed = !ok
        historyActionStatus = "\(ok ? "✓" : "✗") \(message)"

        let snapshot = historyActionStatus
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if historyActionStatus == snapshot {
                historyActionStatus = nil
                historyActionFailed = false
            }
        }
    }
}

private struct HistoryCommitDetailView: View {
    let git: GitStatusService
    let commit: GitCommit?
    @Binding var newTagName: String
    @Binding var compareFromRef: String
    @Binding var compareToRef: String
    let actionStatus: String?
    let actionFailed: Bool
    let onCherryPick: () -> Void
    let onCreateTag: () -> Void
    let onCompare: () -> Void
    let onClearCompare: () -> Void

    var body: some View {
        Group {
            if let commit {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(commit.message)
                            .font(.headline)
                            .textSelection(.enabled)

                        Text("\(commit.shortHash) · \(commit.author) · \(commit.fullDate)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        if let detail = git.commitDetail, !detail.body.isEmpty, detail.body != commit.message {
                            Text(detail.body)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        HStack(spacing: 8) {
                            Button("Cherry-pick", action: onCherryPick)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(git.isBusy)

                            TextField("New tag name…", text: $newTagName)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(maxWidth: 180)

                            Button("Create Tag", action: onCreateTag)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || git.isBusy)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Compare Refs")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                TextField("From ref / branch / commit…", text: $compareFromRef)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)

                                TextField("To ref / branch / commit…", text: $compareToRef)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)

                                Button("Compare", action: onCompare)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(compareFromRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || compareToRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || git.isBusy)

                                Button("Clear", action: onClearCompare)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(git.compareResult == nil && git.compareError == nil && !git.isLoadingCompareResult)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let actionStatus {
                            Text(actionStatus)
                                .font(.system(size: 10))
                                .foregroundStyle(actionFailed ? Color.red : Color.green)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    if git.isLoadingCommitDetail {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                if git.isLoadingCompareResult {
                                    Text("Loading compare diff…")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 10)
                                } else if let compareError = git.compareError {
                                    Text(compareError)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 10)
                                } else if let compare = git.compareResult {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Compare: \(compare.fromRef) -> \(compare.toRef)")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.secondary)

                                        if !compare.files.isEmpty {
                                            ForEach(compare.files) { file in
                                                HStack(spacing: 8) {
                                                    Text(file.status)
                                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                        .frame(width: 18)
                                                    Text(file.path)
                                                        .font(.system(size: 11, design: .monospaced))
                                                        .textSelection(.enabled)
                                                    Spacer()
                                                }
                                            }
                                        } else {
                                            Text("No file differences")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.top, 10)

                                    DiffView(
                                        diff: compare.diff,
                                        placeholder: "No patch differences for the selected refs"
                                    )
                                    .frame(minHeight: 240)
                                } else if let detail = git.commitDetail, !detail.files.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Changed Files")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.secondary)

                                        ForEach(detail.files) { file in
                                            HStack(spacing: 8) {
                                                Text(file.status)
                                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 18)
                                                Text(file.path)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .textSelection(.enabled)
                                                Spacer()
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.top, 10)
                                }

                                if git.compareResult == nil && git.compareError == nil && !git.isLoadingCompareResult {
                                    DiffView(
                                        diff: git.commitDetail?.diff ?? "",
                                        placeholder: git.isLoadingCommitDetail ? "Loading…" : "No patch available for this commit"
                                    )
                                    .frame(minHeight: 240)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text("Select a commit to inspect details")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct GraphCommitRow: View {
    let row: GitGraphRow
    let graphWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // ── Graph canvas ─────────────────────────────────────────────
            Canvas { ctx, size in
                let h    = size.height
                let midY = h / 2.0
                let dotX = CGFloat(row.lane) * laneW + laneW / 2

                // top lines  (top → midY)
                for l in row.topLines {
                    let x1 = CGFloat(l.from) * laneW + laneW / 2
                    let x2 = l.to == row.lane ? dotX : CGFloat(l.to) * laneW + laneW / 2
                    drawSegment(ctx: ctx,
                                from: CGPoint(x: x1, y: 0),
                                to:   CGPoint(x: x2, y: midY),
                                color: l.color)
                }

                // bottom lines  (midY → bottom)
                for l in row.bottomLines {
                    let x1 = l.from == row.lane ? dotX : CGFloat(l.from) * laneW + laneW / 2
                    let x2 = CGFloat(l.to) * laneW + laneW / 2
                    drawSegment(ctx: ctx,
                                from: CGPoint(x: x1, y: midY),
                                to:   CGPoint(x: x2, y: h),
                                color: l.color)
                }

                // dot
                let r   = dotR
                let dot = CGRect(x: dotX - r, y: midY - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: dot), with: .color(row.color))
                // thin white ring
                ctx.stroke(Path(ellipseIn: dot.insetBy(dx: -0.8, dy: -0.8)),
                           with: .color(.white.opacity(0.20)),
                           style: StrokeStyle(lineWidth: 1.5))
            }
            .frame(width: graphWidth)
            .clipped()

            // ── Commit info ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                // Branch / tag labels
                if !row.commit.refs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(row.commit.refs.prefix(4), id: \.self) { ref in
                            RefLabel(ref: ref, laneColor: row.color)
                        }
                    }
                }

                Text(row.commit.message)
                    .font(.system(size: 11))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(row.commit.shortHash)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(row.color)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    Text(row.commit.author)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    Text(row.commit.date)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 5)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Draw a line; uses a smooth bezier for diagonal segments.
    private func drawSegment(ctx: GraphicsContext,
                             from: CGPoint, to: CGPoint,
                             color: Color) {
        var path = Path()
        path.move(to: from)
        if abs(from.x - to.x) > 1 {
            let midY = (from.y + to.y) / 2
            path.addCurve(to: to,
                          control1: CGPoint(x: from.x, y: midY),
                          control2: CGPoint(x: to.x,   y: midY))
        } else {
            path.addLine(to: to)
        }
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Ref label (branch / tag / HEAD pill)

private struct RefLabel: View {
    let ref: String
    let laneColor: Color

    private var isHEAD:   Bool { ref == "HEAD" || ref.hasPrefix("HEAD ->") }
    private var isRemote: Bool { ref.hasPrefix("origin/") || ref.contains("->") && ref.contains("/") }
    private var isTag:    Bool { ref.hasPrefix("tag:") }

    /// The short display name
    private var label: String {
        if ref.hasPrefix("HEAD -> ") { return String(ref.dropFirst("HEAD -> ".count)) }
        if ref.hasPrefix("tag: ")    { return String(ref.dropFirst("tag: ".count)) }
        return ref
    }

    private var icon: String {
        if isHEAD   { return "location.fill" }
        if isTag    { return "tag.fill" }
        if isRemote { return "cloud.fill" }
        return "arrow.triangle.branch"
    }

    private var bg: Color {
        if isHEAD   { return laneColor.opacity(0.20) }
        if isTag    { return Color.yellow.opacity(0.18) }
        if isRemote { return Color.gray.opacity(0.18) }
        return laneColor.opacity(0.18)
    }

    private var fg: Color {
        if isHEAD   { return laneColor }
        if isTag    { return Color.yellow }
        if isRemote { return Color.gray }
        return laneColor
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(bg))
        .overlay(Capsule().strokeBorder(fg.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Branches tab

private struct GitBranchesView: View {
    let git: GitStatusService

    @State private var newBranchName = ""
    @State private var renameSourceBranch: String? = nil
    @State private var renameBranchName = ""
    @State private var newTagName = ""
    @State private var stashMessage = ""
    @State private var actionResult: String? = nil
    @State private var actionResultFailed = false
    @State private var remoteName = "origin"
    @State private var remoteURL = ""
    @State private var remoteResult: String? = nil
    @State private var remoteResultFailed = false
    @State private var mergeConflictAlertMessage: String? = nil

    private var localBranches: [GitBranch] { git.branches.filter { !$0.isRemote } }
    private var remoteBranches: [GitBranch] { git.branches.filter { $0.isRemote } }
    private var existingRemote: GitRemote? {
        let name = remoteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return git.remotes.first { $0.name == name }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if !localBranches.isEmpty {
                    Section("Local") {
                        ForEach(localBranches) { branch in
                            LocalBranchRow(
                                branch: branch,
                                isBusy: git.isBusy,
                                onSwitch: {
                                    git.switchBranch(branch.name)
                                },
                                onMerge: branch.isCurrent ? nil : {
                                    git.mergeBranch(branch.name) { ok, message in
                                        handleMergeResult(branch: branch.name, ok: ok, message: message)
                                    }
                                },
                                onRebase: branch.isCurrent ? nil : {
                                    git.rebaseCurrentBranch(onto: branch.name, completion: handleActionResult)
                                },
                                onDelete: branch.isCurrent ? nil : {
                                    git.deleteBranch(branch.name, completion: handleActionResult)
                                },
                                onRename: {
                                    renameSourceBranch = branch.name
                                    renameBranchName = branch.name
                                }
                            )
                        }
                    }
                }
                if !remoteBranches.isEmpty {
                    Section("Remote Branches") {
                        ForEach(remoteBranches) { branch in
                            RemoteBranchRow(
                                branch: branch,
                                isBusy: git.isBusy,
                                onCheckout: {
                                    git.checkoutRemoteBranch(branch.name, completion: handleActionResult)
                                }
                            )
                        }
                    }
                }
                if !git.tags.isEmpty {
                    Section("Tags") {
                        ForEach(git.tags) { tag in
                            GitTagRow(
                                tag: tag,
                                isBusy: git.isBusy,
                                onCheckout: {
                                    git.checkoutTag(tag.name, completion: handleActionResult)
                                },
                                onDelete: {
                                    git.deleteTag(tag.name, completion: handleActionResult)
                                }
                            )
                        }
                    }
                }
                if !git.stashes.isEmpty {
                    Section("Stashes") {
                        ForEach(git.stashes) { stash in
                            GitStashRow(
                                stash: stash,
                                isBusy: git.isBusy,
                                onApply: {
                                    git.applyStash(stash.reference, pop: false, completion: handleActionResult)
                                },
                                onPop: {
                                    git.applyStash(stash.reference, pop: true, completion: handleActionResult)
                                },
                                onDrop: {
                                    git.dropStash(stash.reference, completion: handleActionResult)
                                }
                            )
                        }
                    }
                }
                if !git.remotes.isEmpty {
                    Section("Remotes") {
                        ForEach(git.remotes) { remote in
                            RemoteRow(
                                remote: remote,
                                isPreferred: remote.name == git.preferredRemoteName,
                                onEdit: {
                                    remoteName = remote.name
                                    remoteURL = remote.url
                                },
                                onRemove: { removeRemote(named: remote.name) }
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)

            Divider()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("New branch name…", text: $newBranchName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { createBranch() }
                    Button("Create", action: createBranch)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || git.isBusy)
                }

                if let sourceBranch = renameSourceBranch {
                    HStack(spacing: 8) {
                        Text("Rename \(sourceBranch) →")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        TextField("Renamed branch…", text: $renameBranchName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit { submitBranchRename() }
                        Button("Rename", action: submitBranchRename)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(renameBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || git.isBusy)
                        Button("Cancel") {
                            self.renameSourceBranch = nil
                            renameBranchName = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if !git.currentBranch.isEmpty {
                    Text("Current branch: \(git.currentBranch). Merge and rebase actions target this branch.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let actionResult {
                    Text(actionResult)
                        .font(.system(size: 10))
                        .foregroundStyle(actionResultFailed ? Color.red : Color.green)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("New tag name…", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { createTag() }
                    Button("Create Tag", action: createTag)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || git.isBusy)
                }

                HStack(spacing: 8) {
                    TextField("Stash message…", text: $stashMessage)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { createStash() }
                    Button("Stash", action: createStash)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(git.statuses.isEmpty || git.isBusy)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Remote name", text: $remoteName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(width: 120)
                        TextField("Remote URL…", text: $remoteURL)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .onSubmit { submitRemoteForm() }
                        if existingRemote == nil {
                            Button("Add Remote", action: submitRemoteForm)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(remoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || git.isBusy)
                        } else {
                            Button("Update Remote", action: submitRemoteForm)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(remoteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || git.isBusy)
                        }

                        if existingRemote != nil {
                            Button("Remove") { removeRemote(named: remoteName) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(git.isBusy)
                        }
                    }

                    if let existingRemote {
                        Text("Editing existing remote '\(existingRemote.name)'.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    if let remoteResult {
                        Text(remoteResult)
                            .font(.system(size: 10))
                            .foregroundStyle(remoteResultFailed ? Color.red : Color.green)
                            .lineLimit(2)
                    }
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .alert("Merge Conflict", isPresented: mergeConflictAlertPresented) {
            Button("OK", role: .cancel) {
                mergeConflictAlertMessage = nil
            }
        } message: {
            Text(mergeConflictAlertMessage ?? "Resolve the conflicted files in the Changes tab, then finish the merge.")
        }
    }

    private func createBranch() {
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        git.createBranch(name)
        newBranchName = ""
    }

    private func submitBranchRename() {
        guard let renameSourceBranch else { return }
        let newName = renameBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        git.renameBranch(renameSourceBranch, to: newName) { ok, message in
            handleActionResult(ok, message)
            if ok {
                self.renameSourceBranch = nil
                self.renameBranchName = ""
            }
        }
    }

    private func createTag() {
        let tagName = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tagName.isEmpty else { return }
        git.createTag(tagName) { ok, message in
            handleActionResult(ok, message)
            if ok { newTagName = "" }
        }
    }

    private func createStash() {
        let message = stashMessage
        git.createStash(message: message) { ok, result in
            handleActionResult(ok, result)
            if ok { stashMessage = "" }
        }
    }

    private func handleActionResult(_ ok: Bool, _ message: String) {
        actionResultFailed = !ok
        actionResult = "\(ok ? "✓" : "✗") \(message)"

        let resultSnapshot = actionResult
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if actionResult == resultSnapshot {
                actionResult = nil
                actionResultFailed = false
            }
        }
    }

    private func handleMergeResult(branch: String, ok: Bool, message: String) {
        guard !ok, isMergeConflictMessage(message) else {
            handleActionResult(ok, message)
            return
        }

        actionResult = nil
        actionResultFailed = false
        mergeConflictAlertMessage = "Merging \(branch) into \(git.currentBranch) created conflicts. Open the Changes tab, resolve the conflicted files, then complete the merge."
    }

    private func isMergeConflictMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("conflict") ||
            normalized.contains("automatic merge failed") ||
            normalized.contains("fix conflicts")
    }

    private var mergeConflictAlertPresented: Binding<Bool> {
        Binding(
            get: { mergeConflictAlertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    mergeConflictAlertMessage = nil
                }
            }
        )
    }

    private func submitRemoteForm() {
        let name = remoteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty else { return }
        if existingRemote != nil {
            git.updateRemote(name: name, url: url, completion: handleRemoteResult)
        } else {
            git.addRemote(name: name, url: url, completion: handleRemoteResult)
        }
    }

    private func removeRemote(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        git.removeRemote(name: trimmedName) { ok, message in
            handleRemoteResult(ok, message)
            if ok && remoteName.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedName {
                remoteName = "origin"
                remoteURL = ""
            }
        }
    }

    private func handleRemoteResult(_ ok: Bool, _ message: String) {
        remoteResultFailed = !ok
        remoteResult = "\(ok ? "✓" : "✗") \(message)"
        if ok, existingRemote == nil { remoteName = "origin"; remoteURL = "" }

        let resultSnapshot = remoteResult
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if remoteResult == resultSnapshot {
                remoteResult = nil
                remoteResultFailed = false
            }
        }
    }
}

private struct LocalBranchRow: View {
    let branch: GitBranch
    let isBusy: Bool
    let onSwitch: (() -> Void)?
    let onMerge: (() -> Void)?
    let onRebase: (() -> Void)?
    let onDelete: (() -> Void)?
    let onRename: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: branch.isCurrent ? "checkmark" : "arrow.triangle.branch")
                .font(.system(size: 10))
                .foregroundStyle(branch.isCurrent ? Color.green : Color.secondary)
                .frame(width: 14)

            Text(branch.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(branch.isCurrent ? Color.primary : Color.secondary)

            Spacer()

            if let onSwitch, !branch.isCurrent {
                Button("Switch", action: onSwitch)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isBusy)
            }

            if let onRebase, !branch.isCurrent {
                Button("Rebase", action: onRebase)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isBusy)
            }

            if let onMerge, !branch.isCurrent {
                Button("Merge", action: onMerge)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(isBusy)
            }

            if let onRename {
                Button("Rename", action: onRename)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isBusy)
            }

            if let onDelete, !branch.isCurrent {
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isBusy)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RemoteBranchRow: View {
    let branch: GitBranch
    let isBusy: Bool
    let onCheckout: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(branch.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Checkout", action: onCheckout)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isBusy)
        }
        .padding(.vertical, 2)
    }
}

private struct GitTagRow: View {
    let tag: GitTag
    let isBusy: Bool
    let onCheckout: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
                .font(.system(size: 10))
                .foregroundStyle(.yellow)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                HStack(spacing: 6) {
                    Text(tag.targetShortHash)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if !tag.subject.isEmpty {
                        Text(tag.subject)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button("Checkout", action: onCheckout)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isBusy)

            Button("Delete", role: .destructive, action: onDelete)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isBusy)
        }
        .padding(.vertical, 2)
    }
}

private struct GitStashRow: View {
    let stash: GitStash
    let isBusy: Bool
    let onApply: () -> Void
    let onPop: () -> Void
    let onDrop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(stash.reference)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(stash.message.isEmpty ? "Saved working tree" : stash.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Apply", action: onApply)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isBusy)

            Button("Pop", action: onPop)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isBusy)

            Button("Drop", role: .destructive, action: onDrop)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isBusy)
        }
        .padding(.vertical, 2)
    }
}

private struct RemoteRow: View {
    let remote: GitRemote
    let isPreferred: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(remote.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))

                if isPreferred {
                    GitStateBadge(text: "Default", tint: Color.blue.opacity(0.75))
                }

                Spacer()

                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                Button("Remove", action: onRemove)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }

            Text(remote.url)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

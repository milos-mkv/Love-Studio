import Foundation

// MARK: - Models

enum GitFileStatus {
    case modified, added, deleted, renamed, unmerged

    var color: (r: Double, g: Double, b: Double) {
        switch self {
        case .modified:  return (0.95, 0.70, 0.20)
        case .added:     return (0.25, 0.80, 0.40)
        case .deleted:   return (0.90, 0.30, 0.30)
        case .renamed:   return (0.40, 0.65, 0.95)
        case .unmerged:  return (0.90, 0.40, 0.90)
        }
    }

    var label: String {
        switch self {
        case .modified:  return "M"
        case .added:     return "A"
        case .deleted:   return "D"
        case .renamed:   return "R"
        case .unmerged:  return "U"
        }
    }
}

struct GitFileState {
    let status: GitFileStatus
    let hasStagedChanges: Bool
    let hasUnstagedChanges: Bool

    var isStagedOnly: Bool  { hasStagedChanges && !hasUnstagedChanges }
    var isUnstagedOnly: Bool { hasUnstagedChanges && !hasStagedChanges }
}

struct GitCommit: Identifiable {
    let id: String
    let shortHash: String
    let message: String
    let author: String
    let date: String
    let fullDate: String
    let parents: [String]
    let refs: [String]      // branch/tag labels (e.g. ["HEAD -> main", "origin/main"])
}

struct GitBranch: Identifiable {
    var id: String { name }
    let name: String
    let isCurrent: Bool
    let isRemote: Bool
}

struct GitRemote: Identifiable {
    var id: String { name }
    let name: String
    let url: String
}

struct GitTag: Identifiable {
    var id: String { name }
    let name: String
    let targetShortHash: String
    let subject: String
}

struct GitStash: Identifiable {
    var id: String { reference }
    let reference: String
    let message: String
}

struct GitCommitFileChange: Identifiable {
    var id: String { "\(status):\(path)" }
    let status: String
    let path: String
}

struct GitCommitDetail {
    let commitID: String
    let body: String
    let files: [GitCommitFileChange]
    let diff: String
}

struct GitCompareResult {
    let fromRef: String
    let toRef: String
    let files: [GitCommitFileChange]
    let diff: String
}

enum GitConflictResolutionStrategy {
    case ours
    case theirs
    case both
    case markResolved
}

enum GitRepositoryOperation {
    case merge
    case rebase
    case cherryPick

    var displayName: String {
        switch self {
        case .merge:      return "Merge"
        case .rebase:     return "Rebase"
        case .cherryPick: return "Cherry-pick"
        }
    }
}

fileprivate struct GitUpstreamStatus {
    let upstreamBranch: String
    let aheadCount: Int
    let behindCount: Int
    nonisolated static let empty = GitUpstreamStatus(upstreamBranch: "", aheadCount: 0, behindCount: 0)
}

// MARK: - Service

@Observable
@MainActor
final class GitStatusService {

    private(set) var statuses:      [String: GitFileState] = [:]
    private(set) var isGitRepo      = false
    private(set) var commits:       [GitCommit] = []
    private(set) var branches:      [GitBranch] = []
    private(set) var remotes:       [GitRemote] = []
    private(set) var tags:          [GitTag] = []
    private(set) var stashes:       [GitStash] = []
    private(set) var currentBranch  = ""
    private(set) var upstreamBranch = ""
    private(set) var aheadCount     = 0
    private(set) var behindCount    = 0
    private(set) var diff           = ""
    private(set) var isLoadingDiff  = false
    private(set) var selectedDiffPath: String? = nil
    private(set) var commitDetail: GitCommitDetail? = nil
    private(set) var isLoadingCommitDetail = false
    private(set) var compareResult: GitCompareResult? = nil
    private(set) var isLoadingCompareResult = false
    private(set) var compareError: String? = nil
    private(set) var currentOperation: GitRepositoryOperation? = nil
    private(set) var worktreeChangeToken = 0
    private(set) var isBusy         = false
    private(set) var lastError:     String? = nil

    private var refreshTask: Task<Void, Never>?
    private var projectRoot: URL?
    private var diffRequestID = 0
    private var commitDetailRequestID = 0
    private var compareRequestID = 0

    var conflictedPaths: [String] {
        statuses.keys.sorted().filter {
            guard let state = statuses[$0] else { return false }
            if case .unmerged = state.status { return true }
            return false
        }
    }

    // MARK: Lifecycle

    func attach(to rootURL: URL) {
        projectRoot = rootURL
        refresh()
        startAutoRefresh()
    }

    func detach() {
        refreshTask?.cancel()
        statuses = [:]; isGitRepo = false; remotes = []; tags = []; stashes = []
        currentBranch = ""; upstreamBranch = ""
        aheadCount = 0; behindCount = 0
        diff = ""; isLoadingDiff = false; selectedDiffPath = nil
        commitDetail = nil; isLoadingCommitDetail = false
        compareResult = nil; isLoadingCompareResult = false; compareError = nil
        currentOperation = nil
        worktreeChangeToken = 0
        projectRoot = nil
    }

    // MARK: Refresh

    func refresh() {
        guard let root = projectRoot else { return }
        let hasGit = FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
        Task {
            async let s  = Task.detached(priority: .utility) { hasGit ? GitCommands.runGitStatus(in: root)   : [:] }.value
            async let c  = Task.detached(priority: .utility) { hasGit ? GitCommands.runGitLog(in: root)      : [] }.value
            async let br = Task.detached(priority: .utility) { hasGit ? GitCommands.runGitBranches(in: root) : ([] as [GitBranch], "") }.value
            async let rm = Task.detached(priority: .utility) { hasGit ? GitCommands.runGitRemotes(in: root)  : [] }.value
            async let tg = Task.detached(priority: .utility) { hasGit ? GitCommands.runGitTags(in: root)     : [] }.value
            async let st = Task.detached(priority: .utility) { hasGit ? GitCommands.runGitStashes(in: root)  : [] }.value
            async let op = Task.detached(priority: .utility) { hasGit ? GitCommands.runGitOperationState(in: root) : nil }.value
            async let up = Task.detached(priority: .utility) { hasGit ? GitCommands.runGitUpstreamStatus(in: root) : .empty }.value
            let (statuses, commits, (branches, current), remotes, tags, stashes, currentOperation, upstream) = await (s, c, br, rm, tg, st, op, up)
            self.isGitRepo      = hasGit
            self.statuses       = statuses
            self.commits        = commits
            self.branches       = branches
            self.remotes        = remotes
            self.tags           = tags
            self.stashes        = stashes
            self.currentOperation = currentOperation
            self.currentBranch  = current
            self.upstreamBranch = upstream.upstreamBranch
            self.aheadCount     = upstream.aheadCount
            self.behindCount    = upstream.behindCount
        }
    }

    // MARK: Diff

    func loadDiff(for relativePath: String) {
        guard let root = projectRoot else { return }
        let state = statuses[relativePath]
        diffRequestID += 1
        let requestID = diffRequestID
        selectedDiffPath = relativePath
        diff = ""; isLoadingDiff = true
        Task {
            let result = await Task.detached(priority: .utility) {
                GitCommands.diffOutput(for: relativePath, state: state, in: root)
            }.value
            guard requestID == self.diffRequestID, self.selectedDiffPath == relativePath else { return }
            self.diff = result
            self.isLoadingDiff = false
        }
    }

    func clearDiff() {
        diffRequestID += 1; diff = ""; isLoadingDiff = false; selectedDiffPath = nil
    }

    // MARK: Commit details

    func loadCommitDetail(for commitID: String) {
        guard let root = projectRoot else { return }
        commitDetailRequestID += 1
        let requestID = commitDetailRequestID
        commitDetail = nil
        isLoadingCommitDetail = true
        Task {
            let result = await Task.detached(priority: .utility) {
                GitCommands.commitDetail(for: commitID, in: root)
            }.value
            guard requestID == self.commitDetailRequestID else { return }
            self.commitDetail = result
            self.isLoadingCommitDetail = false
        }
    }

    func clearCommitDetail() {
        commitDetailRequestID += 1
        commitDetail = nil
        isLoadingCommitDetail = false
    }

    // MARK: Compare

    func loadCompareResult(from fromRef: String, to toRef: String) {
        guard let root = projectRoot else { return }
        let trimmedFrom = fromRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = toRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFrom.isEmpty, !trimmedTo.isEmpty else {
            compareResult = nil
            compareError = "Both refs are required"
            isLoadingCompareResult = false
            return
        }

        compareRequestID += 1
        let requestID = compareRequestID
        compareResult = nil
        compareError = nil
        isLoadingCompareResult = true

        Task {
            let result = await Task.detached(priority: .utility) {
                GitCommands.compareRefs(from: trimmedFrom, to: trimmedTo, in: root)
            }.value
            guard requestID == self.compareRequestID else { return }
            self.isLoadingCompareResult = false
            if let compare = result.0 {
                self.compareResult = compare
                self.compareError = nil
            } else {
                self.compareResult = nil
                self.compareError = result.1 ?? "Failed to compare refs"
            }
        }
    }

    func clearCompareResult() {
        compareRequestID += 1
        compareResult = nil
        compareError = nil
        isLoadingCompareResult = false
    }

    // MARK: Staging / Commit

    func stageFile(_ relativePath: String)   { runGitCmd(["add", "--", relativePath]) }
    func stageAll()                          { runGitCmd(["add", "-A"]) }

    func unstageFile(_ relativePath: String) {
        guard let root = projectRoot else { return }
        let state = statuses[relativePath]
        isBusy = true
        Task {
            let ok = await Task.detached(priority: .utility) {
                GitCommands.unstage(relativePath, state: state, in: root)
            }.value
            self.isBusy = false
            self.lastError = ok ? nil : "Unstage failed"
            self.refresh()
            if let p = selectedDiffPath { self.loadDiff(for: p) }
        }
    }

    func unstageAll(completion: @escaping (Bool, String) -> Void) {
        runGitOperation({ root in
            let primary = GitCommands.gitWithError(["restore", "--staged", "--", "."], in: root)
            if primary.0 != nil { return primary }
            return GitCommands.gitWithError(["reset", "HEAD", "--", "."], in: root)
        }, completion: completion)
    }

    func discardFile(_ relativePath: String, completion: @escaping (Bool, String) -> Void) {
        guard let state = statuses[relativePath] else {
            completion(false, "No file selected"); return
        }
        runGitOperation({ root in GitCommands.discard(relativePath, state: state, in: root) }, completion: completion)
    }

    func discardAll(completion: @escaping (Bool, String) -> Void) {
        runGitOperation({ root in GitCommands.discardAll(in: root) }, completion: completion)
    }

    func resolveConflict(_ relativePath: String, using strategy: GitConflictResolutionStrategy, completion: @escaping (Bool, String) -> Void) {
        guard conflictedPaths.contains(relativePath) else {
            completion(false, "Selected file is not in conflict"); return
        }
        runGitOperation({ root in GitCommands.resolveConflict(relativePath, using: strategy, in: root) }, completion: completion)
    }

    func abortCurrentOperation(completion: @escaping (Bool, String) -> Void) {
        guard let currentOperation else {
            completion(false, "No merge, rebase, or cherry-pick in progress"); return
        }
        let args: [String]
        switch currentOperation {
        case .merge:      args = ["merge", "--abort"]
        case .rebase:     args = ["rebase", "--abort"]
        case .cherryPick: args = ["cherry-pick", "--abort"]
        }
        runGitOperation({ root in GitCommands.gitWithError(args, in: root) }, completion: completion)
    }

    func commit(message: String, completion: @escaping (Bool, String) -> Void) {
        guard let root = projectRoot,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(false, "Empty commit message"); return
        }
        isBusy = true
        Task {
            let out = await Task.detached(priority: .userInitiated) {
                GitCommands.git(["commit", "-m", message], in: root)
            }.value
            let ok = out != nil
            self.isBusy = false; self.lastError = ok ? nil : "Commit failed"
            self.refresh(); completion(ok, out ?? "Commit failed")
        }
    }

    func commitAll(message: String, completion: @escaping (Bool, String) -> Void) {
        guard let root = projectRoot,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(false, "Empty commit message"); return
        }
        isBusy = true
        Task {
            let (_, addErr) = await Task.detached(priority: .userInitiated) {
                GitCommands.gitWithError(["add", "-A"], in: root)
            }.value
            if addErr != nil {
                self.isBusy = false
                let message = GitCommands.commandMessage(stdout: nil, stderr: addErr, fallback: "Stage all failed")
                self.lastError = message
                completion(false, message)
                return
            }
            let (out, err) = await Task.detached(priority: .userInitiated) {
                GitCommands.gitWithError(["commit", "-m", message], in: root)
            }.value
            let ok = out != nil
            let finalMessage = GitCommands.commandMessage(stdout: out, stderr: err, fallback: ok ? "Committed" : "Commit failed")
            self.isBusy = false
            self.lastError = ok ? nil : finalMessage
            self.refresh()
            completion(ok, finalMessage)
        }
    }

    func amendLastCommit(message: String, completion: @escaping (Bool, String) -> Void) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandArgs = trimmed.isEmpty ? ["commit", "--amend", "--no-edit"] : ["commit", "--amend", "-m", trimmed]
        runGitOperation({ root in GitCommands.gitWithError(commandArgs, in: root) }, completion: completion)
    }

    // MARK: Branches

    func createBranch(_ name: String) { runGitCmd(["checkout", "-b", name]) }
    func switchBranch(_ name: String) { runGitCmd(["checkout", name]) }
    func mergeBranch(_ name: String, completion: @escaping (Bool, String) -> Void) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(false, "No branch selected"); return
        }
        guard !currentBranch.isEmpty else {
            completion(false, "No active branch"); return
        }
        guard currentBranch != name else {
            completion(false, "Cannot merge a branch into itself"); return
        }
        runGitOperation({ root in GitCommands.gitWithError(["merge", "--no-edit", name], in: root) }, completion: completion)
    }
    func renameBranch(_ name: String, to newName: String, completion: @escaping (Bool, String) -> Void) {
        let trimmedOld = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty else {
            completion(false, "Branch names cannot be empty"); return
        }
        let args = trimmedOld == currentBranch ? ["branch", "-m", trimmedNew] : ["branch", "-m", trimmedOld, trimmedNew]
        runGitOperation({ root in GitCommands.gitWithError(args, in: root) }, completion: completion)
    }

    func deleteBranch(_ name: String, completion: @escaping (Bool, String) -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(false, "No branch selected"); return }
        guard trimmed != currentBranch else { completion(false, "Cannot delete the current branch"); return }
        runGitOperation({ root in GitCommands.gitWithError(["branch", "-d", trimmed], in: root) }, completion: completion)
    }

    func checkoutRemoteBranch(_ name: String, completion: @escaping (Bool, String) -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(false, "No remote branch selected"); return }
        let remoteRef = trimmed.hasPrefix("remotes/") ? String(trimmed.dropFirst("remotes/".count)) : trimmed
        runGitOperation({ root in
            let branchName = remoteRef.split(separator: "/").last.map(String.init) ?? remoteRef
            let primary = GitCommands.gitWithError(["switch", "--track", "-c", branchName, remoteRef], in: root)
            if primary.0 != nil { return primary }
            return GitCommands.gitWithError(["checkout", "--track", remoteRef], in: root)
        }, completion: completion)
    }

    func rebaseCurrentBranch(onto name: String, completion: @escaping (Bool, String) -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(false, "No branch selected"); return }
        guard !currentBranch.isEmpty else { completion(false, "No active branch"); return }
        guard trimmed != currentBranch else { completion(false, "Current branch is already \(trimmed)"); return }
        runGitOperation({ root in GitCommands.gitWithError(["rebase", trimmed], in: root) }, completion: completion)
    }

    // MARK: History actions

    func cherryPickCommit(_ commitID: String, completion: @escaping (Bool, String) -> Void) {
        let trimmed = commitID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(false, "No commit selected"); return }
        runGitOperation({ root in GitCommands.gitWithError(["cherry-pick", trimmed], in: root) }, completion: completion)
    }

    // MARK: Tags

    func createTag(_ name: String, at commitID: String? = nil, completion: @escaping (Bool, String) -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(false, "Tag name cannot be empty"); return }
        let commandArgs = if let commitID, !commitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ["tag", trimmed, commitID]
        } else {
            ["tag", trimmed]
        }
        runGitOperation({ root in GitCommands.gitWithError(commandArgs, in: root) }, completion: completion)
    }

    func deleteTag(_ name: String, completion: @escaping (Bool, String) -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(false, "No tag selected"); return }
        runGitOperation({ root in GitCommands.gitWithError(["tag", "-d", trimmed], in: root) }, completion: completion)
    }

    func checkoutTag(_ name: String, completion: @escaping (Bool, String) -> Void) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(false, "No tag selected"); return }
        runGitOperation({ root in GitCommands.gitWithError(["checkout", trimmed], in: root) }, completion: completion)
    }

    // MARK: Stash

    func createStash(message: String, completion: @escaping (Bool, String) -> Void) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let args = trimmed.isEmpty ? ["stash", "push", "--include-untracked"] : ["stash", "push", "--include-untracked", "-m", trimmed]
        runGitOperation({ root in GitCommands.gitWithError(args, in: root) }, completion: completion)
    }

    func applyStash(_ reference: String, pop: Bool, completion: @escaping (Bool, String) -> Void) {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(false, "No stash selected"); return }
        let args = pop ? ["stash", "pop", trimmed] : ["stash", "apply", trimmed]
        runGitOperation({ root in GitCommands.gitWithError(args, in: root) }, completion: completion)
    }

    func dropStash(_ reference: String, completion: @escaping (Bool, String) -> Void) {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion(false, "No stash selected"); return }
        runGitOperation({ root in GitCommands.gitWithError(["stash", "drop", trimmed], in: root) }, completion: completion)
    }

    // MARK: Remotes

    func addRemote(name: String, url: String, completion: @escaping (Bool, String) -> Void) {
        runGitOperation({ root in GitCommands.gitWithError(["remote", "add", name, url], in: root) }, completion: completion)
    }

    func updateRemote(name: String, url: String, completion: @escaping (Bool, String) -> Void) {
        runGitOperation({ root in GitCommands.gitWithError(["remote", "set-url", name, url], in: root) }, completion: completion)
    }

    func removeRemote(name: String, completion: @escaping (Bool, String) -> Void) {
        runGitOperation({ root in GitCommands.gitWithError(["remote", "remove", name], in: root) }, completion: completion)
    }

    func fetch(completion: @escaping (Bool, String) -> Void) {
        runGitOperation({ root in GitCommands.gitWithError(["fetch", "--all", "--prune"], in: root) }, completion: completion)
    }

    func pull(completion: @escaping (Bool, String) -> Void) {
        guard !upstreamBranch.isEmpty else { completion(false, "No upstream configured"); return }
        runGitOperation({ root in GitCommands.gitWithError(["pull", "--ff-only"], in: root) }, completion: completion)
    }

    func push(completion: @escaping (Bool, String) -> Void) {
        guard !upstreamBranch.isEmpty else { completion(false, "No upstream. Publish first."); return }
        runGitOperation({ root in GitCommands.gitWithError(["push"], in: root) }, completion: completion)
    }

    func publishCurrentBranch(completion: @escaping (Bool, String) -> Void) {
        guard !currentBranch.isEmpty else { completion(false, "No active branch"); return }
        guard let remoteName = preferredRemoteName else { completion(false, "Add a remote first"); return }
        let branch = currentBranch
        runGitOperation({ root in GitCommands.gitWithError(["push", "-u", remoteName, branch], in: root) }, completion: completion)
    }

    func initRepo(completion: @escaping (Bool, String) -> Void) {
        runGitOperation({ root in GitCommands.gitWithError(["init"], in: root) }, completion: completion)
    }

    var preferredRemoteName: String? {
        remotes.contains(where: { $0.name == "origin" }) ? "origin" : remotes.first?.name
    }

    // MARK: Private helpers

    private func runGitCmd(_ args: [String]) {
        guard let root = projectRoot else { return }
        isBusy = true
        Task {
            _ = await Task.detached(priority: .utility) { GitCommands.git(args, in: root) }.value
            self.isBusy = false; self.refresh()
            self.worktreeChangeToken &+= 1
            if let p = selectedDiffPath { self.loadDiff(for: p) }
        }
    }

    private func runGitOperation(
        _ operation: @escaping @Sendable (URL) -> (String?, String?),
        completion: @escaping (Bool, String) -> Void
    ) {
        guard let root = projectRoot else { completion(false, "No project attached"); return }
        isBusy = true
        Task {
            let (out, err) = await Task.detached(priority: .utility) { operation(root) }.value
            let ok = out != nil
            let message = GitCommands.commandMessage(stdout: out, stderr: err, fallback: ok ? "Done" : "Git command failed")
            self.isBusy = false; self.lastError = ok ? nil : message
            self.refresh()
            self.worktreeChangeToken &+= 1
            if let p = selectedDiffPath { self.loadDiff(for: p) }
            completion(ok, message)
        }
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }

}

// MARK: - Git command layer
//
// Pure, isolation-free git plumbing. Kept out of the `@Observable` GitStatusService
// class so the class stays small enough for the Swift type-checker to resolve its
// construction quickly (these static bodies otherwise dominate that cost).
enum GitCommands {

    // MARK: Git binary (no sandbox - auto-detect from common paths or PATH)

    nonisolated static let candidateGitPaths: [String] = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
        "/usr/bin/git",
    ]

    nonisolated static var gitPath: String {
        for path in candidateGitPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "git"   // fall back to whatever is in PATH
    }

    // MARK: Git execution

    @discardableResult
    nonisolated static func git(_ args: [String], in root: URL) -> String? {
        let process = Process()
        process.executableURL    = URL(fileURLWithPath: gitPath)
        process.arguments        = args
        process.currentDirectoryURL = root
        process.environment      = gitEnvironment()
        let outPipe = Pipe(); let errPipe = Pipe()
        process.standardOutput   = outPipe
        process.standardError    = errPipe
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    nonisolated static func gitWithError(_ args: [String], in root: URL) -> (String?, String?) {
        let process = Process()
        process.executableURL    = URL(fileURLWithPath: gitPath)
        process.arguments        = args
        process.currentDirectoryURL = root
        process.environment      = gitEnvironment()
        let outPipe = Pipe(); let errPipe = Pipe()
        process.standardOutput   = outPipe
        process.standardError    = errPipe
        do { try process.run() } catch { return (nil, "Failed to launch git: \(error.localizedDescription)") }
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            let parts = [out, err].compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            let message = parts.isEmpty ? "exit \(process.terminationStatus)" : parts.joined(separator: "\n")
            return (nil, message)
        }
        return (out, nil)
    }

    nonisolated static func gitOutput(_ args: [String], in root: URL, allowedExitCodes: Set<Int> = [0]) -> String? {
        let process = Process()
        process.executableURL    = URL(fileURLWithPath: gitPath)
        process.arguments        = args
        process.currentDirectoryURL = root
        process.environment      = gitEnvironment()
        let outPipe = Pipe(); let errPipe = Pipe()
        process.standardOutput   = outPipe
        process.standardError    = errPipe
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard allowedExitCodes.contains(Int(process.terminationStatus)) else { return nil }
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    nonisolated static func gitEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"]                = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["HOME"]                = NSHomeDirectory()
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_SSH_COMMAND"]     = "ssh -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR"
        return env
    }

    // MARK: Diff

    nonisolated static func diffOutput(for relativePath: String, state: GitFileState?, in root: URL) -> String {
        var sections: [String] = []

        if state?.hasStagedChanges == true {
            if let out = gitOutput(["diff", "--cached", "--", relativePath], in: root),
               !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append(out)
            }
        }

        if state?.hasUnstagedChanges == true {
            let isUntrackedAdded: Bool
            if case .added? = state?.status, state?.hasStagedChanges != true {
                isUntrackedAdded = true
            } else {
                isUntrackedAdded = false
            }
            if isUntrackedAdded {
                let absPath = root.appendingPathComponent(relativePath).path
                if let out = gitOutput(["diff", "--no-index", "--", "/dev/null", absPath], in: root, allowedExitCodes: [0, 1]),
                   !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections.append(out)
                }
            } else if let out = gitOutput(["diff", "--", relativePath], in: root),
                      !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append(out)
            }
        }

        if !sections.isEmpty { return sections.joined(separator: "\n") }

        let absPath = root.appendingPathComponent(relativePath).path
        if let out = gitOutput(["diff", "--no-index", "--", "/dev/null", absPath], in: root, allowedExitCodes: [0, 1]),
           !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return out
        }
        return ""
    }

    nonisolated static func compareRefs(from fromRef: String, to toRef: String, in root: URL) -> (GitCompareResult?, String?) {
        let diff = gitOutput(["diff", fromRef, toRef], in: root, allowedExitCodes: [0, 1])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawFiles = gitOutput(["diff", "--name-status", fromRef, toRef], in: root, allowedExitCodes: [0, 1])?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if diff.isEmpty, rawFiles == nil {
            let (_, err) = gitWithError(["diff", "--name-status", fromRef, toRef], in: root)
            return (nil, commandMessage(stdout: nil, stderr: err, fallback: "Failed to compare refs"))
        }

        let files = (rawFiles ?? "")
            .components(separatedBy: .newlines)
            .compactMap { line -> GitCommitFileChange? in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard let status = parts.first, parts.count >= 2 else { return nil }
                return GitCommitFileChange(status: String(status), path: String(parts.last ?? ""))
            }

        return (GitCompareResult(fromRef: fromRef, toRef: toRef, files: files, diff: diff), nil)
    }

    nonisolated static func commitDetail(for commitID: String, in root: URL) -> GitCommitDetail {
        let trimmedID = commitID.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = gitOutput(["show", "-s", "--format=%B", trimmedID], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawFiles = gitOutput(["diff-tree", "--no-commit-id", "--name-status", "-r", "-m", trimmedID], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let files = rawFiles
            .components(separatedBy: .newlines)
            .compactMap { line -> GitCommitFileChange? in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard let status = parts.first, parts.count >= 2 else { return nil }
                let path = String(parts.last ?? "")
                return GitCommitFileChange(status: String(status), path: path)
            }
        let diff = gitOutput(["show", "--format=fuller", "--patch", trimmedID], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GitCommitDetail(commitID: trimmedID, body: body, files: files, diff: diff)
    }

    // MARK: Unstage

    nonisolated static func unstage(_ relativePath: String, state: GitFileState?, in root: URL) -> Bool {
        if git(["restore", "--staged", "--", relativePath], in: root) != nil { return true }
        if case .added? = state?.status {
            return git(["rm", "--cached", "--", relativePath], in: root) != nil
        }
        return false
    }

    nonisolated static func discard(_ relativePath: String, state: GitFileState, in root: URL) -> (String?, String?) {
        if case .added = state.status {
            _ = gitWithError(["restore", "--staged", "--", relativePath], in: root)
            _ = gitWithError(["rm", "-f", "--cached", "--", relativePath], in: root)
            do {
                let url = root.appendingPathComponent(relativePath)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return ("Discarded \(relativePath)", nil)
            } catch {
                return (nil, "Failed to remove added file: \(error.localizedDescription)")
            }
        }

        let restore = gitWithError(["restore", "--source=HEAD", "--staged", "--worktree", "--", relativePath], in: root)
        if restore.0 != nil { return ("Discarded \(relativePath)", nil) }
        return gitWithError(["checkout", "--", relativePath], in: root)
    }

    nonisolated static func discardAll(in root: URL) -> (String?, String?) {
        let restore = gitWithError(["restore", "--source=HEAD", "--staged", "--worktree", "--", "."], in: root)
        if restore.0 == nil, let err = restore.1, !err.isEmpty {
            return restore
        }
        let clean = gitWithError(["clean", "-fd"], in: root)
        if clean.0 == nil && clean.1 != nil {
            return clean
        }
        return ("Discarded all local changes", nil)
    }

    nonisolated static func resolveConflict(_ relativePath: String, using strategy: GitConflictResolutionStrategy, in root: URL) -> (String?, String?) {
        switch strategy {
        case .ours:
            let checkout = gitWithError(["checkout", "--ours", "--", relativePath], in: root)
            guard checkout.0 != nil else { return checkout }
            return gitWithError(["add", "--", relativePath], in: root)

        case .theirs:
            let checkout = gitWithError(["checkout", "--theirs", "--", relativePath], in: root)
            guard checkout.0 != nil else { return checkout }
            return gitWithError(["add", "--", relativePath], in: root)

        case .markResolved:
            return gitWithError(["add", "--", relativePath], in: root)

        case .both:
            let fileURL = root.appendingPathComponent(relativePath)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return (nil, "Accept Both currently supports UTF-8 text files only")
            }
            guard let resolved = acceptBothConflicts(in: content) else {
                return (nil, "No standard conflict markers found to merge both sides")
            }
            do {
                try resolved.write(to: fileURL, atomically: true, encoding: .utf8)
                return gitWithError(["add", "--", relativePath], in: root)
            } catch {
                return (nil, "Failed to write resolved file: \(error.localizedDescription)")
            }
        }
    }

    nonisolated static func acceptBothConflicts(in content: String) -> String? {
        let hadTrailingNewline = content.hasSuffix("\n")
        let lines = content.components(separatedBy: "\n")
        var output: [String] = []
        var ours: [String] = []
        var theirs: [String] = []
        enum ParseState { case normal, ours, theirs }
        var state: ParseState = .normal
        var foundConflict = false

        for line in lines {
            switch state {
            case .normal:
                if line.hasPrefix("<<<<<<<") {
                    state = .ours
                    ours.removeAll(keepingCapacity: true)
                    theirs.removeAll(keepingCapacity: true)
                    foundConflict = true
                } else {
                    output.append(line)
                }
            case .ours:
                if line.hasPrefix("=======") {
                    state = .theirs
                } else {
                    ours.append(line)
                }
            case .theirs:
                if line.hasPrefix(">>>>>>>") {
                    output.append(contentsOf: ours)
                    output.append(contentsOf: theirs)
                    state = .normal
                } else {
                    theirs.append(line)
                }
            }
        }

        guard foundConflict else { return nil }
        guard case .normal = state else { return nil }
        let result = output.joined(separator: "\n")
        return hadTrailingNewline ? result + "\n" : result
    }

    // MARK: Message formatting

    nonisolated static func commandMessage(stdout: String?, stderr: String?, fallback: String) -> String {
        let out = stdout?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !out.isEmpty { return out }
        let err = (stderr ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Warning: Permanently added") }
            .joined(separator: "\n")
        return err.isEmpty ? fallback : err
    }

    // MARK: Parsing

    nonisolated static func runGitLog(in root: URL) -> [GitCommit] {
        let sep = "\u{1F}"
        let fmt = "%H\(sep)%h\(sep)%s\(sep)%an\(sep)%ar\(sep)%ai\(sep)%P\(sep)%D"
        guard let raw = git(["log", "--format=\(fmt)", "--all", "--topo-order", "-200"], in: root) else { return [] }
        return raw.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: sep)
            guard parts.count >= 6 else { return nil }
            let parents = parts.count >= 7
                ? parts[6].split(separator: " ").map(String.init)
                : []
            let refs = parts.count >= 8
                ? parts[7].components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            return GitCommit(id: parts[0], shortHash: parts[1], message: parts[2],
                             author: parts[3], date: parts[4], fullDate: parts[5],
                             parents: parents, refs: refs)
        }
    }

    nonisolated static func runGitBranches(in root: URL) -> ([GitBranch], String) {
        guard let raw = git(["branch", "-a", "--format=%(HEAD) %(refname:short)"], in: root) else { return ([], "") }
        var current = ""
        let branches: [GitBranch] = raw.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            let isCurrent = trimmed.hasPrefix("* ")
            let name = isCurrent ? String(trimmed.dropFirst(2)) : trimmed
            guard !name.contains(" -> ") else { return nil }
            if isCurrent { current = name }
            return GitBranch(name: name, isCurrent: isCurrent, isRemote: name.hasPrefix("remotes/"))
        }
        if current.isEmpty { current = branches.first(where: { !$0.isRemote })?.name ?? "" }
        return (branches, current)
    }

    nonisolated static func runGitRemotes(in root: URL) -> [GitRemote] {
        guard let raw = git(["remote", "-v"], in: root) else { return [] }
        var seen = Set<String>(); var remotes: [GitRemote] = []
        for line in raw.components(separatedBy: "\n") {
            let parts = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
            guard parts.count >= 2 else { continue }
            let name = String(parts[0]); let url = String(parts[1])
            guard seen.insert(name).inserted else { continue }
            remotes.append(GitRemote(name: name, url: url))
        }
        return remotes.sorted { $0.name == "origin" ? true : $1.name == "origin" ? false : $0.name < $1.name }
    }

    nonisolated static func runGitTags(in root: URL) -> [GitTag] {
        guard let raw = git(["tag", "--list", "--format=%(refname:short)%x1f%(objectname:short)%x1f%(subject)"], in: root) else { return [] }
        return raw.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\u{1F}")
            guard parts.count >= 2, !parts[0].isEmpty else { return nil }
            return GitTag(name: parts[0], targetShortHash: parts[1], subject: parts.count >= 3 ? parts[2] : "")
        }
    }

    nonisolated static func runGitStashes(in root: URL) -> [GitStash] {
        guard let raw = git(["stash", "list", "--format=%gd%x1f%gs"], in: root) else { return [] }
        return raw.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\u{1F}")
            guard parts.count >= 1, !parts[0].isEmpty else { return nil }
            return GitStash(reference: parts[0], message: parts.count >= 2 ? parts[1] : "")
        }
    }

    nonisolated static func runGitOperationState(in root: URL) -> GitRepositoryOperation? {
        guard let gitDirText = gitOutput(["rev-parse", "--git-dir"], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !gitDirText.isEmpty else { return nil }

        let gitDirURL: URL
        if gitDirText.hasPrefix("/") {
            gitDirURL = URL(fileURLWithPath: gitDirText)
        } else {
            gitDirURL = root.appendingPathComponent(gitDirText)
        }

        let fm = FileManager.default
        if fm.fileExists(atPath: gitDirURL.appendingPathComponent("MERGE_HEAD").path) {
            return .merge
        }
        if fm.fileExists(atPath: gitDirURL.appendingPathComponent("CHERRY_PICK_HEAD").path) {
            return .cherryPick
        }
        if fm.fileExists(atPath: gitDirURL.appendingPathComponent("rebase-merge").path) ||
            fm.fileExists(atPath: gitDirURL.appendingPathComponent("rebase-apply").path) {
            return .rebase
        }
        return nil
    }

    fileprivate nonisolated static func runGitUpstreamStatus(in root: URL) -> GitUpstreamStatus {
        let upstream = git(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !upstream.isEmpty else { return .empty }
        let countsText = gitOutput(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], in: root)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = countsText.split(whereSeparator: \.isWhitespace)
        return GitUpstreamStatus(
            upstreamBranch: upstream,
            aheadCount:  parts.indices.contains(0) ? Int(parts[0]) ?? 0 : 0,
            behindCount: parts.indices.contains(1) ? Int(parts[1]) ?? 0 : 0
        )
    }

    nonisolated static func runGitStatus(in root: URL) -> [String: GitFileState] {
        guard let output = git(["status", "--porcelain", "-u"], in: root) else { return [:] }
        var result: [String: GitFileState] = [:]
        for line in output.components(separatedBy: "\n") {
            guard line.count >= 3 else { continue }
            let x = line.first ?? " "
            let y = line.dropFirst().first ?? " "
            let raw = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            // Git quotes paths that contain spaces or special characters when core.quotePath=true (the default).
            // Handle rename ("old -> new") after stripping any surrounding quotes from each component.
            let finalPath = raw
                .components(separatedBy: " -> ")
                .last
                .map { gitUnquotePath($0) } ?? gitUnquotePath(raw)
            result[finalPath] = GitFileState(
                status: fileStatus(for: x, workTree: y),
                hasStagedChanges:   x != " " && x != "?",
                hasUnstagedChanges: y != " "
            )
        }
        return result
    }

    /// Strips surrounding double-quotes that git adds for paths containing spaces or
    /// non-ASCII characters, and unescapes C-style escape sequences (\\, \", \n, \t, \NNN).
    nonisolated static func gitUnquotePath(_ s: String) -> String {
        guard s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 else { return s }
        let chars = Array(s.dropFirst().dropLast())
        var result = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\" && i + 1 < chars.count {
                let esc = chars[i + 1]
                switch esc {
                case "\"": result.append("\""); i += 2
                case "\\": result.append("\\"); i += 2
                case "n":  result.append("\n"); i += 2
                case "t":  result.append("\t"); i += 2
                case "r":  result.append("\r"); i += 2
                case "a":  result.append("\u{07}"); i += 2
                case "b":  result.append("\u{08}"); i += 2
                case "0", "1", "2", "3", "4", "5", "6", "7":
                    // Octal: 1–3 octal digits
                    var octal = String(esc)
                    var j = i + 2
                    while j < chars.count && octal.count < 3
                          && chars[j] >= "0" && chars[j] <= "7" {
                        octal.append(chars[j]); j += 1
                    }
                    if let scalar = UInt32(octal, radix: 8), let unicode = Unicode.Scalar(scalar) {
                        result.append(Character(unicode))
                    } else {
                        result.append("\\"); result.append(esc)
                    }
                    i = j
                default:
                    result.append("\\"); result.append(esc); i += 2
                }
            } else {
                result.append(ch); i += 1
            }
        }
        return result
    }

    nonisolated static func fileStatus(for index: Character, workTree: Character) -> GitFileStatus {
        switch (index, workTree) {
        case ("?", "?"):                              return .added
        case ("A", _), (_, "A"):                     return .added
        case ("D", _), (_, "D"):                     return .deleted
        case ("R", _), (_, "R"):                     return .renamed
        case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): return .unmerged
        default:                                     return .modified
        }
    }
}

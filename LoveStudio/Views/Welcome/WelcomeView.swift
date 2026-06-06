import SwiftUI

struct WelcomeView: View {

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            Divider()
            rightPanel
        }
        .background(.windowBackground)
    }

    // MARK: Left Panel — Branding

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 52))
                .foregroundStyle(.pink)

            Text("LÖVE Studio")
                .font(.largeTitle.bold())

            Text("Game Development Environment")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Version 1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(36)
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(.quinary)
    }

    // MARK: Right Panel — Actions + Recents

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionButtons
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 20)

            Divider()

            recentProjectsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            WelcomeActionButton(
                icon: "plus.square.fill",
                title: "New Project",
                subtitle: "Create a new LÖVE game project"
            ) {
                createNewProject()
            }

            WelcomeActionButton(
                icon: "folder.fill",
                title: "Open Project",
                subtitle: "Open an existing project folder"
            ) {
                openExistingProject()
            }
        }
    }

    private var recentProjectsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Projects")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if RecentProjectsStore.shared.projects.isEmpty {
                Text("No recent projects")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(RecentProjectsStore.shared.projects) { entry in
                            RecentProjectRow(entry: entry) {
                                openProject(url: entry.url)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: Actions

    private func createNewProject() {
        let panel = NSOpenPanel()
        panel.title = "Choose location for new project"
        panel.prompt = "Create Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Create minimal project structure
        let mainLua = url.appendingPathComponent("main.lua")
        let confLua = url.appendingPathComponent("conf.lua")

        let mainContent = """
function love.load()
end

function love.update(dt)
end

function love.draw()
end
"""

        let confContent = """
function love.conf(t)
    t.title = "\(url.lastPathComponent)"
    t.window.width = 800
    t.window.height = 600
end
"""

        try? mainContent.write(to: mainLua, atomically: true, encoding: .utf8)
        try? confContent.write(to: confLua, atomically: true, encoding: .utf8)

        openProject(url: url)
    }

    private func openExistingProject() {
        let panel = NSOpenPanel()
        panel.title = "Open LÖVE Project"
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url: url)
    }

    private func openProject(url: URL) {
        RecentProjectsStore.shared.add(url: url)
        openWindow(id: "studio", value: url)
        dismissWindow(id: "welcome")
    }
}

// MARK: - WelcomeActionButton

private struct WelcomeActionButton: View {

    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.pink)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - RecentProjectRow

private struct RecentProjectRow: View {

    let entry: RecentProjectEntry
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.pink.opacity(0.8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body)
                        .lineLimit(1)
                    Text(entry.url.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview {
    WelcomeView()
        .frame(width: 760, height: 460)
}

import SwiftUI

@main
struct LoveStudioApp: App {

    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Scene {

        // MARK: Welcome Window
        Window("Welcome to LÖVE Studio", id: "welcome") {
            WelcomeView()
                .frame(width: 760, height: 460)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()

        // MARK: Studio Window
        WindowGroup(id: "studio", for: URL.self) { $projectURL in
            if let url = projectURL {
                StudioView(projectURL: url)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 800)
        .defaultPosition(.center)
    }
}

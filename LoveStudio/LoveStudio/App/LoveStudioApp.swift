import SwiftUI
import AppKit

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Disable macOS window state restoration so the app always opens at Welcome.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        UserDefaults.standard.set(true,  forKey: "ApplePersistenceIgnoreState")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Kada korisnik klikne na Dock ikonicu a nema otvorenih prozora - otvori Welcome
        if !flag {
            for window in sender.windows {
                if window.identifier?.rawValue == "welcome" {
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
            NSApp.sendAction(Selector(("showWelcome:")), to: nil, from: nil)
        }
        return true
    }
}

// MARK: - App

@main
struct LoveStudioApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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

        // MARK: Tilemap Editor Window
        WindowGroup(id: "tilemap-editor", for: URL.self) { $projectURL in
            if let url = projectURL {
                TilemapEditorView(projectURL: url)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 800)
        .defaultPosition(.center)

        // MARK: Animation Editor Window
        WindowGroup(id: "animation-editor", for: URL.self) { $projectURL in
            if let url = projectURL {
                AnimationManagerView(projectURL: url)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1160, height: 740)
        .defaultPosition(.center)

        // MARK: Image Editor Window
        WindowGroup(id: "image-editor", for: URL.self) { $projectURL in
            if let url = projectURL {
                ImageEditorView(projectURL: url)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 980, height: 700)
        .defaultPosition(.center)

        // MARK: UI Builder Window
        WindowGroup(id: "ui-builder", for: URL.self) { $projectURL in
            if let url = projectURL {
                UIBuilderView(projectURL: url)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1060, height: 680)
        .defaultPosition(.center)

        // MARK: Scene Manager Window
        WindowGroup(id: "scene-manager", for: URL.self) { $projectURL in
            if let url = projectURL {
                SceneManagerView(projectURL: url)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1220, height: 720)
        .defaultPosition(.center)

        // MARK: Particle Editor Window
        WindowGroup(id: "particle-editor", for: URL.self) { $projectURL in
            if let url = projectURL {
                ParticleEditorView(projectURL: url)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 880, height: 700)
        .defaultPosition(.center)

        // MARK: Audio Manager Window
        WindowGroup(id: "audio-manager", for: URL.self) { $projectURL in
            if let url = projectURL {
                AudioManagerView(projectURL: url)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 900, height: 560)
        .defaultPosition(.center)

        // MARK: Spritesheet Packer Window
        WindowGroup(id: "spritesheet-packer", for: URL.self) { $projectURL in
            if let url = projectURL {
                SpritesheetPackerView(projectURL: url)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)

        // MARK: Settings
        Settings {
            SettingsView()
        }
    }
}

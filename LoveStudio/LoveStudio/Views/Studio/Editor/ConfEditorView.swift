import SwiftUI

struct ConfEditorView: View {
    let confURL: URL
    var onSaved: ((URL) -> Void)? = nil

    @State private var conf: ConfLua = ConfLua()

    private let presets: [(String, Int, Int)] = [
        ("320 × 180 (Pixel Art)", 320, 180),
        ("640 × 360", 640, 360),
        ("800 × 600", 800, 600),
        ("1024 × 768", 1024, 768),
        ("1280 × 720 (HD)", 1280, 720),
        ("1920 × 1080 (Full HD)", 1920, 1080),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Window
                ConfSection(title: "Window", icon: "macwindow") {
                    VStack(spacing: 12) {
                        ConfRow(label: "Title") {
                            TextField("Game title", text: $conf.title)
                                .textFieldStyle(.roundedBorder)
                        }

                        ConfRow(label: "LÖVE version") {
                            TextField("e.g. 11.5", text: $conf.version)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }

                        ConfRow(label: "Resolution") {
                            HStack(spacing: 8) {
                                TextField("W", value: $conf.width, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text("×").foregroundStyle(.secondary)
                                TextField("H", value: $conf.height, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Menu("Preset") {
                                    ForEach(presets, id: \.0) { name, w, h in
                                        Button(name) {
                                            conf.width  = w
                                            conf.height = h
                                        }
                                    }
                                }
                                .fixedSize()
                            }
                        }

                        ConfRow(label: "Fullscreen") {
                            Toggle("", isOn: $conf.fullscreen)
                                .toggleStyle(.switch)
                            if conf.fullscreen {
                                Picker("", selection: $conf.fullscreenType) {
                                    ForEach(ConfLua.FullscreenType.allCases) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .fixedSize()
                            }
                        }

                        ConfRow(label: "Resizable") {
                            Toggle("", isOn: $conf.resizable).toggleStyle(.switch)
                        }

                        ConfRow(label: "Borderless") {
                            Toggle("", isOn: $conf.borderless).toggleStyle(.switch)
                        }

                        ConfRow(label: "MSAA") {
                            Picker("", selection: $conf.msaa) {
                                Text("Off").tag(0)
                                Text("2x").tag(2)
                                Text("4x").tag(4)
                                Text("8x").tag(8)
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                        }

                        ConfRow(label: "VSync") {
                            Picker("", selection: $conf.vsync) {
                                Text("Off").tag(0)
                                Text("On").tag(1)
                                Text("Adaptive").tag(-1)
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                    }
                }

                // MARK: Identity
                ConfSection(title: "Identity", icon: "tag") {
                    VStack(alignment: .leading, spacing: 8) {
                        ConfRow(label: "Save folder") {
                            TextField("e.g. mygame", text: $conf.identity)
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("Folder where LÖVE stores save files (empty = use title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Modules
                ConfSection(title: "Modules", icon: "square.grid.2x2") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Disable unused modules to reduce memory footprint")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [
                                GridItem(.fixed(140), alignment: .leading),
                                GridItem(.fixed(140), alignment: .leading),
                                GridItem(.fixed(140), alignment: .leading),
                            ],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ConfModuleToggle(name: "Audio",       value: $conf.moduleAudio)
                            ConfModuleToggle(name: "Data",        value: $conf.moduleData)
                            ConfModuleToggle(name: "Event",       value: $conf.moduleEvent)
                            ConfModuleToggle(name: "Font",        value: $conf.moduleFont)
                            ConfModuleToggle(name: "Graphics",    value: $conf.moduleGraphics)
                            ConfModuleToggle(name: "Image",       value: $conf.moduleImage)
                            ConfModuleToggle(name: "Joystick",    value: $conf.moduleJoystick)
                            ConfModuleToggle(name: "Keyboard",    value: $conf.moduleKeyboard)
                            ConfModuleToggle(name: "Math",        value: $conf.moduleMath)
                            ConfModuleToggle(name: "Mouse",       value: $conf.moduleMouse)
                            ConfModuleToggle(name: "Physics",     value: $conf.modulePhysics)
                            ConfModuleToggle(name: "Sound",       value: $conf.moduleSound)
                            ConfModuleToggle(name: "System",      value: $conf.moduleSystem)
                            ConfModuleToggle(name: "Thread",      value: $conf.moduleThread)
                            ConfModuleToggle(name: "Timer",       value: $conf.moduleTimer)
                            ConfModuleToggle(name: "Touchscreen", value: $conf.moduleTouchscreen)
                            ConfModuleToggle(name: "Video",       value: $conf.moduleVideo)
                            ConfModuleToggle(name: "Window",      value: $conf.moduleWindow)
                        }
                    }
                }

            }
        }
        .onAppear { conf = ConfLuaParser.parse(from: confURL) }
        .onChange(of: conf) { _, _ in writeConf() }
    }

    private func writeConf() {
        let generated = ConfLuaParser.generate(conf)
        try? generated.write(to: confURL, atomically: true, encoding: .utf8)
        onSaved?(confURL)
    }
}

// MARK: - Section

struct ConfSection<Content: View>: View {
    let title  : String
    let icon   : String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(Color(red: 1.0, green: 0.28, blue: 0.58))
                Text(title)
                    .font(.headline)
            }
            .padding(.bottom, 2)
            content()
        }
        .padding(20)

        Divider().padding(.horizontal, 20)
    }
}

// MARK: - Row

struct ConfRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            content()
            Spacer()
        }
    }
}

// MARK: - Module toggle

private struct ConfModuleToggle: View {
    let name : String
    @Binding var value: Bool

    var body: some View {
        Toggle(name, isOn: $value)
            .toggleStyle(.checkbox)
            .font(.body)
    }
}

import SwiftUI
import AppKit

struct AboutView: View {

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var loveVersion: String {
        let loveApp = Bundle.main.url(forResource: "love", withExtension: "app",
                                      subdirectory: "LoveRuntime")
        let plist = loveApp?.appendingPathComponent("Contents/Info.plist")
        if let p = plist, let dict = NSDictionary(contentsOf: p),
           let v = dict["CFBundleShortVersionString"] as? String { return v }
        return "11.x"
    }

    var body: some View {
        VStack(spacing: 0) {

            // Header
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.pink.opacity(0.8), Color.red.opacity(0.6)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                }
                .shadow(color: .pink.opacity(0.4), radius: 12, y: 4)

                Text("LÖVE Studio")
                    .font(.system(size: 22, weight: .semibold))

                Text("Version \(appVersion)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 24)

            // Info grid
            VStack(spacing: 0) {
                infoRow(label: "Developer", value: "Miloš Milićević")
                infoRow(label: "LÖVE Runtime", value: "love2d.org · \(loveVersion)")
                infoRow(label: "Language", value: "Swift + SwiftUI")
                infoRow(label: "Platform", value: "macOS 14+")
                infoRow(label: "License", value: "MIT")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 24)

            // Tech stack badges
            VStack(spacing: 8) {
                Text("Built with")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 8) {
                    badge("SwiftUI", color: .blue)
                    badge("Lua", color: .purple)
                    badge("LÖVE 11", color: .pink)
                    badge("MobDebug", color: .orange)
                }
            }
            .padding(.vertical, 14)

            Divider()
                .padding(.horizontal, 24)

            // Footer
            VStack(spacing: 4) {
                Text("© 2025 Miloš Milićević. All rights reserved.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Made with ♥ for the LÖVE game dev community")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
            .padding(.vertical, 14)
        }
        .frame(width: 340)
    }

    // MARK: Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .padding(.vertical, 5)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
    }
}

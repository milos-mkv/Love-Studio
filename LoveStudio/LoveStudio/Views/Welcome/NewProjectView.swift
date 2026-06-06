import SwiftUI

struct NewProjectView: View {

    let onCreate: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String = "MyGame"
    @State private var selectedTemplate: ProjectTemplate = .empty
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            Text("New Project")
                .font(.title2.bold())
                .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Project name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project Name").font(.headline)
                        TextField("MyGame", text: $projectName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Template grid
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Template").font(.headline)
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(ProjectTemplate.allCases) { template in
                                TemplateCard(
                                    template: template,
                                    isSelected: selectedTemplate == template
                                ) {
                                    selectedTemplate = template
                                }
                            }
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Project") { createProject() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(24)
        }
        .frame(width: 500, height: 520)
    }

    // MARK: Logic

    private func createProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose Location"
        panel.message = "Gde da se napravi projekt folder"

        guard panel.runModal() == .OK, let parentURL = panel.url else { return }

        let accessed = parentURL.startAccessingSecurityScopedResource()
        defer { if accessed { parentURL.stopAccessingSecurityScopedResource() } }

        let projectURL = parentURL.appendingPathComponent(
            projectName.trimmingCharacters(in: .whitespaces)
        )

        do {
            try TemplateService.shared.createProject(
                name: projectName,
                template: selectedTemplate,
                at: projectURL
            )
            dismiss()
            onCreate(projectURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - TemplateCard

private struct TemplateCard: View {

    let template: ProjectTemplate
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: template.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? .white : .pink)

                Text(template.displayName)
                    .font(.body.bold())
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? AnyShapeStyle(.pink)
                    : AnyShapeStyle(.secondary.opacity(0.1)),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NewProjectView { _ in }
}

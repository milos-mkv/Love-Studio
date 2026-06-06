import SwiftUI

struct StudioView: View {

    let projectURL: URL

    var body: some View {
        Text("Studio: \(projectURL.lastPathComponent)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.windowBackground)
            .navigationTitle(projectURL.lastPathComponent)
    }
}

#Preview {
    StudioView(projectURL: URL(filePath: "/tmp/MyGame"))
}

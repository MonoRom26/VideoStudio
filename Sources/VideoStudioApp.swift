import SwiftUI

@main
struct VideoStudioApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @StateObject private var editor = Editor()

    var body: some View {
        Group {
            if editor.hasMedia {
                EditorView(editor: editor)
            } else {
                HomeView(editor: editor)
            }
        }
    }
}

import SwiftUI

struct HomeView: View {
    @ObservedObject var editor: Editor
    @State private var pick: PickKind?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Video Studio")
                    .font(.largeTitle).bold()
                    .padding(.top, 24)

                HStack(spacing: 12) {
                    Button(action: { editor.pendingTool = nil; pick = .video }) {
                        Label("Pick video", systemImage: "video")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledStyle(color: .blue))
                    Button(action: { editor.pendingTool = nil; pick = .image }) {
                        Label("Pick photo", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledStyle(color: .purple))
                }

                if !editor.loadError.isEmpty {
                    Text(editor.loadError).font(.footnote).foregroundColor(.red)
                }

                Text("Tools")
                    .font(.subheadline).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Tool.allCases) { t in
                        Button(action: { editor.pendingTool = t; pick = .video }) {
                            VStack(spacing: 6) {
                                Image(systemName: t.icon).font(.title2).foregroundColor(.blue)
                                Text(t.title).font(.footnote).foregroundColor(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }
                }

                Text("Everything runs on your iPhone. No internet needed.")
                    .font(.footnote).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding()
        }
        .sheet(item: $pick) { kind in
            MediaPicker(kind: kind,
                        onVideo: { url in pick = nil; editor.loadVideo(url) },
                        onImage: { img in pick = nil; editor.loadPhoto(img) },
                        onCancel: { pick = nil })
        }
    }
}

struct FilledStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .cornerRadius(12)
    }
}

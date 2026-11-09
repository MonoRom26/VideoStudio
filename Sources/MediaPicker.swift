import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum PickKind: Identifiable {
    case video, image
    var id: Int { self == .video ? 0 : 1 }
}

/// Photos picker (no permission needed to pick).
struct MediaPicker: UIViewControllerRepresentable {
    let kind: PickKind
    var onVideo: (URL) -> Void = { _ in }
    var onImage: (UIImage) -> Void = { _ in }
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = kind == .video ? .videos : .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MediaPicker
        init(_ parent: MediaPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                parent.onCancel()
                return
            }
            if parent.kind == .video {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                    guard let url = url else {
                        DispatchQueue.main.async { self.parent.onCancel() }
                        return
                    }
                    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "." + ext)
                    try? FileManager.default.copyItem(at: url, to: dest)
                    DispatchQueue.main.async { self.parent.onVideo(dest) }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    DispatchQueue.main.async {
                        if let img = obj as? UIImage { self.parent.onImage(img) } else { self.parent.onCancel() }
                    }
                }
            } else {
                parent.onCancel()
            }
        }
    }
}

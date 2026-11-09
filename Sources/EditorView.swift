import SwiftUI

enum EditorSheet: Identifiable {
    case export, overlayImage
    var id: Int { self == .export ? 0 : 1 }
}

struct EditorView: View {
    @ObservedObject var editor: Editor
    @State private var tool: Tool = .trim
    @State private var sheet: EditorSheet?
    @State private var drawMode = false
    @State private var drawStart: CGPoint?
    @State private var drawCurrent: CGPoint?

    private var tools: [Tool] {
        Tool.allCases.filter { !(editor.isPhoto && $0.videoOnly) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            preview
            if !editor.isPhoto { controls }
            toolStrip
            Divider()
            ScrollView {
                panel.padding()
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .export:
                ExportSheet(editor: editor, onClose: { sheet = nil })
            case .overlayImage:
                MediaPicker(kind: .image,
                            onImage: { img in editor.addImageOverlay(img); sheet = nil },
                            onCancel: { sheet = nil })
            }
        }
        .onAppear {
            if let t = editor.pendingTool, !(editor.isPhoto && t.videoOnly) {
                tool = t
            } else {
                tool = editor.isPhoto ? .crop : .trim
            }
        }
        .onDisappear { editor.player.pause() }
    }

    // MARK: top bar
    private var topBar: some View {
        HStack {
            Button(action: { editor.close() }) {
                Image(systemName: "xmark").font(.headline)
            }
            Spacer()
            Text(editor.isPhoto ? "Photo" : "Video").font(.headline)
            Spacer()
            Button(action: { editor.exportState = .idle; sheet = .export }) {
                Text("Export").bold()
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.blue).foregroundColor(.white)
                    .cornerRadius(14)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: preview
    private var preview: some View {
        ZStack {
            Color.black
            if editor.isPhoto {
                if let img = editor.photoPreview {
                    Image(uiImage: img).resizable().scaledToFit()
                }
            } else {
                PlayerView(player: editor.player)
            }
        }
        .aspectRatio(editor.outputAspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: UIScreen.main.bounds.height * 0.42)
        .overlay(GeometryReader { g in interactionLayer(g.size) })
    }

    private func interactionLayer(_ size: CGSize) -> some View {
        ZStack {
            if tool == .removeText {
                ForEach(editor.settings.regions) { r in
                    Rectangle()
                        .stroke(r.enabled ? Color.red : Color.gray, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .frame(width: r.rect.width * size.width, height: r.rect.height * size.height)
                        .position(x: r.rect.midX * size.width, y: r.rect.midY * size.height)
                }
                if let a = drawStart, let b = drawCurrent {
                    Rectangle()
                        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .frame(width: abs(b.x - a.x), height: abs(b.y - a.y))
                        .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                }
            }
            if tool == .overlay, let i = editor.selectedIndex, i < editor.settings.overlays.count {
                let o = editor.settings.overlays[i]
                let box = editor.overlayBoxes[o.id] ?? CGSize(width: 0.2, height: 0.1)
                Rectangle()
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .frame(width: box.width * size.width, height: box.height * size.height)
                    .rotationEffect(.degrees(o.rotation))
                    .position(x: CGFloat(o.x) * size.width, y: CGFloat(o.y) * size.height)
            }
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in drag(v, size, ended: false) }
                    .onEnded { v in drag(v, size, ended: true) })
        }
        .frame(width: size.width, height: size.height)
    }

    private func drag(_ v: DragGesture.Value, _ size: CGSize, ended: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, 0), size.width), y: min(max(p.y, 0), size.height))
        }
        if tool == .overlay {
            let p = clamp(v.location)
            editor.moveSelectedOverlay(x: Double(p.x / size.width), y: Double(p.y / size.height))
        } else if tool == .removeText && drawMode {
            let a = clamp(v.startLocation)
            let b = clamp(v.location)
            if ended {
                let r = CGRect(x: min(a.x, b.x) / size.width, y: min(a.y, b.y) / size.height,
                               width: abs(b.x - a.x) / size.width, height: abs(b.y - a.y) / size.height)
                if r.width > 0.01 && r.height > 0.01 { editor.addRegion(r) }
                drawStart = nil
                drawCurrent = nil
            } else {
                drawStart = a
                drawCurrent = b
            }
        }
    }

    // MARK: controls
    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: { editor.togglePlay() }) {
                Image(systemName: editor.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2).frame(width: 40)
            }
            Slider(value: Binding(
                get: { min(editor.currentTime, editor.settings.outputDuration) },
                set: { editor.seek(to: $0) }),
                   in: 0...max(0.1, editor.settings.outputDuration))
            Text(timeString(editor.currentTime) + " / " + timeString(editor.settings.outputDuration))
                .font(.system(size: 11, design: .monospaced))
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func timeString(_ t: Double) -> String {
        let v = max(0, t)
        return String(format: "%d:%04.1f", Int(v) / 60, v.truncatingRemainder(dividingBy: 60))
    }

    // MARK: tool strip
    private var toolStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tools) { t in
                    Button(action: { tool = t; drawMode = false }) {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon).font(.title3)
                            Text(t.title).font(.system(size: 10))
                        }
                        .frame(width: 66, height: 50)
                        .foregroundColor(tool == t ? .white : .primary)
                        .background(tool == t ? Color.blue : Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: panels
    @ViewBuilder
    private var panel: some View {
        switch tool {
        case .trim: TrimPanel(editor: editor)
        case .speed: SpeedPanel(editor: editor)
        case .crop: CropPanel(editor: editor)
        case .adjust: AdjustPanel(editor: editor)
        case .filter: FilterPanel(editor: editor)
        case .effect: EffectPanel(editor: editor)
        case .overlay: OverlayPanel(editor: editor, onPickImage: { sheet = .overlayImage })
        case .removeText: RemoveTextPanel(editor: editor, drawMode: $drawMode)
        case .enhance: EnhancePanel(editor: editor)
        case .audio: AudioPanel(editor: editor)
        }
    }
}

struct ExportSheet: View {
    @ObservedObject var editor: Editor
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Export").font(.title2).bold()
            Text(summary).font(.subheadline).foregroundColor(.secondary)

            switch editor.exportState {
            case .idle:
                Button(action: { editor.export() }) {
                    Text("Export & save to Photos").frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledStyle(color: .blue))
            case .working(let p):
                ProgressView(value: p)
                Text("\(Int(p * 100))%").font(.footnote).foregroundColor(.secondary)
                if !editor.isPhoto {
                    Button(action: { editor.cancelExport() }) { Text("Cancel") }
                }
            case .done:
                Text("Saved to Photos ✓").font(.headline).foregroundColor(.green)
            case .failed(let msg):
                Text(msg).font(.footnote).foregroundColor(.red).multilineTextAlignment(.center)
                Button(action: { editor.export() }) {
                    Text("Try again").frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledStyle(color: .blue))
            }

            Button(action: onClose) { Text("Close") }
            Spacer()
        }
        .padding()
    }

    private var summary: String {
        let o = editor.outputSize
        var text = "\(Int(o.width))×\(Int(o.height))"
        if !editor.isPhoto { text += String(format: " • %.1f s", editor.settings.outputDuration) }
        return text
    }
}

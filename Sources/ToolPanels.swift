import SwiftUI

// MARK: - small helpers
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.footnote)
                Spacer()
                Text(String(format: format, value)).font(.footnote).foregroundColor(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

struct ChipRow<T: Hashable>: View {
    let options: [T]
    let title: (T) -> String
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { o in
                    Button(action: { selection = o }) {
                        Text(title(o))
                            .font(.footnote)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selection == o ? Color.blue : Color(.secondarySystemBackground))
                            .foregroundColor(selection == o ? .white : .primary)
                            .cornerRadius(16)
                    }
                }
            }
        }
    }
}

struct SmallButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.footnote)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
        }
    }
}

// MARK: - Trim
struct TrimPanel: View {
    @ObservedObject var editor: Editor
    var body: some View {
        let s = editor.settings
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(title: "Start", value: $editor.settings.trimStart,
                          range: 0...max(0.1, s.trimEnd - 0.2), format: "%.1f s")
            LabeledSlider(title: "End", value: $editor.settings.trimEnd,
                          range: min(s.trimStart + 0.2, editor.duration)...max(editor.duration, 0.3), format: "%.1f s")
            Text(String(format: "Clip: %.1f s  •  After speed changes: %.1f s",
                        s.trimEnd - s.trimStart, s.outputDuration))
                .font(.footnote).foregroundColor(.secondary)
        }
    }
}

// MARK: - Speed / slow-mo
struct SpeedPanel: View {
    @ObservedObject var editor: Editor
    var body: some View {
        let s = editor.settings
        VStack(alignment: .leading, spacing: 12) {
            Text("Whole video").font(.subheadline).bold()
            ChipRow(options: [0.25, 0.5, 1.0, 1.5, 2.0, 4.0],
                    title: { String(format: "%g×", $0) },
                    selection: $editor.settings.speed)
            LabeledSlider(title: "Speed", value: $editor.settings.speed, range: 0.25...4, format: "%.2f×")

            Divider()
            Toggle(isOn: Binding(
                get: { editor.settings.sectionOn },
                set: { on in
                    editor.settings.sectionOn = on
                    if on { editor.initSection() }
                })) {
                Text("Slow-mo / speed section").font(.subheadline).bold()
            }

            if s.sectionOn {
                LabeledSlider(title: "Section start", value: $editor.settings.sectionStart,
                              range: s.trimStart...max(s.trimStart + 0.1, s.trimEnd), format: "%.1f s")
                LabeledSlider(title: "Section end", value: $editor.settings.sectionEnd,
                              range: s.trimStart...max(s.trimStart + 0.1, s.trimEnd), format: "%.1f s")
                ChipRow(options: [0.1, 0.25, 0.5, 2.0, 3.0],
                        title: { String(format: "%g×", $0) },
                        selection: $editor.settings.sectionSpeed)
                LabeledSlider(title: "Section speed", value: $editor.settings.sectionSpeed,
                              range: 0.1...4, format: "%.2f×")
            }
            Text("Times are in the original video. Slow motion looks smoothest on videos shot at 120 or 240 fps.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }
}

// MARK: - Crop / rotate
struct CropPanel: View {
    @ObservedObject var editor: Editor
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChipRow(options: AspectPreset.allCases, title: { $0.title }, selection: $editor.settings.aspect)
            LabeledSlider(title: "Zoom", value: $editor.settings.zoom, range: 1...3, format: "%.2f×")
            LabeledSlider(title: "Move left / right", value: $editor.settings.panX, range: -1...1)
            LabeledSlider(title: "Move down / up", value: $editor.settings.panY, range: -1...1)
            HStack {
                SmallButton(title: "Rotate", icon: "rotate.right") {
                    editor.settings.rotation = (editor.settings.rotation + 90) % 360
                }
                SmallButton(title: "Flip", icon: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                    editor.settings.flipH.toggle()
                }
                SmallButton(title: "Reset", icon: "arrow.counterclockwise") {
                    editor.settings.rotation = 0
                    editor.settings.flipH = false
                    editor.settings.aspect = .original
                    editor.settings.zoom = 1
                    editor.settings.panX = 0
                    editor.settings.panY = 0
                }
            }
            Text("Tip: crop and rotate first, then remove text.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }
}

// MARK: - Adjust
struct AdjustPanel: View {
    @ObservedObject var editor: Editor
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledSlider(title: "Brightness", value: $editor.settings.brightness, range: -0.5...0.5)
            LabeledSlider(title: "Contrast", value: $editor.settings.contrast, range: 0.5...1.5)
            LabeledSlider(title: "Saturation", value: $editor.settings.saturation, range: 0...2)
            LabeledSlider(title: "Warmth", value: $editor.settings.warmth, range: -1...1)
            LabeledSlider(title: "Sharpness", value: $editor.settings.sharpness, range: 0...2)
            LabeledSlider(title: "Vignette", value: $editor.settings.vignette, range: 0...1)
            SmallButton(title: "Reset", icon: "arrow.counterclockwise") {
                editor.settings.brightness = 0
                editor.settings.contrast = 1
                editor.settings.saturation = 1
                editor.settings.warmth = 0
                editor.settings.sharpness = 0
                editor.settings.vignette = 0
            }
        }
    }
}

// MARK: - Filters
struct FilterPanel: View {
    @ObservedObject var editor: Editor
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChipRow(options: FilterPreset.allCases, title: { $0.title }, selection: $editor.settings.filter)
            if editor.settings.filter != .none {
                LabeledSlider(title: "Amount", value: $editor.settings.filterAmount, range: 0...1)
            }
        }
    }
}

// MARK: - Effects
struct EffectPanel: View {
    @ObservedObject var editor: Editor
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChipRow(options: EffectPreset.allCases, title: { $0.title }, selection: $editor.settings.effect)
            if editor.settings.effect != .none {
                LabeledSlider(title: "Intensity", value: $editor.settings.effectAmount, range: 0...1)
            }
        }
    }
}

// MARK: - Overlay (text / emoji / image)
struct OverlayPanel: View {
    @ObservedObject var editor: Editor
    var onPickImage: () -> Void
    @State private var showEmoji = false

    private let emojis = ["😀", "😂", "😍", "😎", "🔥", "❤️", "👍", "🎉", "⭐️", "💯", "🚀", "🌈",
                          "🎵", "📍", "✅", "❌", "👑", "💎", "🍕", "🐶"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SmallButton(title: "Text", icon: "textformat") { editor.addText() }
                SmallButton(title: "Emoji", icon: "face.smiling") { showEmoji.toggle() }
                SmallButton(title: "Image", icon: "photo") { onPickImage() }
            }

            if showEmoji {
                let cols = [GridItem(.adaptive(minimum: 40))]
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(emojis, id: \.self) { e in
                        Button(action: { editor.addEmoji(e) }) { Text(e).font(.title) }
                    }
                }
            }

            if !editor.settings.overlays.isEmpty {
                Text("Layers").font(.subheadline).bold()
                ForEach(editor.settings.overlays) { o in
                    HStack {
                        Button(action: { editor.selectedOverlay = o.id }) {
                            HStack {
                                Image(systemName: o.kind == .image ? "photo" : "textformat")
                                Text(label(o)).lineLimit(1)
                                Spacer()
                            }
                            .padding(8)
                            .background(editor.selectedOverlay == o.id ? Color.blue.opacity(0.2) : Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        .foregroundColor(.primary)
                        Button(action: { editor.deleteOverlay(o.id) }) {
                            Image(systemName: "trash").foregroundColor(.red)
                        }
                    }
                }
            }

            if let i = editor.selectedIndex, i < editor.settings.overlays.count {
                selectedEditor(editor.settings.overlays[i])
            } else if editor.settings.overlays.isEmpty {
                Text("Add text, an emoji or an image. Drag on the preview to move it.")
                    .font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    private func label(_ o: OverlayItem) -> String {
        o.kind == .image ? "Image" : (o.text.isEmpty ? "(empty)" : o.text)
    }

    @ViewBuilder
    private func selectedEditor(_ o: OverlayItem) -> some View {
        let id = o.id
        Divider()
        VStack(alignment: .leading, spacing: 12) {
            if o.kind != .image {
                TextField("Text", text: editor.overlayBinding(id, \.text, default: ""))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            if o.kind == .text {
                ColorPicker("Color", selection: editor.overlayBinding(id, \.color, default: Color.white))
                Toggle("Bold", isOn: editor.overlayBinding(id, \.bold, default: true))
                Toggle("Dark background", isOn: editor.overlayBinding(id, \.background, default: false))
            }
            LabeledSlider(title: "Size", value: editor.overlayBinding(id, \.size, default: 0.1),
                          range: o.kind == .image ? 0.05...1 : 0.02...0.4)
            LabeledSlider(title: "Rotate", value: editor.overlayBinding(id, \.rotation, default: 0),
                          range: -180...180, format: "%.0f°")
            LabeledSlider(title: "Opacity", value: editor.overlayBinding(id, \.opacity, default: 1), range: 0.1...1)
            if !editor.isPhoto {
                let total = max(0.5, editor.settings.outputDuration)
                LabeledSlider(title: "Show from", value: editor.overlayBinding(id, \.start, default: 0),
                              range: 0...total, format: "%.1f s")
                LabeledSlider(title: "Show until",
                              value: Binding(
                                get: { min(o.end, total) },
                                set: { v in editor.overlayBinding(id, \.end, default: 3600).wrappedValue = v }),
                              range: 0...total, format: "%.1f s")
                SmallButton(title: "Show on whole video", icon: "infinity") {
                    editor.overlayBinding(id, \.start, default: 0).wrappedValue = 0
                    editor.overlayBinding(id, \.end, default: 3600).wrappedValue = 3600
                }
            }
        }
    }
}

// MARK: - Remove text
struct RemoveTextPanel: View {
    @ObservedObject var editor: Editor
    @Binding var drawMode: Bool
    @State private var padding = 0.01

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { editor.detectText(padding: padding) }) {
                Label(editor.scanning ? "Scanning…" : "Auto detect text", systemImage: "text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FilledStyle(color: .blue))
            .disabled(editor.scanning)

            if editor.scanning {
                ProgressView(value: editor.scanProgress)
            }
            if !editor.scanMessage.isEmpty {
                Text(editor.scanMessage).font(.footnote).foregroundColor(.secondary)
            }

            LabeledSlider(title: "Box padding", value: $padding, range: 0...0.04, format: "%.3f")

            Toggle("Draw a box on the preview", isOn: $drawMode)

            Text("Fill style").font(.subheadline).bold()
            ChipRow(options: FillStyle.allCases, title: { $0.title }, selection: $editor.settings.fillStyle)

            if !editor.settings.regions.isEmpty {
                Text("Areas").font(.subheadline).bold()
                ForEach(Array(editor.settings.regions.enumerated()), id: \.element.id) { idx, r in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Toggle(isOn: editor.regionBinding(r.id, \.enabled, default: true)) {
                                Text("Area \(idx + 1)").font(.footnote)
                            }
                            Button(action: { editor.deleteRegion(r.id) }) {
                                Image(systemName: "trash").foregroundColor(.red)
                            }
                        }
                        if !editor.isPhoto {
                            Toggle(isOn: editor.regionBinding(r.id, \.wholeVideo, default: true)) {
                                Text(r.wholeVideo ? "Whole video"
                                     : String(format: "From %.1f s to %.1f s (original video)", r.start, r.end))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }

            Text("Works best on small, still text such as captions and watermarks over simple backgrounds. Busy or moving backgrounds can leave traces. Do crop and rotate first.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }
}

// MARK: - Enhance HD
struct EnhancePanel: View {
    @ObservedObject var editor: Editor
    var body: some View {
        let o = editor.outputSize
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $editor.settings.enhance) {
                VStack(alignment: .leading) {
                    Text("Enhance HD").font(.subheadline).bold()
                    Text("Upscales 2× and reduces noise and softness").font(.caption).foregroundColor(.secondary)
                }
            }
            Text("Output size").font(.subheadline).bold()
            ChipRow(options: ResolutionPreset.allCases, title: { $0.title }, selection: $editor.settings.resolution)
            Text("Result: \(Int(o.width))×\(Int(o.height))")
                .font(.footnote).foregroundColor(.secondary)
            Text("This sharpens and enlarges the picture on your iPhone. It does not add new detail like AI upscalers. 4K exports are slow on older iPhones.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }
}

// MARK: - Audio
struct AudioPanel: View {
    @ObservedObject var editor: Editor
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Mute video", isOn: $editor.settings.muted)
            LabeledSlider(title: "Volume", value: $editor.settings.volume, range: 0...2, format: "%.2f")
                .disabled(editor.settings.muted)
        }
    }
}

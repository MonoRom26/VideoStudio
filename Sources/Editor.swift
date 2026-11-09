import SwiftUI
import AVFoundation
import Photos
import CoreImage

enum ExportState {
    case idle
    case working(Double)
    case done
    case failed(String)
}

private struct Cluster {
    var rect: CGRect
    var first: Double
    var last: Double
    var hits: Int
    var lastSample: Int
}

/// Holds the loaded media, all edit settings, the preview player and the export code.
final class Editor: ObservableObject {
    @Published var settings = EditSettings() { didSet { scheduleRebuild() } }
    @Published var hasMedia = false
    @Published var isPhoto = false
    @Published var duration = 0.0
    @Published var currentTime = 0.0
    @Published var isPlaying = false
    @Published var photoPreview: UIImage?
    @Published var overlayBoxes: [UUID: CGSize] = [:]
    @Published var selectedOverlay: UUID?
    @Published var scanning = false
    @Published var scanProgress = 0.0
    @Published var scanMessage = ""
    @Published var exportState: ExportState = .idle
    @Published var loadError = ""
    var pendingTool: Tool?

    let player = AVPlayer()
    private var asset: AVURLAsset?
    private var photoSource: UIImage?
    private var sourceSize = CGSize(width: 1920, height: 1080)
    private var fps = 30.0
    private var composition: AVMutableComposition?
    private var lastKey = ""
    private var rebuildWork: DispatchWorkItem?
    private let ciContext = CIContext()
    private let previewQueue = DispatchQueue(label: "videostudio.preview")
    private var exportSession: AVAssetExportSession?

    init() {
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
                                       queue: .main) { [weak self] t in
            let sec = t.seconds
            if sec.isFinite { self?.currentTime = sec }
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.isPlaying = false
        }
    }

    // MARK: derived
    var outputSize: CGSize {
        Geometry.outputSize(source: sourceSize, settings: settings, maxLongSide: isPhoto ? 4096 : 3840)
    }
    var outputAspect: CGFloat {
        let o = outputSize
        return max(0.1, o.width / max(1, o.height))
    }
    var selectedIndex: Int? {
        guard let id = selectedOverlay else { return nil }
        return settings.overlays.firstIndex { $0.id == id }
    }

    // MARK: loading
    func loadVideo(_ url: URL) {
        let a = AVURLAsset(url: url)
        guard let track = a.tracks(withMediaType: .video).first else {
            loadError = "Could not read this video."
            return
        }
        let n = track.naturalSize.applying(track.preferredTransform)
        sourceSize = CGSize(width: abs(n.width), height: abs(n.height))
        fps = Double(track.nominalFrameRate)
        asset = a
        photoSource = nil
        isPhoto = false
        duration = a.duration.seconds
        var s = EditSettings()
        s.trimEnd = duration
        lastKey = ""
        composition = nil
        loadError = ""
        currentTime = 0
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        hasMedia = true
        settings = s
        rebuildNow()
    }

    func loadPhoto(_ image: UIImage) {
        let ui = image.normalized(maxSide: 4096)
        guard ui.cgImage != nil else { loadError = "Could not read this photo."; return }
        photoSource = ui
        sourceSize = CGSize(width: ui.cgImage!.width, height: ui.cgImage!.height)
        asset = nil
        isPhoto = true
        duration = 0
        loadError = ""
        hasMedia = true
        settings = EditSettings()
        rebuildNow()
    }

    func close() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        hasMedia = false
        asset = nil
        photoSource = nil
        composition = nil
        photoPreview = nil
        selectedOverlay = nil
        scanMessage = ""
        exportState = .idle
        pendingTool = nil
    }

    // MARK: preview
    private func scheduleRebuild() {
        guard hasMedia else { return }
        rebuildWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.rebuildNow() }
        rebuildWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
    }

    func rebuildNow() {
        rebuildWork?.cancel()
        if isPhoto { renderPhotoPreview(); return }
        guard let asset = asset else { return }
        let s = settings
        let full = Geometry.outputSize(source: sourceSize, settings: s)
        let prev = Geometry.previewSize(full)
        let renderer = Renderer(settings: s, outSize: prev, isPhoto: false)
        overlayBoxes = renderer.normalizedSizes()

        let key = s.segments().map { "\($0.srcStart)-\($0.srcEnd)-\($0.speed)" }.joined(separator: ",")
            + "|\(s.muted)|\(s.volume)"

        if key != lastKey || composition == nil {
            guard let result = Builder.compose(asset: asset, settings: s) else { return }
            let comp = result.0
            composition = comp
            let vc = Builder.videoComposition(for: comp, renderer: renderer, size: prev, fps: fps, context: ciContext)
            let item = AVPlayerItem(asset: comp)
            item.audioMix = result.1
            item.audioTimePitchAlgorithm = .spectral
            item.videoComposition = vc
            let wasPlaying = isPlaying
            let t = player.currentTime()
            player.replaceCurrentItem(with: item)
            let limit = comp.duration
            let target = (t.isValid && CMTimeCompare(t, limit) < 0) ? t : CMTime.zero
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            if wasPlaying { player.play() }
            lastKey = key
        } else if let comp = composition {
            let vc = Builder.videoComposition(for: comp, renderer: renderer, size: prev, fps: fps, context: ciContext)
            player.currentItem?.videoComposition = vc
            if !isPlaying {
                player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    private func renderPhotoPreview() {
        guard let src = photoSource, let cg = src.cgImage else { return }
        let s = settings
        let full = Geometry.outputSize(source: sourceSize, settings: s, maxLongSide: 4096)
        let prev = Geometry.previewSize(full)
        previewQueue.async { [weak self] in
            guard let self = self else { return }
            let r = Renderer(settings: s, outSize: prev, isPhoto: true)
            let ci = r.render(CIImage(cgImage: cg), outTime: 0)
            if let out = self.ciContext.createCGImage(ci, from: CGRect(origin: .zero, size: prev)) {
                let img = UIImage(cgImage: out)
                let boxes = r.normalizedSizes()
                DispatchQueue.main.async {
                    self.photoPreview = img
                    self.overlayBoxes = boxes
                }
            }
        }
    }

    // MARK: playback
    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= settings.outputDuration - 0.05 { player.seek(to: .zero) }
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    // MARK: speed helper
    func initSection() {
        let s = settings
        if s.sectionEnd <= s.sectionStart + 0.05 || s.sectionStart < s.trimStart || s.sectionEnd > s.trimEnd {
            let span = s.trimEnd - s.trimStart
            settings.sectionStart = s.trimStart + span / 3
            settings.sectionEnd = s.trimStart + span * 2 / 3
        }
    }

    // MARK: overlays
    func overlayBinding<T>(_ id: UUID, _ kp: WritableKeyPath<OverlayItem, T>, default d: T) -> Binding<T> {
        Binding(get: { self.settings.overlays.first(where: { $0.id == id })?[keyPath: kp] ?? d },
                set: { v in
                    if let i = self.settings.overlays.firstIndex(where: { $0.id == id }) {
                        self.settings.overlays[i][keyPath: kp] = v
                    }
                })
    }

    func addText() {
        var o = OverlayItem(kind: .text)
        o.text = "Your text"
        o.size = 0.07
        settings.overlays.append(o)
        selectedOverlay = o.id
    }

    func addEmoji(_ e: String) {
        var o = OverlayItem(kind: .emoji)
        o.text = e
        o.size = 0.15
        settings.overlays.append(o)
        selectedOverlay = o.id
    }

    func addImageOverlay(_ image: UIImage) {
        let small = image.normalized(maxSide: 1024)
        guard let data = small.pngData() else { return }
        var o = OverlayItem(kind: .image)
        o.imageData = data
        o.size = 0.3
        settings.overlays.append(o)
        selectedOverlay = o.id
    }

    func deleteOverlay(_ id: UUID) {
        settings.overlays.removeAll { $0.id == id }
        if selectedOverlay == id { selectedOverlay = nil }
    }

    func moveSelectedOverlay(x: Double, y: Double) {
        guard let i = selectedIndex else { return }
        settings.overlays[i].x = x
        settings.overlays[i].y = y
    }

    // MARK: text regions
    func regionBinding<T>(_ id: UUID, _ kp: WritableKeyPath<TextRegion, T>, default d: T) -> Binding<T> {
        Binding(get: { self.settings.regions.first(where: { $0.id == id })?[keyPath: kp] ?? d },
                set: { v in
                    if let i = self.settings.regions.firstIndex(where: { $0.id == id }) {
                        self.settings.regions[i][keyPath: kp] = v
                    }
                })
    }

    func addRegion(_ rect: CGRect) {
        settings.regions.append(TextRegion(rect: rect, start: 0, end: 0, wholeVideo: true))
    }

    func deleteRegion(_ id: UUID) {
        settings.regions.removeAll { $0.id == id }
    }

    private static func pad(_ r: CGRect, _ p: Double) -> CGRect {
        let d = CGFloat(p)
        return r.insetBy(dx: -d, dy: -d).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        if i.isNull { return 0 }
        let minArea = min(a.width * a.height, b.width * b.height)
        return minArea > 0 ? (i.width * i.height) / minArea : 0
    }

    func detectText(padding: Double) {
        guard !scanning else { return }
        scanning = true
        scanProgress = 0
        scanMessage = ""
        let s = settings

        if isPhoto, let cg = photoSource?.cgImage {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let ci = Renderer.preScale(CIImage(cgImage: cg), settings: s)
                var boxes: [CGRect] = []
                if let cg2 = self.ciContext.createCGImage(ci, from: ci.extent) {
                    boxes = TextDetector.detect(cg2, accurate: true)
                }
                let regions = boxes.map {
                    TextRegion(rect: Editor.pad($0, padding), start: 0, end: 0, wholeVideo: true)
                }
                DispatchQueue.main.async { self.finishScan(regions) }
            }
            return
        }

        guard let asset = asset else { scanning = false; return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 1280, height: 1280)

            let span = max(0.1, s.trimEnd - s.trimStart)
            let step = max(0.4, span / 40)
            var times: [Double] = []
            var t = s.trimStart
            while t < s.trimEnd - 0.05 { times.append(t); t += step }
            if times.isEmpty { times = [s.trimStart] }

            var clusters: [Cluster] = []
            for (i, time) in times.enumerated() {
                if let cg = try? gen.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil) {
                    let ci = Renderer.preScale(CIImage(cgImage: cg), settings: s)
                    if let cg2 = self.ciContext.createCGImage(ci, from: ci.extent) {
                        for b in TextDetector.detect(cg2, accurate: false) {
                            if let idx = clusters.firstIndex(where: { Editor.overlapRatio($0.rect, b) > 0.5 }) {
                                clusters[idx].rect = clusters[idx].rect.union(b)
                                clusters[idx].last = time
                                if clusters[idx].lastSample != i {
                                    clusters[idx].hits += 1
                                    clusters[idx].lastSample = i
                                }
                            } else {
                                clusters.append(Cluster(rect: b, first: time, last: time, hits: 1, lastSample: i))
                            }
                        }
                    }
                }
                let p = Double(i + 1) / Double(times.count)
                DispatchQueue.main.async { self.scanProgress = p }
            }

            let minHits = times.count >= 3 ? 2 : 1
            let regions: [TextRegion] = clusters.filter { $0.hits >= minHits }.map { c in
                let whole = Double(c.hits) >= 0.7 * Double(times.count)
                return TextRegion(rect: Editor.pad(c.rect, padding),
                                  start: max(s.trimStart, c.first - step),
                                  end: min(s.trimEnd, c.last + step),
                                  wholeVideo: whole)
            }
            DispatchQueue.main.async { self.finishScan(regions) }
        }
    }

    private func finishScan(_ regions: [TextRegion]) {
        scanning = false
        scanProgress = 1
        if regions.isEmpty {
            scanMessage = "No text found. Try drawing a box on the preview."
        } else {
            settings.regions.append(contentsOf: regions)
            scanMessage = "Found \(regions.count) text area(s). Check the red boxes on the preview."
        }
    }

    // MARK: export
    func export() {
        player.pause()
        isPlaying = false
        exportState = .working(0)
        if isPhoto { exportPhoto() } else { exportVideo() }
    }

    private func fail(_ message: String) {
        DispatchQueue.main.async { self.exportState = .failed(message) }
    }

    private func exportPhoto() {
        guard let src = photoSource, let cg = src.cgImage else { fail("No photo loaded."); return }
        let s = settings
        let size = sourceSize
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let out = Geometry.outputSize(source: size, settings: s, maxLongSide: 4096)
            let r = Renderer(settings: s, outSize: out, isPhoto: true)
            let ci = r.render(CIImage(cgImage: cg), outTime: 0)
            guard let cgOut = self.ciContext.createCGImage(ci, from: CGRect(origin: .zero, size: out)),
                  let data = UIImage(cgImage: cgOut).jpegData(compressionQuality: 0.95) else {
                self.fail("Could not render the photo."); return
            }
            DispatchQueue.main.async { self.exportState = .working(0.7) }
            self.requestPhotos { ok in
                guard ok else { self.fail("Photos access is off. Enable it in Settings."); return }
                PHPhotoLibrary.shared().performChanges({
                    let req = PHAssetCreationRequest.forAsset()
                    req.addResource(with: .photo, data: data, options: nil)
                }, completionHandler: { success, err in
                    DispatchQueue.main.async {
                        self.exportState = success ? .done : .failed(err?.localizedDescription ?? "Save failed.")
                    }
                })
            }
        }
    }

    private func exportVideo() {
        guard let asset = asset else { fail("No video loaded."); return }
        let s = settings
        let out = Geometry.outputSize(source: sourceSize, settings: s)
        guard let result = Builder.compose(asset: asset, settings: s) else { fail("Could not build the video."); return }
        let renderer = Renderer(settings: s, outSize: out, isPhoto: false)
        let vc = Builder.videoComposition(for: result.0, renderer: renderer, size: out, fps: fps, context: ciContext)
        guard let session = AVAssetExportSession(asset: result.0, presetName: AVAssetExportPresetHighestQuality) else {
            fail("Export is not available for this video."); return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).mp4")
        session.videoComposition = vc
        session.audioMix = result.1
        session.outputURL = url
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.audioTimePitchAlgorithm = .spectral
        exportSession = session

        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak session] t in
            guard let self = self, let session = session else { t.invalidate(); return }
            if session.status == .exporting || session.status == .waiting {
                self.exportState = .working(Double(session.progress) * 0.95)
            } else {
                t.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)

        session.exportAsynchronously { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async { timer.invalidate() }
            switch session.status {
            case .completed:
                self.requestPhotos { ok in
                    guard ok else { self.fail("Photos access is off. Enable it in Settings."); return }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    }, completionHandler: { success, err in
                        try? FileManager.default.removeItem(at: url)
                        DispatchQueue.main.async {
                            self.exportState = success ? .done : .failed(err?.localizedDescription ?? "Save failed.")
                        }
                    })
                }
            case .cancelled:
                self.fail("Export cancelled.")
            default:
                self.fail(session.error?.localizedDescription ?? "Export failed.")
            }
        }
    }

    func cancelExport() {
        exportSession?.cancelExport()
    }

    private func requestPhotos(_ done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            done(status == .authorized || status == .limited)
        }
    }
}

enum Builder {
    /// Trim + speed: builds the timeline from the source video.
    static func compose(asset: AVAsset, settings s: EditSettings) -> (AVMutableComposition, AVAudioMix?)? {
        guard let vTrack = asset.tracks(withMediaType: .video).first else { return nil }
        let comp = AVMutableComposition()
        guard let cv = comp.addMutableTrack(withMediaType: .video,
                                            preferredTrackID: kCMPersistentTrackID_Invalid) else { return nil }
        cv.preferredTransform = vTrack.preferredTransform
        let aTrack = asset.tracks(withMediaType: .audio).first
        let ca: AVMutableCompositionTrack? = aTrack != nil
            ? comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        let ts: CMTimeScale = 600
        var cursor = CMTime.zero
        for seg in s.segments() {
            let range = CMTimeRange(start: CMTime(seconds: seg.srcStart, preferredTimescale: ts),
                                    duration: CMTime(seconds: seg.srcEnd - seg.srcStart, preferredTimescale: ts))
            do {
                try cv.insertTimeRange(range, of: vTrack, at: cursor)
                if let at = aTrack, let ca = ca { try ca.insertTimeRange(range, of: at, at: cursor) }
            } catch {
                return nil
            }
            let inserted = CMTimeRange(start: cursor, duration: range.duration)
            let outDur = CMTime(seconds: seg.outDuration, preferredTimescale: ts)
            comp.scaleTimeRange(inserted, toDuration: outDur)
            cursor = CMTimeAdd(cursor, outDur)
        }

        var mix: AVAudioMix?
        if let ca = ca {
            let p = AVMutableAudioMixInputParameters(track: ca)
            p.setVolume(s.muted ? 0 : Float(s.volume), at: .zero)
            let m = AVMutableAudioMix()
            m.inputParameters = [p]
            mix = m
        }
        return (comp, mix)
    }

    static func videoComposition(for comp: AVAsset, renderer: Renderer, size: CGSize,
                                 fps: Double, context: CIContext) -> AVMutableVideoComposition {
        let vc = AVMutableVideoComposition(asset: comp, applyingCIFiltersWithHandler: { request in
            let out = renderer.render(request.sourceImage, outTime: request.compositionTime.seconds)
            request.finish(with: out, context: context)
        })
        vc.renderSize = size
        let rate = Int32(max(24, min(60, fps.rounded())))
        vc.frameDuration = CMTime(value: 1, timescale: rate)
        return vc
    }
}

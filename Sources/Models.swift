import SwiftUI

enum FilterPreset: String, CaseIterable, Identifiable {
    case none, vivid, warm, cool, noir, mono, chrome, fade, instant, process, tonal, transfer, sepia, dramatic, cinema
    var id: String { rawValue }
    var title: String { self == .none ? "None" : rawValue.capitalized }
}

enum EffectPreset: String, CaseIterable, Identifiable {
    case none, blur, pixelate, glow, comic, glitch, zoomBlur
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .glow: return "Glow"
        case .comic: return "Comic"
        case .glitch: return "Glitch"
        case .zoomBlur: return "Zoom blur"
        }
    }
}

enum AspectPreset: String, CaseIterable, Identifiable {
    case original, wide, tall, square, portrait, classic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return "Original"
        case .wide: return "16:9"
        case .tall: return "9:16"
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .classic: return "4:3"
        }
    }
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .wide: return 16.0 / 9.0
        case .tall: return 9.0 / 16.0
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        case .classic: return 4.0 / 3.0
        }
    }
}

enum ResolutionPreset: String, CaseIterable, Identifiable {
    case original, p720, p1080, p2160
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return "Original"
        case .p720: return "720p"
        case .p1080: return "1080p"
        case .p2160: return "4K"
        }
    }
    var shortSide: CGFloat? {
        switch self {
        case .original: return nil
        case .p720: return 720
        case .p1080: return 1080
        case .p2160: return 2160
        }
    }
}

enum FillStyle: String, CaseIterable, Identifiable {
    case patch, blur
    var id: String { rawValue }
    var title: String { self == .patch ? "Patch fill" : "Blur" }
}

enum Tool: String, CaseIterable, Identifiable {
    case trim, speed, crop, adjust, filter, effect, overlay, removeText, enhance, audio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trim: return "Trim"
        case .speed: return "Speed"
        case .crop: return "Crop"
        case .adjust: return "Adjust"
        case .filter: return "Filters"
        case .effect: return "Effects"
        case .overlay: return "Overlay"
        case .removeText: return "Remove text"
        case .enhance: return "Enhance HD"
        case .audio: return "Audio"
        }
    }
    var icon: String {
        switch self {
        case .trim: return "scissors"
        case .speed: return "speedometer"
        case .crop: return "crop"
        case .adjust: return "slider.horizontal.3"
        case .filter: return "camera.filters"
        case .effect: return "wand.and.stars"
        case .overlay: return "textformat"
        case .removeText: return "eraser"
        case .enhance: return "sparkles"
        case .audio: return "speaker.wave.2"
        }
    }
    var videoOnly: Bool { self == .trim || self == .speed || self == .audio }
}

/// Region (normalized 0...1, origin top-left, in the cropped frame) where text is removed
struct TextRegion: Identifiable {
    var id = UUID()
    var rect: CGRect
    var start: Double
    var end: Double
    var wholeVideo: Bool
    var enabled = true
}

enum OverlayKind { case text, emoji, image }

struct OverlayItem: Identifiable {
    var id = UUID()
    var kind: OverlayKind
    var text = ""
    var imageData: Data?
    var color = Color.white
    var bold = true
    var background = false
    var x = 0.5            // center, normalized, origin top-left
    var y = 0.5
    var size = 0.07        // text/emoji: font height / output height. image: width / output width
    var rotation = 0.0     // degrees
    var opacity = 1.0
    var start = 0.0        // output timeline seconds
    var end = 3600.0
}

struct Segment {
    let srcStart: Double
    let srcEnd: Double
    let speed: Double
    var outDuration: Double { (srcEnd - srcStart) / max(0.05, speed) }
}

struct EditSettings {
    var trimStart = 0.0
    var trimEnd = 0.0
    var speed = 1.0
    var sectionOn = false
    var sectionStart = 0.0
    var sectionEnd = 0.0
    var sectionSpeed = 0.5

    var rotation = 0
    var flipH = false
    var aspect = AspectPreset.original
    var zoom = 1.0
    var panX = 0.0
    var panY = 0.0

    var brightness = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var warmth = 0.0
    var sharpness = 0.0
    var vignette = 0.0

    var filter = FilterPreset.none
    var filterAmount = 1.0
    var effect = EffectPreset.none
    var effectAmount = 0.5

    var regions: [TextRegion] = []
    var fillStyle = FillStyle.patch
    var overlays: [OverlayItem] = []

    var enhance = false
    var resolution = ResolutionPreset.original

    var muted = false
    var volume = 1.0

    func segments() -> [Segment] {
        let a = trimStart, b = trimEnd
        guard b > a else { return [] }
        if sectionOn, sectionEnd > sectionStart + 0.05 {
            let s0 = max(a, min(sectionStart, b))
            let s1 = max(s0, min(sectionEnd, b))
            var out: [Segment] = []
            if s0 > a + 0.01 { out.append(Segment(srcStart: a, srcEnd: s0, speed: speed)) }
            if s1 > s0 + 0.01 { out.append(Segment(srcStart: s0, srcEnd: s1, speed: sectionSpeed)) }
            if b > s1 + 0.01 { out.append(Segment(srcStart: s1, srcEnd: b, speed: speed)) }
            if !out.isEmpty { return out }
        }
        return [Segment(srcStart: a, srcEnd: b, speed: speed)]
    }

    var outputDuration: Double { segments().reduce(0) { $0 + $1.outDuration } }
}

enum Geometry {
    static func even(_ v: CGFloat) -> CGFloat { max(2, (v / 2).rounded() * 2) }

    static func rotatedSize(_ s: CGSize, rotation: Int) -> CGSize {
        rotation % 180 == 0 ? s : CGSize(width: s.height, height: s.width)
    }

    static func cropSize(_ s: CGSize, aspect: AspectPreset, zoom: Double) -> CGSize {
        var w = s.width, h = s.height
        if let r = aspect.ratio {
            if w / h > r { w = h * r } else { h = w / r }
        }
        let z = CGFloat(max(1, zoom))
        return CGSize(width: w / z, height: h / z)
    }

    static func outputSize(source: CGSize, settings s: EditSettings, maxLongSide: CGFloat = 3840) -> CGSize {
        let rs = rotatedSize(source, rotation: s.rotation)
        let cs = cropSize(rs, aspect: s.aspect, zoom: s.zoom)
        var scale: CGFloat = 1
        let short = max(1, min(cs.width, cs.height))
        if let target = s.resolution.shortSide { scale = target / short } else if s.enhance { scale = 2 }
        let long = max(cs.width, cs.height) * scale
        if long > maxLongSide { scale *= maxLongSide / long }
        return CGSize(width: even(cs.width * scale), height: even(cs.height * scale))
    }

    static func previewSize(_ out: CGSize, maxLong: CGFloat = 1080) -> CGSize {
        let l = max(out.width, out.height)
        let k = min(1, maxLong / max(1, l))
        return CGSize(width: even(out.width * k), height: even(out.height * k))
    }
}

extension UIImage {
    /// Redraws the image upright and limits its longest side
    func normalized(maxSide: CGFloat = 4096) -> UIImage {
        let longest = max(size.width, size.height)
        let k = longest > maxSide ? maxSide / longest : 1
        if imageOrientation == .up && k == 1 { return self }
        let newSize = CGSize(width: size.width * k, height: size.height * k)
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: f).image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

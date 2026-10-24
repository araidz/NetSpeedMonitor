import AppKit

@MainActor
enum MenuBarIconGenerator {

    /// Standard menu bar item height.
    private static let iconHeight: CGFloat = 20
    /// Horizontal padding around the text. Kept small so the readout sits close
    /// to the neighbouring menu bar icon.
    private static let horizontalPadding: CGFloat = 0
    /// Per-line height. Kept just under the font size to pull the two lines
    /// closer together without letting the glyphs overlap.
    private static let lineHeight: CGFloat = 9
    /// Nudges the text downward so it lines up vertically with the other menu
    /// bar icons (positive moves it down).
    private static let verticalOffset: CGFloat = 1.5

    // Monospaced digits keep the numbers aligned and stop the width from
    // jittering as values change. Created once and reused.
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
    private static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.alignment = .right
        p.minimumLineHeight = lineHeight
        p.maximumLineHeight = lineHeight
        return p
    }()

    /// Width reserved for the readout — the widest figure the compact format can
    /// produce ("00.00M") plus its arrow. Every image is drawn at this width, so
    /// the status item never resizes: the arrows stay put and only the digits
    /// change. A rarer wider figure draws by growing the image once instead of
    /// being clipped.
    private static let reservedWidth: CGFloat = {
        let reference = NSAttributedString(string: "00.00M ↑", attributes: [.font: font])
        return ceil(reference.size().width)
    }()

    // Cache the last rendered image. The formatted text and colour band change
    // only at coarse thresholds, so idle/steady ticks reuse the same image
    // instead of re-drawing it. The normal rendering is keyed on the two formatted
    // strings, their opacity bands, and the caller-provided status-button appearance.
    private static var cachedKey: String?
    private static var cachedImage: NSImage?

    /// Renders the two-line up/down speed readout. Values are in bytes/sec; each
    /// line is shaded by its own speed band (monochrome) so the current
    /// throughput is readable at a glance.
    static func generateIcon(upload: Double, download: Double, format: RateFormat,
                             appearance: NSAppearance, tint: NSColor? = nil) -> NSImage {
        let upText = format.compact(upload)
        let downText = format.compact(download)

        let upBand = tint == nil ? opacity(for: upload) : 1
        let downBand = tint == nil ? opacity(for: download) : 1
        let key = "\(upText)|\(downText)|\(upBand)|\(downBand)|\(appearance.name.rawValue)"
        if tint == nil, key == cachedKey, let cached = cachedImage { return cached }

        var image: NSImage!
        appearance.performAsCurrentDrawingAppearance {
            let attributedText = NSMutableAttributedString()
            attributedText.append(line(text: "\(upText) ↑", color: tint ?? color(for: upload)))
            attributedText.append(NSAttributedString(string: "\n"))
            attributedText.append(line(text: "\(downText) ↓", color: tint ?? color(for: download)))

            let textSize = attributedText.size()
            let width = max(Self.reservedWidth, ceil(textSize.width)) + horizontalPadding * 2

            image = NSImage(size: NSSize(width: width, height: iconHeight), flipped: false) { rect in
                let textRect = NSRect(
                    x: 0,
                    y: (rect.height - textSize.height) / 2 - verticalOffset,
                    width: rect.width - horizontalPadding,
                    height: textSize.height
                )
                attributedText.draw(in: textRect)
                return true
            }

            // We vary the text opacity by speed, so this is not a template image.
            image.isTemplate = false
            image.accessibilityDescription = "Up \(format.full(upload)), down \(format.full(download))"
        }

        if tint == nil {
            cachedKey = key
            cachedImage = image
        }
        return image
    }

    // MARK: - Helpers

    /// Builds one shaded line with the arrow on the right, e.g. "12.34 ↑".
    private static func line(text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    /// Maps a speed (bytes/sec) to a monochrome opacity band — brighter means
    /// faster. Bands are fixed in MB/s whatever unit is displayed.
    private static func opacity(for bytesPerSec: Double) -> CGFloat {
        switch bytesPerSec / (1024 * 1024) {
        case 1...:    return 1.0
        case 0.1...:  return 0.7
        case 0.01...: return 0.55
        default:      return 0.4
        }
    }

    /// The label colour at the opacity band for the given speed.
    private static func color(for bytesPerSec: Double) -> NSColor {
        NSColor.labelColor.withAlphaComponent(opacity(for: bytesPerSec))
    }
}

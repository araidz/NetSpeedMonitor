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

    // Cache the last rendered image. The formatted text and colour band change
    // only at coarse thresholds, so idle/steady ticks reuse the same image
    // instead of re-drawing it. The normal rendering is keyed on the two formatted
    // strings, their opacity bands, and the caller-provided status-button appearance.
    private static var cachedKey: String?
    private static var cachedImage: NSImage?

    /// Renders the two-line up/down speed readout. Values are in MB/s; each line
    /// is shaded by its own speed band (monochrome) so the current throughput is
    /// readable at a glance.
    static func generateIcon(uploadMBps: Double, downloadMBps: Double,
                             appearance: NSAppearance, tint: NSColor? = nil) -> NSImage {
        let upText = format(uploadMBps)
        let downText = format(downloadMBps)

        let upBand = tint == nil ? opacity(forMBps: uploadMBps) : 1
        let downBand = tint == nil ? opacity(forMBps: downloadMBps) : 1
        let key = "\(upText)|\(downText)|\(upBand)|\(downBand)|\(appearance.name.rawValue)"
        if tint == nil, key == cachedKey, let cached = cachedImage { return cached }

        var image: NSImage!
        appearance.performAsCurrentDrawingAppearance {
            let attributedText = NSMutableAttributedString()
            attributedText.append(line(text: "\(upText) ↑", color: tint ?? color(forMBps: uploadMBps)))
            attributedText.append(NSAttributedString(string: "\n"))
            attributedText.append(line(text: "\(downText) ↓", color: tint ?? color(forMBps: downloadMBps)))

            let textSize = attributedText.size()
            let width = ceil(textSize.width) + horizontalPadding * 2

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
            image.accessibilityDescription = "Up \(upText) MB/s, down \(downText) MB/s"
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

    /// Formats a MB/s value with a sensible number of decimals for its
    /// magnitude, keeping the readout compact.
    private static func format(_ mbps: Double) -> String {
        switch mbps {
        case let value where value >= 100: return String(format: "%.0f", value)
        case let value where value >= 10:  return String(format: "%.1f", value)
        default:                           return String(format: "%.2f", mbps)
        }
    }

    /// Maps a speed (MB/s) to a monochrome opacity band — brighter means faster.
    private static func opacity(forMBps mbps: Double) -> CGFloat {
        switch mbps {
        case let value where value >= 1.0:  return 1.0
        case let value where value >= 0.1:  return 0.7
        case let value where value >= 0.01: return 0.55
        default:                            return 0.4
        }
    }

    /// The label colour at the opacity band for the given speed.
    private static func color(forMBps mbps: Double) -> NSColor {
        NSColor.labelColor.withAlphaComponent(opacity(forMBps: mbps))
    }
}

import AppKit

final class MenuBarIconGenerator {

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

    /// Renders the two-line up/down speed readout. Values are in MB/s; each line
    /// is shaded by its own speed band (monochrome) so the current throughput is
    /// readable at a glance.
    static func generateIcon(uploadMBps: Double, downloadMBps: Double) -> NSImage {
        // Monospaced digits keep the numbers aligned and stop the width from
        // jittering as values change. Larger + bolder than the original for
        // easier reading.
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight

        let attributedText = NSMutableAttributedString()
        attributedText.append(line(symbol: "↑", valueMBps: uploadMBps, font: font, paragraph: paragraph))
        attributedText.append(NSAttributedString(string: "\n"))
        attributedText.append(line(symbol: "↓", valueMBps: downloadMBps, font: font, paragraph: paragraph))

        let textSize = attributedText.size()
        let width = ceil(textSize.width) + horizontalPadding * 2

        let image = NSImage(size: NSSize(width: width, height: iconHeight), flipped: false) { rect in
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
        // `labelColor` still resolves correctly for both light and dark menu bars.
        image.isTemplate = false
        return image
    }

    // MARK: - Helpers

    /// Builds one shaded line, e.g. "↑ 12.34".
    private static func line(
        symbol: String,
        valueMBps: Double,
        font: NSFont,
        paragraph: NSParagraphStyle
    ) -> NSAttributedString {
        let text = "\(symbol) \(format(valueMBps))"
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color(forMBps: valueMBps),
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

    /// Maps a speed (MB/s) to a monochrome shade so the range is obvious at a
    /// glance — brighter/more solid means faster:
    /// - Fast     (≥ 1 MB/s):    full strength
    /// - Moderate (0.1–1 MB/s):  slightly dimmed
    /// - Slow     (0.01–0.1):    dimmer
    /// - Idle     (< 0.01 MB/s): faint
    private static func color(forMBps mbps: Double) -> NSColor {
        let opacity: CGFloat
        switch mbps {
        case let value where value >= 1.0:   opacity = 1.0
        case let value where value >= 0.1:   opacity = 0.7
        case let value where value >= 0.01:  opacity = 0.45
        default:                             opacity = 0.3
        }
        return NSColor.labelColor.withAlphaComponent(opacity)
    }
}

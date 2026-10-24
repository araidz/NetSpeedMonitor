import AppKit

/// A small throughput graph shown at the top of the menu: download as a filled
/// area, upload as a line, newest sample on the right. A snapshot taken when
/// the menu opens, like the rest of the menu.
final class HistoryGraphView: NSView {
    /// Samples inside the window, oldest first. Older ones are dropped so the
    /// graph keeps its span after the sampling interval changes.
    private let samples: [MenuBarState.Sample]
    private let span: TimeInterval
    private let caption: NSAttributedString

    private static let inset: CGFloat = 14
    private static let captionHeight: CGFloat = 16
    private static let downColor = NSColor.controlAccentColor
    private static let upColor = NSColor.systemOrange

    init(samples: [MenuBarState.Sample], span: TimeInterval, format: RateFormat) {
        self.span = span
        let now = Date()
        self.samples = samples.filter { now.timeIntervalSince($0.at) <= span }

        let upPeak = self.samples.map(\.up).max() ?? 0
        let downPeak = self.samples.map(\.down).max() ?? 0
        let spanText = Duration.seconds(span)
            .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        // Keeps the one-line caption on one line, with an ellipsis if a pair of
        // four-digit peaks ever outgrows the menu width.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        attributes[.paragraphStyle] = paragraph

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "last \(spanText) · Peak ", attributes: attributes))
        text.append(NSAttributedString(string: "↑ ", attributes: [
            .font: font, .foregroundColor: Self.upColor, .paragraphStyle: paragraph,
        ]))
        text.append(NSAttributedString(string: "\(format.full(upPeak)) · ", attributes: attributes))
        text.append(NSAttributedString(string: "↓ ", attributes: [
            .font: font, .foregroundColor: Self.downColor, .paragraphStyle: paragraph,
        ]))
        text.append(NSAttributedString(string: format.full(downPeak), attributes: attributes))
        caption = text

        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 64))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Throughput graph, \(text.string)")
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let top = bounds.maxY - Self.captionHeight
        caption.draw(in: NSRect(x: Self.inset, y: top,
                                width: bounds.width - Self.inset * 2, height: Self.captionHeight))

        let plot = NSRect(x: Self.inset, y: bounds.minY + 4,
                          width: bounds.width - Self.inset * 2, height: top - bounds.minY - 8)

        guard samples.count > 1 else { return }
        // One shared scale for both lines. Floor of 1 KB/s keeps an idle link
        // from scaling noise to full height.
        let scale = max(samples.map { max($0.down, $0.up) }.max() ?? 0, 1024)
        let now = Date()
        // Positioned by age, not index, so samples taken at the previous
        // interval still land in the right place instead of the graph blanking.
        func point(_ sample: MenuBarState.Sample, _ value: Double) -> NSPoint {
            let age = min(max(now.timeIntervalSince(sample.at), 0), span)
            return NSPoint(x: plot.maxX - CGFloat(age / span) * plot.width,
                           y: plot.minY + CGFloat(value / scale) * plot.height)
        }
        func line(_ value: (MenuBarState.Sample) -> Double) -> NSBezierPath {
            let path = NSBezierPath()
            for (index, sample) in samples.enumerated() {
                let p = point(sample, value(sample))
                index == 0 ? path.move(to: p) : path.line(to: p)
            }
            path.lineWidth = 1.5
            path.lineJoinStyle = .round
            return path
        }

        let down = line(\.down)
        let area = down.copy() as! NSBezierPath
        area.line(to: NSPoint(x: point(samples[samples.count - 1], 0).x, y: plot.minY))
        area.line(to: NSPoint(x: point(samples[0], 0).x, y: plot.minY))
        area.close()
        Self.downColor.withAlphaComponent(0.25).setFill()
        area.fill()
        Self.downColor.setStroke()
        down.stroke()

        Self.upColor.setStroke()
        line(\.up).stroke()
    }
}

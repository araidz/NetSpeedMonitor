import AppKit

/// A small throughput graph shown at the top of the menu: download as a filled
/// area, upload as a line, newest sample on the right. A snapshot taken when
/// the menu opens, like the rest of the menu.
final class HistoryGraphView: NSView {
    private let samples: [MenuBarState.Sample]
    private let capacity: Int
    private let caption: NSAttributedString

    private static let inset: CGFloat = 14
    private static let captionHeight: CGFloat = 16
    private static let downColor = NSColor.controlAccentColor
    private static let upColor = NSColor.systemOrange

    init(samples: [MenuBarState.Sample], capacity: Int, span: String, format: RateFormat) {
        self.samples = samples
        self.capacity = max(capacity, 2)
        let peak = samples.map { max($0.down, $0.up) }.max() ?? 0

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "↓ ", attributes: [.font: font, .foregroundColor: Self.downColor]))
        text.append(NSAttributedString(string: "↑ ", attributes: [.font: font, .foregroundColor: Self.upColor]))
        text.append(NSAttributedString(string: "last \(span) · peak \(format.full(peak))",
                                       attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        caption = text

        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 64))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Throughput graph, \(text.string)")
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let top = bounds.maxY - Self.captionHeight
        caption.draw(at: NSPoint(x: Self.inset, y: top + 2))

        let plot = NSRect(x: Self.inset, y: bounds.minY + 4,
                          width: bounds.width - Self.inset * 2, height: top - bounds.minY - 8)

        guard samples.count > 1 else { return }
        // Floor of 1 KB/s keeps an idle link from scaling noise to full height.
        let peak = max(samples.map { max($0.down, $0.up) }.max() ?? 0, 1024)
        let step = plot.width / CGFloat(capacity - 1)
        func point(_ index: Int, _ value: Double) -> NSPoint {
            NSPoint(x: plot.maxX - CGFloat(samples.count - 1 - index) * step,
                    y: plot.minY + CGFloat(value / peak) * plot.height)
        }
        func line(_ value: (MenuBarState.Sample) -> Double) -> NSBezierPath {
            let path = NSBezierPath()
            for (index, sample) in samples.enumerated() {
                let p = point(index, value(sample))
                index == 0 ? path.move(to: p) : path.line(to: p)
            }
            path.lineWidth = 1.5
            path.lineJoinStyle = .round
            return path
        }

        let down = line(\.down)
        let area = down.copy() as! NSBezierPath
        area.line(to: NSPoint(x: plot.maxX, y: plot.minY))
        area.line(to: NSPoint(x: point(0, 0).x, y: plot.minY))
        area.close()
        Self.downColor.withAlphaComponent(0.25).setFill()
        area.fill()
        Self.downColor.setStroke()
        down.stroke()

        Self.upColor.setStroke()
        line(\.up).stroke()
    }
}

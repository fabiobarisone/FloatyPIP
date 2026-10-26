import Cocoa

final class PiPPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Strato che compare tenendo ⌘ sopra la finestra:
/// trascina = sposta, trascina da un angolo = ridimensiona, click semplice = passa al video.
final class ControlOverlay: NSView {
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onClick: ((NSEvent) -> Void)?
    private let hint = NSTextField(labelWithString: " ⌘  trascina = sposta  ·  angoli = ridimensiona  ·  scroll = zoom ")
    private let grip: CGFloat = 26

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        layer?.cornerRadius = 10
        hint.font = .systemFont(ofSize: 10.5, weight: .medium)
        hint.textColor = .white
        hint.alignment = .center
        hint.drawsBackground = true
        hint.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        hint.isHidden = bounds.width < 330
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let b = bounds.insetBy(dx: 5, dy: 5)
        let l: CGFloat = 14
        let p = NSBezierPath()
        p.lineWidth = 3
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (b.minX, b.minY, 1, 1), (b.maxX, b.minY, -1, 1),
            (b.minX, b.maxY, 1, -1), (b.maxX, b.maxY, -1, -1)
        ]
        for (x, y, sx, sy) in corners {
            p.move(to: NSPoint(x: x + sx * l, y: y))
            p.line(to: NSPoint(x: x, y: y))
            p.line(to: NSPoint(x: x, y: y + sy * l))
        }
        p.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let w = window else { return }
        let p = convert(event.locationInWindow, from: nil)
        let left = p.x < grip, right = p.x > bounds.width - grip
        let bottom = p.y < grip, top = p.y > bounds.height - grip
        let corner = (left || right) && (top || bottom)

        let startMouse = NSEvent.mouseLocation
        let start = w.frame
        var moved = false
        onBegin?()
        while let ev = w.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { break }
            let m = NSEvent.mouseLocation
            let dx = m.x - startMouse.x, dy = m.y - startMouse.y
            if !moved && hypot(dx, dy) < 4 { continue }
            moved = true
            if corner {
                var nw = right ? start.width + dx : start.width - dx
                nw = max(AppDelegate.minWidth, min(2400, nw))
                let nh = (nw * 9 / 16).rounded()
                let x = left ? start.maxX - nw : start.minX
                let y = bottom ? start.maxY - nh : start.minY
                w.setFrame(NSRect(x: x, y: y, width: nw, height: nh), display: true)
            } else {
                w.setFrameOrigin(NSPoint(x: start.minX + dx, y: start.minY + dy))
            }
        }
        onEnd?()
        if !moved { onClick?(event) }
    }
}

/// Voce di menu con etichetta + slider (percentuale).
final class SliderMenuView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let slider: NSSlider
    private let title: String
    private let onChange: (Double) -> Void
    private let format: (Double) -> String

    init(title: String, value: Double, min: Double, max: Double,
         format: @escaping (Double) -> String = { "\(Int(($0 * 100).rounded()))%" },
         onChange: @escaping (Double) -> Void) {
        self.title = title
        self.onChange = onChange
        self.format = format
        slider = NSSlider(value: value, minValue: min, maxValue: max, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 50))
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        label.font = .menuFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: 27, width: 230, height: 18)
        slider.frame = NSRect(x: 18, y: 4, width: 224, height: 22)
        addSubview(label)
        addSubview(slider)
        refreshLabel()
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ v: Double) { slider.doubleValue = v; refreshLabel() }
    @objc private func changed() { refreshLabel(); onChange(slider.doubleValue) }
    private func refreshLabel() { label.stringValue = "\(title): \(format(slider.doubleValue))" }
}

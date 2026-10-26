import Cocoa
import ApplicationServices

/// Gestisce le finestre PiP *native* di Chrome/Brave/Edge/Arc (Netflix, Prime, Disney+…):
/// quando il mouse si avvicina le sposta dall'altra parte dello schermo. ⌘ tenuto = non si muovono.
/// Serve il permesso Accessibilità.
final class NativePiP {
    private var lastMove = Date.distantPast
    private var asked = false
    var onNeedPermission: (() -> Void)?

    private var primaryH: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func cgRect(_ f: NSRect) -> CGRect {
        CGRect(x: f.minX, y: primaryH - f.maxY, width: f.width, height: f.height)
    }

    private func distance(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY))
    }

    /// Finestre PiP dei browser Chromium visibili ora (coordinate CG, origine in alto a sinistra).
    func windows() -> [(pid: pid_t, rect: CGRect)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var out: [(pid_t, CGRect)] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 3,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                  BrowserBridge.chromium.contains(bid),
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd),
                  r.width >= 120, r.width <= 1800 else { continue }
            out.append((pid, r))
        }
        return out
    }

    func tick(mode: Mode) {
        guard mode != .off else { return }
        if NSEvent.modifierFlags.contains(.command) { return }
        guard Date().timeIntervalSince(lastMove) > 0.35 else { return }
        let m = NSEvent.mouseLocation
        let mouse = CGPoint(x: m.x, y: primaryH - m.y)
        for (pid, r) in windows() where distance(mouse, r) < 40 {
            guard AXIsProcessTrusted() else {
                if !asked { asked = true; onNeedPermission?() }
                return
            }
            lastMove = Date()
            move(pid: pid, from: r)
            return
        }
    }

    private func move(pid: pid_t, from r: CGRect) {
        let c = CGPoint(x: r.midX, y: r.midY)
        let screens = NSScreen.screens.map { cgRect($0.visibleFrame) }
        let v = screens.first { $0.contains(c) } ?? screens.first ?? r
        var n = r.origin
        let mx = v.minX + v.maxX - r.maxX
        if abs(mx - r.minX) > 20 { n.x = mx } else { n.y = v.minY + v.maxY - r.maxY }
        n.x = min(max(n.x, v.minX), v.maxX - r.width)
        n.y = min(max(n.y, v.minY), v.maxY - r.height)

        let app = AXUIElementCreateApplication(pid)
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &val) == .success,
              let wins = val as? [AXUIElement] else { return }
        for w in wins {
            var pv: CFTypeRef?, sv: CFTypeRef?
            guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pv) == .success,
                  AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sv) == .success,
                  let pAX = pv, let sAX = sv else { continue }
            var p = CGPoint.zero, s = CGSize.zero
            AXValueGetValue(pAX as! AXValue, .cgPoint, &p)
            AXValueGetValue(sAX as! AXValue, .cgSize, &s)
            if abs(p.x - r.minX) < 4, abs(p.y - r.minY) < 4, abs(s.width - r.width) < 4 {
                var np = n
                if let nv = AXValueCreate(.cgPoint, &np) {
                    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, nv)
                }
                return
            }
        }
    }

    static func requestPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

import Foundation

/// Cosa succede quando il mouse si avvicina alla finestra.
enum Mode: Int { case fade = 0, dodge = 1, off = 2 }
enum Corner: Int { case topLeft = 0, topRight, bottomLeft, bottomRight }

/// Impostazioni persistenti (UserDefaults).
enum S {
    static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            "mode": Mode.fade.rawValue,
            "corner": Corner.bottomRight.rawValue,
            "width": 480.0,
            "baseOpacity": 1.0,
            "nearOpacity": 0.15,
            "focusVideo": true,
            "clickThrough": true,
            "autoCapture": true,
            "handBack": true,
            "holdSeconds": 4.0,
            "edgeSoftness": 0.5,
            "hasOrigin": false,
            "originX": 0.0,
            "originY": 0.0
        ])
    }

    static var mode: Mode {
        get { Mode(rawValue: d.integer(forKey: "mode")) ?? .fade }
        set { d.set(newValue.rawValue, forKey: "mode") }
    }
    static var corner: Corner {
        get { Corner(rawValue: d.integer(forKey: "corner")) ?? .bottomRight }
        set { d.set(newValue.rawValue, forKey: "corner") }
    }
    static var width: Double {
        get { d.double(forKey: "width") }
        set { d.set(newValue, forKey: "width") }
    }
    static var baseOpacity: Double {
        get { d.double(forKey: "baseOpacity") }
        set { d.set(newValue, forKey: "baseOpacity") }
    }
    static var nearOpacity: Double {
        get { d.double(forKey: "nearOpacity") }
        set { d.set(newValue, forKey: "nearOpacity") }
    }
    static var focusVideo: Bool {
        get { d.bool(forKey: "focusVideo") }
        set { d.set(newValue, forKey: "focusVideo") }
    }
    static var clickThrough: Bool {
        get { d.bool(forKey: "clickThrough") }
        set { d.set(newValue, forKey: "clickThrough") }
    }
    /// Cattura automatica del video dal browser quando cambi scheda/app
    static var autoCapture: Bool {
        get { d.bool(forKey: "autoCapture") }
        set { d.set(newValue, forKey: "autoCapture") }
    }
    /// Quando torni alla scheda d'origine, il video riprende lì e la PiP si chiude
    static var handBack: Bool {
        get { d.bool(forKey: "handBack") }
        set { d.set(newValue, forKey: "handBack") }
    }
    /// Secondi al 100% quando parte un video, poi sfuma all'opacità scelta
    static var holdSeconds: Double {
        get { d.double(forKey: "holdSeconds") }
        set { d.set(newValue, forKey: "holdSeconds") }
    }
    /// Sfumatura ai bordi (0 = nessuna, 1 = massima)
    static var edgeSoftness: Double {
        get { d.double(forKey: "edgeSoftness") }
        set { d.set(newValue, forKey: "edgeSoftness") }
    }
    /// Posizione libera (dopo trascinamento con ⌘)
    static var origin: CGPoint? {
        get { d.bool(forKey: "hasOrigin") ? CGPoint(x: d.double(forKey: "originX"), y: d.double(forKey: "originY")) : nil }
        set {
            if let p = newValue {
                d.set(true, forKey: "hasOrigin"); d.set(Double(p.x), forKey: "originX"); d.set(Double(p.y), forKey: "originY")
            } else {
                d.set(false, forKey: "hasOrigin")
            }
        }
    }
}

import Cocoa
import WebKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate,
                         WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let minWidth: CGFloat = 120

    var panel: PiPPanel!
    var container: NSView!
    var fadeView: NSView!
    let vignette = CAGradientLayer()
    var vignetteOff = false
    var holdUntil = Date.distantPast
    var holdSlider: SliderMenuView!
    var edgeSlider: SliderMenuView!
    var web: WKWebView!
    var overlay: ControlOverlay!
    var statusItem: NSStatusItem!

    var modeItems: [NSMenuItem] = []
    var cornerItems: [NSMenuItem] = []
    var focusItem: NSMenuItem!
    var clickItem: NSMenuItem!
    var autoItem: NSMenuItem!
    var handBackItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var baseSlider: SliderMenuView!
    var nearSlider: SliderMenuView!

    var timer: Timer?
    var pollTimer: Timer?
    var activity: NSObjectProtocol?
    var lastDodge = Date.distantPast
    var passUntil = Date.distantPast
    var dragging = false

    // Sorgente corrente nella PiP
    var currentURL: URL?
    var currentStart: Double = 0

    // Cattura dal browser
    let bridge = BrowserBridge()
    var lastPlaying: (tab: TabRef, time: Double, at: Date)?
    var captured: TabRef?
    var capturedNative = false
    let native = NativePiP()
    var nativeTimer: Timer?
    var polling = false
    var warned = Set<String>()

    let margin: CGFloat = 16
    let dodgeRange: CGFloat = 40
    let fadeRange: CGFloat = 120

    // MARK: - Avvio

    func applicationDidFinishLaunching(_ n: Notification) {
        S.registerDefaults()
        NSApp.setActivationPolicy(.accessory)
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                         reason: "Riproduzione video PiP")
        setupPanel()
        setupMenu()
        setupHotKeys()
        setupScrollResize()
        setupBrowserWatch()
        applySize(animated: false)
        panel.alphaValue = CGFloat(S.baseOpacity)
        showPlaceholder()

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        flashTitle("pronto")
    }

    // MARK: - Finestra

    func setupPanel() {
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.allowsAirPlayForMediaPlayback = true
        if #available(macOS 14.0, *) {
            cfg.preferences.inactiveSchedulingPolicy = .none   // niente rallentamenti quando la finestra non è attiva
        }
        cfg.userContentController.add(self, name: "pip")
        installUserScripts(cfg.userContentController, start: 0)

        let rect = NSRect(x: 0, y: 0, width: 480, height: 270)
        container = NSView(frame: rect)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor   // il nero sta sotto la maschera, così i bordi sfumano nel trasparente
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true

        web = WKWebView(frame: container.bounds, configuration: cfg)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        web.uiDelegate = self
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

        overlay = ControlOverlay(frame: container.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.isHidden = true
        overlay.onBegin = { [weak self] in self?.dragging = true }
        overlay.onEnd = { [weak self] in
            guard let self else { return }
            self.dragging = false
            self.savePosition()
        }
        overlay.onClick = { [weak self] e in self?.forwardClick(e) }

        // Il video sta in fadeView, che ha la maschera radiale (centro pieno, bordi sfumati)
        fadeView = NSView(frame: container.bounds)
        fadeView.autoresizingMask = [.width, .height]
        fadeView.wantsLayer = true
        fadeView.layer?.backgroundColor = NSColor.black.cgColor
        vignette.type = .radial
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1, y: 1)
        fadeView.addSubview(web)
        updateVignette()

        container.addSubview(fadeView)
        container.addSubview(overlay)

        panel = PiPPanel(contentRect: rect,
                         styleMask: [.borderless, .resizable, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = container
        panel.contentAspectRatio = NSSize(width: 16, height: 9)
        panel.minSize = NSSize(width: Self.minWidth, height: (Self.minWidth * 9 / 16).rounded())
        panel.delegate = self
    }

    func installUserScripts(_ ucc: WKUserContentController, start: Double) {
        ucc.removeAllUserScripts()
        ucc.addUserScript(WKUserScript(source: FocusScript.prelude(focus: S.focusVideo, start: start),
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: FocusScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    func showPlaceholder() {
        web.loadHTMLString("""
            <body style="margin:0;background:#000;color:#999;font:13px -apple-system;display:flex;flex-direction:column;
            align-items:center;justify-content:center;height:100vh;gap:6px;text-align:center">
            <div style="font-size:15px;color:#ddd">Guarda un video nel browser e cambia scheda/app</div>
            <div>oppure copia un link e premi ⌃⌥V</div></body>
            """, baseURL: nil)
    }

    func show() {
        if !panel.isVisible {
            startHold()
            panel.orderFrontRegardless()
        }
    }

    /// 100% per qualche secondo, poi sfuma all'opacità scelta
    func startHold() {
        holdUntil = Date().addingTimeInterval(S.holdSeconds)
        panel.alphaValue = 1
        updateVignette()
    }

    /// Maschera radiale: pieno al centro, sfumato ai lati (spenta durante i secondi al 100% e con ⌘)
    func updateVignette() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let s = CGFloat(S.edgeSoftness)
        let soft = !(s < 0.01 || vignetteOff)
        if panel != nil, panel.hasShadow == soft { panel.hasShadow = !soft; panel.invalidateShadow() }
        if !soft {
            fadeView.layer?.mask = nil
        } else {
            vignette.frame = fadeView.bounds
            let edge = NSColor.black.withAlphaComponent(max(0, 1 - s)).cgColor
            vignette.colors = [NSColor.black.cgColor, NSColor.black.cgColor, edge]
            vignette.locations = [0, NSNumber(value: Double(0.8 - 0.5 * s)), 1]
            if fadeView.layer?.mask !== vignette { fadeView.layer?.mask = vignette }
        }
        CATransaction.commit()
    }

    func windowDidResize(_ notification: Notification) { updateVignette() }

    func hidePiP() {
        web.evaluateJavaScript("window.__pipPause && window.__pipPause()")
        panel.orderOut(nil)
    }

    // MARK: - Posizione

    func screenFor(_ r: NSRect) -> NSScreen {
        let c = NSPoint(x: r.midX, y: r.midY)
        return NSScreen.screens.first { $0.frame.contains(c) } ?? panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func clamp(_ r: NSRect) -> NSRect {
        let v = screenFor(r).visibleFrame
        var f = r
        f.origin.x = min(max(f.minX, v.minX), v.maxX - f.width)
        f.origin.y = min(max(f.minY, v.minY), v.maxY - f.height)
        return f
    }

    func cornerFrame(_ c: Corner, size s: NSSize) -> NSRect {
        let v = (panel.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let left = (c == .topLeft || c == .bottomLeft)
        let top = (c == .topLeft || c == .topRight)
        let x = left ? v.minX + margin : v.maxX - s.width - margin
        let y = top ? v.maxY - s.height - margin : v.minY + margin
        return NSRect(x: x, y: y, width: s.width, height: s.height)
    }

    func targetFrame(size s: NSSize) -> NSRect {
        if let o = S.origin { return clamp(NSRect(origin: o, size: s)) }
        return cornerFrame(S.corner, size: s)
    }

    func setFrame(_ f: NSRect, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                self.panel.animator().setFrame(f, display: true)
            }
        } else {
            panel.setFrame(f, display: true)
        }
    }

    func applySize(animated: Bool) {
        let w = CGFloat(S.width)
        setFrame(targetFrame(size: NSSize(width: w, height: (w * 9 / 16).rounded())), animated: animated)
    }

    func savePosition() {
        let f = clamp(panel.frame)
        if f != panel.frame { setFrame(f, animated: true) }
        S.origin = f.origin
        S.width = Double(f.width)
    }

    func windowDidEndLiveResize(_ notification: Notification) { savePosition() }

    // MARK: - Comportamento vicino al mouse (60 fps)

    func distance(_ p: NSPoint, _ r: NSRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    func tick() {
        guard panel.isVisible, !dragging else { return }

        let d = distance(NSEvent.mouseLocation, panel.frame)
        let cmd = NSEvent.modifierFlags.contains(.command) && d < 6
        let showOverlay = cmd && Date() > passUntil
        if overlay.isHidden == showOverlay { overlay.isHidden = !showOverlay }

        let holding = Date() < holdUntil
        let base: CGFloat = holding ? 1 : CGFloat(S.baseOpacity)
        var target = base
        var ignore = false
        var near: CGFloat = 0

        // Bordi pieni con ⌘ (uso normale); sfumati altrimenti
        let wantOff = cmd
        if wantOff != vignetteOff { vignetteOff = wantOff; updateVignette() }

        if cmd {
            target = 1
        } else {
            switch S.mode {
            case .off:
                break
            case .fade:
                var t = max(0, min(1, 1 - d / fadeRange))
                t = t * t * (3 - 2 * t)
                near = t
                target = base + (CGFloat(S.nearOpacity) - base) * t
                ignore = S.clickThrough
            case .dodge:
                if d < dodgeRange, Date().timeIntervalSince(lastDodge) > 0.35 {
                    lastDodge = Date()
                    dodge()
                }
            }
        }

        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }

        let a = panel.alphaValue
        let speed: CGFloat = (cmd || near > 0.01) ? 0.25 : 0.04   // mouse = rapido, fine "100%" = dissolvenza lenta
        if abs(a - target) > 0.003 {
            panel.alphaValue = a + (target - a) * speed
        } else if a != target {
            panel.alphaValue = target
        }
    }

    /// Salta sul lato opposto dello schermo (orizzontale; se è al centro, verticale).
    func dodge() {
        let f = panel.frame
        let v = screenFor(f).visibleFrame
        var n = f
        let mx = v.minX + v.maxX - f.maxX
        if abs(mx - f.minX) > 20 {
            n.origin.x = mx
        } else {
            n.origin.y = v.minY + v.maxY - f.maxY
        }
        n = clamp(n)
        S.origin = n.origin
        setFrame(n, animated: true)
    }

    /// Click semplice con ⌘: lo passa al video (senza ⌘, per non aprire link).
    func forwardClick(_ e: NSEvent) {
        overlay.isHidden = true
        passUntil = Date().addingTimeInterval(0.6)
        panel.makeKey()
        for (type, pressure) in [(NSEvent.EventType.leftMouseDown, Float(1)), (.leftMouseUp, Float(0))] {
            if let ev = NSEvent.mouseEvent(with: type, location: e.locationInWindow, modifierFlags: [],
                                           timestamp: e.timestamp, windowNumber: e.windowNumber, context: nil,
                                           eventNumber: e.eventNumber, clickCount: e.clickCount, pressure: pressure) {
                NSApp.postEvent(ev, atStart: false)
            }
        }
    }

    // MARK: - ⌘ + scroll = dimensione

    func setupScrollResize() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, e.window === self.panel, e.modifierFlags.contains(.command) else { return e }
            let delta = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY : e.scrollingDeltaY * 10
            let f = self.panel.frame
            let w = max(Self.minWidth, min(2400, f.width + delta * 2))
            let h = (w * 9 / 16).rounded()
            let n = self.clamp(NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h))
            self.panel.setFrame(n, display: true)
            S.origin = n.origin
            S.width = Double(w)
            return nil
        }
    }

    // MARK: - Scorciatoie globali

    func setupHotKeys() {
        HotKeys.register(1, keyCode: kVK_ANSI_P) { [weak self] in self?.toggleVisible() }
        HotKeys.register(2, keyCode: kVK_ANSI_V) { [weak self] in self?.openClipboard() }
        HotKeys.register(3, keyCode: kVK_ANSI_M) { [weak self] in self?.cycleMode() }
        HotKeys.register(4, keyCode: kVK_Space) { [weak self] in self?.playPause() }
        HotKeys.register(5, keyCode: kVK_UpArrow) { [weak self] in self?.nudgeOpacity(+0.1) }
        HotKeys.register(6, keyCode: kVK_DownArrow) { [weak self] in self?.nudgeOpacity(-0.1) }
        HotKeys.register(7, keyCode: kVK_ANSI_C) { [weak self] in self?.captureNow() }
    }

    // MARK: - Cattura automatica dal browser

    func setupBrowserWatch() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontChanged(app?.bundleIdentifier)
        }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.pollBrowser() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t

        native.onNeedPermission = { [weak self] in
            self?.warnOnce("ax", "Permesso Accessibilità",
                           "Per spostare la PiP di Chrome (Netflix, Prime Video…) quando ti avvicini col mouse, attiva FloatyPIP in Impostazioni di Sistema → Privacy e sicurezza → Accessibilità.")
            NativePiP.requestPermission()
        }
        let nt = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.native.tick(mode: S.mode) }
        RunLoop.main.add(nt, forMode: .common)
        nativeTimer = nt
    }

    func frontChanged(_ bundle: String?) {
        if bundle == Bundle.main.bundleIdentifier { return }
        if S.autoCapture, let lp = lastPlaying, lp.tab.bundle != bundle, Date().timeIntervalSince(lp.at) < 3 {
            lastPlaying = nil
            capture(lp.tab, fallbackTime: lp.time + Date().timeIntervalSince(lp.at))
        }
        if BrowserBridge.supports(bundle) { pollBrowser() }
    }

    func pollBrowser() {
        guard S.autoCapture || captured != nil, !polling,
              let b = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              BrowserBridge.supports(b) else { return }
        polling = true
        bridge.probe(b) { [weak self] r in
            self?.polling = false
            self?.handleProbe(r, bundle: b)
        }
    }

    func handleProbe(_ r: ProbeResult, bundle: String) {
        switch r {
        case .nothing:
            return
        case .automationDenied:
            warnOnce("auto-\(bundle)", "Serve il permesso per leggere \(BrowserBridge.name(bundle))",
                     "Impostazioni di Sistema → Privacy e sicurezza → Automazione → FloatyPIP → attiva \(BrowserBridge.name(bundle)).")
        case .tab(let tab, let state):
            if case .jsDenied = state {
                warnOnce("js-\(bundle)", "Attiva un'opzione in \(BrowserBridge.name(bundle))", jsHelp(bundle))
                return
            }
            // Tornato alla scheda d'origine → il video riprende lì
            if let c = captured, c.bundle == tab.bundle, c.key == tab.key {
                if S.handBack, capturedNative || panel.isVisible { handBack() }
                return
            }
            // Cambio scheda dentro il browser mentre un video andava
            if S.autoCapture, let lp = lastPlaying, lp.tab.bundle == tab.bundle, lp.tab.key != tab.key,
               Date().timeIntervalSince(lp.at) < 3 {
                lastPlaying = nil
                capture(lp.tab, fallbackTime: lp.time + Date().timeIntervalSince(lp.at))
            }
            switch state {
            case .playing(let t): lastPlaying = (tab, t, Date())
            case .ad: lastPlaying = (tab, 0, Date())
            default: lastPlaying = nil
            }
        }
    }

    func jsHelp(_ bundle: String) -> String {
        if BrowserBridge.safari.contains(bundle) {
            return "Per catturare i video da Safari: Safari → Impostazioni → Avanzate → \"Mostra funzionalità per sviluppatori web\", poi menu Sviluppo → \"Consenti JavaScript da Apple Events\"."
        }
        return "Per catturare i video: nel menu di \(BrowserBridge.name(bundle)) vai su Visualizza → Opzioni per sviluppatori → \"Consenti JavaScript da eventi Apple\"."
    }

    func capture(_ tab: TabRef, fallbackTime: Double) {
        guard let url = URL(string: tab.url), url.scheme?.hasPrefix("http") == true else { return }
        if Player.isDRM(url) {
            // Netflix & co.: PiP nativa del browser, che poi spostiamo noi
            guard BrowserBridge.chromium.contains(tab.bundle) else {
                warnOnce("drm-safari", "Usa la PiP di Safari",
                         "Netflix e simili sono protetti (DRM): in Safari usa il pulsante PiP del video. Con Chrome la attivo io in automatico.")
                return
            }
            if panel.isVisible { hidePiP() }
            captured = tab
            capturedNative = true
            bridge.exec(tab, js: BrowserBridge.nativePipJS) { _ in }
            if !AXIsProcessTrusted() { native.onNeedPermission?() }
            return
        }
        bridge.pauseAndGetTime(tab) { [weak self] t in
            guard let self else { return }
            self.captured = tab
            self.capturedNative = false
            self.load(url, start: t ?? max(0, fallbackTime))
            self.show()
        }
    }

    /// ⌃⌥C: prende il video della scheda attiva del browser (anche se è in pausa).
    @objc func captureNow() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let b = BrowserBridge.supports(front) ? front :
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).first { BrowserBridge.supports($0) }
        guard let b else { flashTitle("nessun browser"); return }
        bridge.probe(b) { [weak self] r in
            guard let self else { return }
            switch r {
            case .tab(let tab, let state):
                if case .jsDenied = state {
                    if let u = URL(string: tab.url), !Player.isDRM(u) { self.captured = nil; self.load(u, start: Player.startFromURL(u)); self.show() }
                    self.warnOnce("js-\(b)", "Attiva un'opzione in \(BrowserBridge.name(b))", self.jsHelp(b))
                    return
                }
                var t: Double = 0
                if case .playing(let x) = state { t = x }
                self.capture(tab, fallbackTime: t)
            case .automationDenied:
                self.warnOnce("auto-\(b)", "Serve il permesso per leggere \(BrowserBridge.name(b))",
                              "Impostazioni di Sistema → Privacy e sicurezza → Automazione → FloatyPIP → attiva \(BrowserBridge.name(b)).")
            case .nothing:
                self.flashTitle("nessuna scheda")
            }
        }
    }

    func handBack() {
        guard let c = captured else { return }
        captured = nil
        if capturedNative {
            capturedNative = false
            bridge.exec(c, js: BrowserBridge.exitPipJS) { _ in }
            return
        }
        web.evaluateJavaScript("window.__pipTime ? window.__pipTime() : 0") { [weak self] v, _ in
            guard let self else { return }
            let t = (v as? NSNumber)?.doubleValue ?? 0
            self.hidePiP()
            self.showPlaceholder()
            self.currentURL = nil
            self.bridge.resume(c, at: t)
        }
    }

    func warnOnce(_ key: String, _ title: String, _ text: String) {
        guard !warned.contains(key) else { return }
        warned.insert(key)
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    // MARK: - Caricamento video

    func load(_ url: URL, start: Double) {
        currentURL = url
        currentStart = start
        startHold()
        if let html = Player.html(for: url, start: start) {
            web.loadHTMLString(html, baseURL: Player.base)
        } else {
            loadFull(url, start: start)
        }
    }

    func loadFull(_ url: URL, start: Double) {
        installUserScripts(web.configuration.userContentController, start: start)
        web.load(URLRequest(url: url))
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "embedError",
              let u = currentURL else { return }
        loadFull(u, start: currentStart)   // embed non consentito → pagina completa
    }

    // Link che vogliono aprire una nuova finestra: aprili nella PiP
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { webView.load(URLRequest(url: u)) }
        return nil
    }

    // MARK: - Menu barra

    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let img = NSImage(systemSymbolName: "pip", accessibilityDescription: "PiP")
        img?.isTemplate = true
        statusItem.button?.image = img

        let m = NSMenu()
        m.delegate = self

        m.addItem(item("Cattura video dal browser", #selector(captureNow), "c", ctrlOpt: true))
        m.addItem(item("Apri link dagli appunti", #selector(openClipboard), "v", ctrlOpt: true))
        m.addItem(item("Apri URL…", #selector(openURLDialog), ""))
        m.addItem(item("Apri pagina completa (se il player non va)", #selector(openFullPage), ""))
        m.addItem(.separator())

        autoItem = item("Cattura automatica quando cambi scheda/app", #selector(toggleAuto), "")
        handBackItem = item("Torna al browser quando riapri la scheda", #selector(toggleHandBack), "")
        m.addItem(autoItem)
        m.addItem(handBackItem)
        m.addItem(.separator())

        let header = NSMenuItem(title: "Quando il mouse si avvicina", action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)
        for (mode, title) in [(Mode.fade, "Diventa trasparente"), (.dodge, "Si sposta dall'altra parte"), (.off, "Niente")] {
            let it = item(title, #selector(setMode(_:)), "")
            it.tag = mode.rawValue
            it.indentationLevel = 1
            modeItems.append(it)
            m.addItem(it)
        }
        clickItem = item("I click passano attraverso", #selector(toggleClickThrough), "")
        clickItem.indentationLevel = 1
        m.addItem(clickItem)
        m.addItem(.separator())

        baseSlider = SliderMenuView(title: "Opacità", value: S.baseOpacity, min: 0.1, max: 1.0) { [weak self] v in
            S.baseOpacity = v
            self?.panel.alphaValue = CGFloat(v)
        }
        let bi = NSMenuItem(); bi.view = baseSlider; m.addItem(bi)
        nearSlider = SliderMenuView(title: "Opacità col mouse vicino", value: S.nearOpacity, min: 0.0, max: 1.0) { v in
            S.nearOpacity = v
        }
        let ni = NSMenuItem(); ni.view = nearSlider; m.addItem(ni)
        edgeSlider = SliderMenuView(title: "Bordi sfumati", value: S.edgeSoftness, min: 0, max: 1) { [weak self] v in
            S.edgeSoftness = v
            self?.updateVignette()
        }
        let ei = NSMenuItem(); ei.view = edgeSlider; m.addItem(ei)
        holdSlider = SliderMenuView(title: "Al 100% quando parte", value: S.holdSeconds, min: 0, max: 10,
                                    format: { "\(Int($0.rounded())) s" }) { v in
            S.holdSeconds = v.rounded()
        }
        let hi = NSMenuItem(); hi.view = holdSlider; m.addItem(hi)
        m.addItem(.separator())

        let corners = NSMenu()
        for (i, n) in ["Alto sinistra", "Alto destra", "Basso sinistra", "Basso destra"].enumerated() {
            let it = item(n, #selector(setCorner(_:)), "")
            it.tag = i
            cornerItems.append(it)
            corners.addItem(it)
        }
        let ci = NSMenuItem(title: "Angolo", action: nil, keyEquivalent: "")
        ci.submenu = corners
        m.addItem(ci)

        let sizes = NSMenu()
        for (n, w) in [("Mini", 160), ("Piccola", 320), ("Media", 480), ("Grande", 640), ("Extra", 854)] {
            let it = item(n, #selector(setSize(_:)), "")
            it.tag = w
            sizes.addItem(it)
        }
        let si = NSMenuItem(title: "Dimensione", action: nil, keyEquivalent: "")
        si.submenu = sizes
        m.addItem(si)

        focusItem = item("Solo video (pagine complete)", #selector(toggleFocus), "")
        m.addItem(focusItem)
        m.addItem(item("Play / Pausa", #selector(playPause), " ", ctrlOpt: true))
        m.addItem(item("Mostra / Nascondi", #selector(toggleVisible), "p", ctrlOpt: true))
        m.addItem(.separator())

        loginItem = item("Avvia al login", #selector(toggleLogin), "")
        m.addItem(loginItem)
        m.addItem(item("Aiuto e scorciatoie…", #selector(showHelp), ""))
        let quit = NSMenuItem(title: "Esci", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        m.addItem(quit)

        statusItem.menu = m
        refreshMenuState()
    }

    func item(_ t: String, _ s: Selector, _ k: String, ctrlOpt: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: t, action: s, keyEquivalent: k)
        i.target = self
        if ctrlOpt { i.keyEquivalentModifierMask = [.control, .option] }
        return i
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenuState() }

    func refreshMenuState() {
        for it in modeItems { it.state = it.tag == S.mode.rawValue ? .on : .off }
        for it in cornerItems { it.state = (S.origin == nil && it.tag == S.corner.rawValue) ? .on : .off }
        clickItem.state = S.clickThrough ? .on : .off
        clickItem.isEnabled = S.mode == .fade
        focusItem.state = S.focusVideo ? .on : .off
        autoItem.state = S.autoCapture ? .on : .off
        handBackItem.state = S.handBack ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        baseSlider.set(S.baseOpacity)
        nearSlider.set(S.nearOpacity)
        edgeSlider.set(S.edgeSoftness)
        holdSlider.set(S.holdSeconds)
    }

    // MARK: - Azioni

    func open(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s) else { return }
        if Player.isDRM(url) {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Questo sito è protetto (DRM)"
            a.informativeText = "Netflix, Prime Video, Disney+ ecc. non possono girare dentro FloatyPIP. Aprilo in Chrome e cambia scheda (o premi ⌃⌥C): uso la PiP di Chrome e la sposto io quando ti avvicini."
            a.runModal()
            return
        }
        captured = nil
        load(url, start: Player.startFromURL(url))
        show()
    }

    @objc func openClipboard() { open(NSPasteboard.general.string(forType: .string) ?? "") }

    @objc func openURLDialog() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Apri video"
        a.informativeText = "Incolla un link (YouTube, Twitch, Vimeo…)"
        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        tf.stringValue = NSPasteboard.general.string(forType: .string) ?? ""
        a.accessoryView = tf
        a.addButton(withTitle: "Apri")
        a.addButton(withTitle: "Annulla")
        a.window.initialFirstResponder = tf
        if a.runModal() == .alertFirstButtonReturn { open(tf.stringValue) }
    }

    @objc func openFullPage() {
        guard let u = currentURL else { return }
        web.evaluateJavaScript("window.__pipTime ? window.__pipTime() : 0") { [weak self] v, _ in
            self?.loadFull(u, start: (v as? NSNumber)?.doubleValue ?? 0)
        }
    }

    @objc func toggleAuto() { S.autoCapture.toggle(); refreshMenuState() }
    @objc func toggleHandBack() { S.handBack.toggle(); refreshMenuState() }

    @objc func setMode(_ sender: NSMenuItem) {
        S.mode = Mode(rawValue: sender.tag) ?? .fade
        refreshMenuState()
    }

    func cycleMode() {
        S.mode = Mode(rawValue: (S.mode.rawValue + 1) % 3) ?? .fade
        refreshMenuState()
        flashTitle(["Trasparente", "Si sposta", "Niente"][S.mode.rawValue])
    }

    @objc func toggleClickThrough() { S.clickThrough.toggle(); refreshMenuState() }

    func nudgeOpacity(_ delta: Double) {
        S.baseOpacity = max(0.1, min(1.0, S.baseOpacity + delta))
        baseSlider.set(S.baseOpacity)
        flashTitle("\(Int((S.baseOpacity * 100).rounded()))%")
    }

    func flashTitle(_ text: String) {
        statusItem.button?.title = " " + text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.statusItem.button?.title = ""
        }
    }

    @objc func setCorner(_ sender: NSMenuItem) {
        S.corner = Corner(rawValue: sender.tag) ?? .bottomRight
        S.origin = nil
        applySize(animated: true)
    }

    @objc func setSize(_ sender: NSMenuItem) {
        S.width = Double(sender.tag)
        applySize(animated: true)
    }

    @objc func toggleFocus() {
        S.focusVideo.toggle()
        installUserScripts(web.configuration.userContentController, start: 0)
        web.evaluateJavaScript("window.__pipFocus = \(S.focusVideo)")
        refreshMenuState()
    }

    @objc func playPause() { web.evaluateJavaScript("window.__pipToggle && window.__pipToggle()") }

    @objc func toggleVisible() {
        if panel.isVisible { hidePiP() } else { show() }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Avvio al login non riuscito"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
        refreshMenuState()
    }

    @objc func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "FloatyPIP"
        a.informativeText = """
        CATTURA AUTOMATICA
        Guarda un video in Chrome/Safari/Arc: quando cambi scheda o app passa nella PiP dal punto in cui eri. Torni alla scheda → riprende lì.

        TIENI ⌘ SOPRA LA FINESTRA
        • trascina = sposta
        • trascina da un angolo = ridimensiona
        • scroll = zoom
        • click = usa il player normalmente

        SCORCIATOIE
        ⌃⌥C  cattura dal browser
        ⌃⌥V  apri link copiato
        ⌃⌥P  mostra / nascondi
        ⌃⌥Spazio  play / pausa
        ⌃⌥M  cambia modalità
        ⌃⌥↑ / ↓  opacità ±10%
        """
        a.runModal()
    }
}

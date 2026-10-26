import Cocoa

/// Una scheda di un browser.
struct TabRef: Equatable {
    let bundle: String
    let key: String
    let url: String
}

enum ProbeState { case playing(Double), ad, idle, jsDenied }

enum ProbeResult {
    case tab(TabRef, ProbeState)
    case automationDenied
    case nothing
}

/// Parla con Chrome / Safari / Arc / Brave / Edge via AppleScript.
final class BrowserBridge {
    static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "org.chromium.Chromium", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"
    ]
    static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static func supports(_ b: String?) -> Bool {
        guard let b else { return false }
        return chromium.contains(b) || safari.contains(b)
    }
    static func name(_ b: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: b)?.deletingPathExtension().lastPathComponent ?? b
    }

    private let q = DispatchQueue(label: "floatypip.applescript")

    // MARK: JS (solo apici singoli: va dentro una stringa AppleScript)

    private static let bestJS = "var b=null,a=0;document.querySelectorAll('video').forEach(function(v){var s=v.clientWidth*v.clientHeight;if(v.readyState>0&&s>=a){a=s;b=v}});"

    static let probeJS = "(function(){if(document.querySelector('.ad-showing'))return 'ad';" + bestJS +
        "if(!b)return 'none';return (b.paused||b.ended?'p':'g')+b.currentTime;})()"

    static let pauseJS = "(function(){var ad=!!document.querySelector('.ad-showing');" + bestJS +
        "var t=b?b.currentTime:0;document.querySelectorAll('video').forEach(function(v){v.pause()});return ad?'ad':''+t;})()"

    static func resumeJS(_ t: Double) -> String {
        "(function(){" + bestJS + "if(b){b.currentTime=\(t);b.play()}return 'ok';})()"
    }

    // MARK: AppleScript

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// PiP nativa del browser (per Netflix & co.)
    static let nativePipJS = "(function(){" + bestJS +
        "if(!b)return 'none';try{b.disablePictureInPicture=false;b.removeAttribute('disablepictureinpicture');" +
        "var p=b.requestPictureInPicture();if(p&&p.catch)p.catch(function(){});return 'ok'}catch(e){return 'err'}})()"
    static let exitPipJS = "(function(){if(document.pictureInPictureElement){document.exitPictureInPicture();return 'ok'}return 'none'})()"

    private func run(_ src: String, _ done: @escaping (String?, Int?) -> Void) {
        q.async {
            var err: NSDictionary?
            let out = NSAppleScript(source: src)?.executeAndReturnError(&err)
            let code = err?[NSAppleScript.errorNumber] as? Int
            let s = err == nil ? out?.stringValue : nil
            DispatchQueue.main.async { done(s, code) }
        }
    }

    /// Scheda attiva del browser + stato del video.
    func probe(_ bundle: String, _ done: @escaping (ProbeResult) -> Void) {
        let js = Self.esc(Self.probeJS)
        let src: String
        if Self.safari.contains(bundle) {
            src = """
            with timeout of 3 seconds
            tell application id "\(bundle)"
              if (count of windows) is 0 then return ""
              set w to front window
              set t to current tab of w
              set k to ((id of w) as text) & ":" & ((index of t) as text)
              set u to ""
              try
                set u to (URL of t) as text
              end try
              try
                set r to (do JavaScript "\(js)" in t) as text
              on error m number n
                set r to "ERR:" & n & ":" & m
              end try
              return k & linefeed & u & linefeed & r
            end tell
            end timeout
            """
        } else {
            src = """
            with timeout of 3 seconds
            tell application id "\(bundle)"
              if (count of windows) is 0 then return ""
              set t to active tab of front window
              set k to (id of t) as text
              set u to ""
              try
                set u to (URL of t) as text
              end try
              try
                set r to (execute t javascript "\(js)") as text
              on error m number n
                set r to "ERR:" & n & ":" & m
              end try
              return k & linefeed & u & linefeed & r
            end tell
            end timeout
            """
        }
        run(src) { out, code in
            if code == -1743 { return done(.automationDenied) }
            guard let out, !out.isEmpty else { return done(.nothing) }
            let lines = out.components(separatedBy: "\n")
            guard lines.count >= 3 else { return done(.nothing) }
            let tab = TabRef(bundle: bundle, key: lines[0], url: lines[1])
            let r = lines[2...].joined(separator: "\n")
            if r.hasPrefix("ERR:") {
                if r.contains("-1743") { return done(.automationDenied) }
                return done(.tab(tab, r.lowercased().contains("javascript") ? .jsDenied : .idle))
            }
            if r == "ad" { return done(.tab(tab, .ad)) }
            if r.hasPrefix("g"), let t = Double(r.dropFirst()) { return done(.tab(tab, .playing(t))) }
            done(.tab(tab, .idle))
        }
    }

    /// Esegue JS nella scheda indicata (anche se non è più in primo piano).
    func exec(_ tab: TabRef, js: String, _ done: @escaping (String?) -> Void) {
        let j = Self.esc(js)
        let src: String
        if Self.safari.contains(tab.bundle) {
            let p = tab.key.split(separator: ":")
            guard p.count == 2 else { return done(nil) }
            src = """
            with timeout of 3 seconds
            tell application id "\(tab.bundle)"
              return (do JavaScript "\(j)" in tab \(p[1]) of window id \(p[0])) as text
            end tell
            end timeout
            """
        } else {
            src = """
            with timeout of 3 seconds
            tell application id "\(tab.bundle)"
              repeat with w in windows
                repeat with t in tabs of w
                  if ((id of t) as text) is "\(Self.esc(tab.key))" then
                    return (execute t javascript "\(j)") as text
                  end if
                end repeat
              end repeat
            end tell
            end timeout
            return ""
            """
        }
        run(src) { out, _ in done(out) }
    }

    /// Mette in pausa il video nella scheda e restituisce il punto in cui era.
    func pauseAndGetTime(_ tab: TabRef, _ done: @escaping (Double?) -> Void) {
        exec(tab, js: Self.pauseJS) { out in
            guard let out, out != "ad" else { return done(nil) }
            done(Double(out))
        }
    }

    func resume(_ tab: TabRef, at t: Double) {
        exec(tab, js: Self.resumeJS(t)) { _ in }
    }
}

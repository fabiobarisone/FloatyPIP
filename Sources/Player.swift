import Foundation

/// Trasforma un link in un player "pulito" (embed ufficiale) quando possibile:
/// YouTube (youtube-nocookie, niente banner cookie, molti meno spot), Twitch, Vimeo.
enum Player {
    static let host = "floatypip.local"
    static let base = URL(string: "https://\(host)/")!

    /// Siti con DRM: non possono girare nel nostro player → PiP nativa del browser.
    static let drmHosts = ["netflix.com", "primevideo.com", "disneyplus.com", "tv.apple.com", "max.com",
                           "hbomax.com", "paramountplus.com", "dazn.com", "nowtv.it", "now.it", "skygo.sky.it",
                           "mediasetinfinity.mediaset.it", "mediasetinfinity.it", "crunchyroll.com", "timvision.it"]
    static func isDRM(_ u: URL) -> Bool {
        guard let h = u.host?.lowercased() else { return false }
        if drmHosts.contains(where: { h == $0 || h.hasSuffix("." + $0) }) { return true }
        return h.contains("amazon.") && u.path.contains("/gp/video")
    }

    /// "90", "90s", "1m30s", "1h2m3s" → secondi
    static func parseTime(_ s: String?) -> Double {
        guard var s = s?.lowercased(), !s.isEmpty else { return 0 }
        if let v = Double(s) { return v }
        var total = 0.0, num = ""
        if s.hasSuffix("s") == false && s.last?.isNumber == true { s += "s" }
        for c in s {
            if c.isNumber || c == "." { num.append(c); continue }
            let v = Double(num) ?? 0; num = ""
            switch c { case "h": total += v * 3600; case "m": total += v * 60; case "s": total += v; default: break }
        }
        return total
    }

    static func query(_ u: URL, _ name: String) -> String? {
        URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    static func startFromURL(_ u: URL) -> Double {
        if let t = query(u, "t") ?? query(u, "start") { return parseTime(t) }
        if let f = u.fragment, f.hasPrefix("t=") { return parseTime(String(f.dropFirst(2))) }
        return 0
    }

    static func youtubeID(_ u: URL) -> String? {
        guard let h = u.host?.lowercased() else { return nil }
        let parts = u.pathComponents.filter { $0 != "/" }
        if h.hasSuffix("youtu.be") { return parts.first }
        guard h.contains("youtube.com") || h.contains("youtube-nocookie.com") else { return nil }
        if parts.first == "watch" { return query(u, "v") }
        if parts.count >= 2, ["shorts", "live", "embed", "v"].contains(parts[0]) { return parts[1] }
        return nil
    }

    static func twitch(_ u: URL) -> (channel: String?, video: String?)? {
        guard let h = u.host?.lowercased(), h.hasSuffix("twitch.tv"), !h.hasPrefix("player.") else { return nil }
        let parts = u.pathComponents.filter { $0 != "/" }
        guard let first = parts.first else { return nil }
        if first == "videos", parts.count >= 2 { return (nil, parts[1]) }
        let reserved = ["directory", "settings", "p", "downloads", "search", "subscriptions", "inventory", "wallet", "drops"]
        if reserved.contains(first) { return nil }
        return (first, nil)
    }

    static func vimeoID(_ u: URL) -> String? {
        guard let h = u.host?.lowercased(), h.hasSuffix("vimeo.com") else { return nil }
        return u.pathComponents.reversed().first { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static let head = """
    <!doctype html><html><head><meta charset="utf-8">
    <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
    #p,#p iframe,iframe#p{position:fixed;inset:0;width:100%!important;height:100%!important;border:0}</style>
    <script>window.__pipEmbed=true;</script></head><body>
    """

    private static func js(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }

    /// HTML del player embed, oppure nil se il sito va aperto come pagina completa.
    static func html(for u: URL, start: Double) -> String? {
        let st = max(0, Int(start))
        if let id = youtubeID(u) {
            return head + """
            <div id="p"></div>
            <script>
            var player, ready = false;
            function onYouTubeIframeAPIReady(){
              player = new YT.Player('p', {
                videoId: '\(js(id))', host: 'https://www.youtube-nocookie.com',
                playerVars: { autoplay: 1, start: \(st), playsinline: 1, rel: 0, modestbranding: 1, origin: 'https://\(host)' },
                events: {
                  onReady: function(e){ ready = true; e.target.playVideo(); },
                  onError: function(e){ window.webkit.messageHandlers.pip.postMessage({type: 'embedError', code: e.data}); }
                }
              });
            }
            window.__pipTime = function(){ return ready ? player.getCurrentTime() : \(st); };
            window.__pipToggle = function(){ if (!ready) return; player.getPlayerState() == 1 ? player.pauseVideo() : player.playVideo(); };
            window.__pipPause = function(){ if (ready) player.pauseVideo(); };
            window.__pipPlay = function(){ if (ready) player.playVideo(); };
            </script>
            <script src="https://www.youtube.com/iframe_api"></script>
            </body></html>
            """
        }
        if let tw = twitch(u) {
            var opt = "parent: ['\(host)'], width: '100%', height: '100%', autoplay: true, muted: false"
            if let c = tw.channel { opt += ", channel: '\(js(c))'" }
            if let v = tw.video {
                opt += ", video: '\(js(v))'"
                if st > 0 { opt += ", time: '\(st / 3600)h\((st % 3600) / 60)m\(st % 60)s'" }
            }
            return head + """
            <div id="p"></div>
            <script src="https://player.twitch.tv/js/embed/v1.js"></script>
            <script>
            var player = new Twitch.Player('p', { \(opt) });
            window.__pipTime = function(){ try { return player.getCurrentTime(); } catch(e) { return 0; } };
            window.__pipToggle = function(){ try { player.isPaused() ? player.play() : player.pause(); } catch(e) {} };
            window.__pipPause = function(){ try { player.pause(); } catch(e) {} };
            window.__pipPlay = function(){ try { player.play(); } catch(e) {} };
            </script></body></html>
            """
        }
        if let id = vimeoID(u) {
            return head + """
            <iframe id="p" src="https://player.vimeo.com/video/\(id)?autoplay=1#t=\(st)s" allow="autoplay; fullscreen; picture-in-picture"></iframe>
            <script src="https://player.vimeo.com/api/player.js"></script>
            <script>
            var t = \(st), paused = false, player = new Vimeo.Player(document.getElementById('p'));
            player.on('timeupdate', function(d){ t = d.seconds; });
            player.on('pause', function(){ paused = true; });
            player.on('play', function(){ paused = false; });
            window.__pipTime = function(){ return t; };
            window.__pipToggle = function(){ paused ? player.play() : player.pause(); };
            window.__pipPause = function(){ player.pause(); };
            window.__pipPlay = function(){ player.play(); };
            </script></body></html>
            """
        }
        return nil
    }
}

/// JavaScript iniettato nelle pagine "complete" (non embed):
/// isola il <video> più grande, salta/silenzia gli spot YouTube, applica il tempo di partenza.
enum FocusScript {
    static func prelude(focus: Bool, start: Double) -> String {
        "window.__pipFocus = \(focus); window.__pipStart = \(start);"
    }

    static let source = """
    (function(){
      if (window.__pip || window.__pipEmbed) return; window.__pip = true;
      if (window.__pipFocus === undefined) window.__pipFocus = true;
      var startApplied = !(window.__pipStart > 0), autoplayed = false, adMuted = false;
      window.__pipUserPaused = false;
      var st = document.createElement('style');
      st.textContent = `
        .__pipv{position:fixed!important;inset:0!important;left:0!important;top:0!important;
          width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;
          z-index:2147483647!important;background:#000!important;object-fit:contain!important;transform:none!important}
        html.__pipon, html.__pipon body{overflow:hidden!important;background:#000!important}
        html.__pipon body *:not(:has(.__pipv)):not(.__pipv){visibility:hidden!important}`;
      document.documentElement.appendChild(st);

      function best(){
        var b = null, a = 0;
        document.querySelectorAll('video').forEach(function(v){
          var r = v.getBoundingClientRect();
          var s = (v.videoWidth || r.width) * (v.videoHeight || r.height);
          if (s >= a) { a = s; b = v; }
        });
        return b;
      }
      window.__pipTime = function(){ var v = best(); return v ? v.currentTime : 0; };
      window.__pipPause = function(){ window.__pipUserPaused = true; document.querySelectorAll('video').forEach(function(v){ v.pause(); }); };
      window.__pipPlay = function(){ window.__pipUserPaused = false; var v = best(); if (v) v.play().catch(function(){}); };
      window.__pipToggle = function(){ var v = best(); if (!v) return; v.paused ? window.__pipPlay() : window.__pipPause(); };

      setInterval(function(){
        document.querySelectorAll('.ytp-skip-ad-button,.ytp-ad-skip-button,.ytp-ad-skip-button-modern,.ytp-ad-skip-button-container button')
          .forEach(function(b){ try { b.click(); } catch(e){} });
        var ad = document.querySelector('.ad-showing');
        var v0 = document.querySelector('video');
        if (ad && v0) {
          if (!v0.muted) { v0.muted = true; adMuted = true; }
          if (isFinite(v0.duration) && v0.duration > 0 && v0.currentTime < v0.duration - 0.3) v0.currentTime = v0.duration - 0.1;
          if (v0.paused) v0.play().catch(function(){});
        } else if (adMuted && v0) { v0.muted = false; adMuted = false; }

        var b = best();
        document.querySelectorAll('video').forEach(function(v){ if (v !== b) v.classList.remove('__pipv'); });
        if (b) b.classList.toggle('__pipv', !!window.__pipFocus);
        document.documentElement.classList.toggle('__pipon', !!window.__pipFocus && !!b);

        if (b && !ad) {
          if (!startApplied && b.readyState > 0) { b.currentTime = window.__pipStart; startApplied = true; }
          if (!autoplayed && b.paused && !window.__pipUserPaused) b.play().catch(function(){});
          if (!b.paused) autoplayed = true;
        }
      }, 400);

      document.addEventListener('click', function(e){
        if (!window.__pipFocus) return;
        if (!document.querySelector('video.__pipv')) return;
        e.preventDefault(); e.stopPropagation();
        window.__pipToggle();
      }, true);
    })();
    """
}

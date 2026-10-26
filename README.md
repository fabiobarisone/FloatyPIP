# FloatyPIP

Finestra video flottante per macOS 13+ che non ti costringe a spostarla di continuo: quando ti avvicini col mouse diventa trasparente (e i click passano sotto) oppure scappa dall'altra parte dello schermo.

## Funzioni
- **Cattura automatica dal browser** (Chrome, Safari, Arc, Brave, Edge): guardi un video, cambi scheda o app → passa nella PiP dal punto in cui eri. Torni alla scheda → riprende lì.
- **Player pulito** per YouTube (youtube-nocookie), Twitch, Vimeo; altri siti in pagina completa con "solo video" e salto spot YouTube.
- **Netflix, Prime Video, Disney+, NOW, DAZN…** (DRM): usa la PiP nativa di Chrome e la sposta quando ti avvicini.
- **Trasparenza**: opacità normale + opacità col mouse vicino, bordi sfumati nel trasparente, parte al 100% per qualche secondo e poi sfuma.
- **Tieni ⌘** sulla finestra: trascina = sposta, angoli = ridimensiona, scroll = zoom, click = player normale.
- Finestra minima 120 px, posizione e impostazioni salvate, avvio al login.

## Installazione
```bash
git clone https://github.com/fabiobarisone/FloatyPIP.git && cd FloatyPIP
./build.sh install
```
Servono solo i Command Line Tools (`xcode-select --install`). Nessun Xcode, nessuna dipendenza.

### Permessi (una volta)
- **Chrome**: Visualizza → Opzioni per sviluppatori → "Consenti JavaScript da eventi Apple" (Safari: menu Sviluppo → "Consenti JavaScript da Apple Events").
- **Automazione**: rispondi OK a "FloatyPIP vuole controllare Google Chrome".
- **Accessibilità** (solo per spostare la PiP di Chrome su Netflix & co.): Impostazioni di Sistema → Privacy e sicurezza → Accessibilità.

## Scorciatoie
| Tasti | Azione |
|---|---|
| ⌃⌥C | cattura il video dal browser |
| ⌃⌥V | apri link copiato |
| ⌃⌥P | mostra / nascondi |
| ⌃⌥Spazio | play / pausa |
| ⌃⌥M | cambia modalità (trasparente → si sposta → niente) |
| ⌃⌥↑ / ↓ | opacità ±10% |

## Struttura
```
Sources/
  AppDelegate.swift    finestra, menu, logica principale
  BrowserBridge.swift  AppleScript verso Chrome/Safari (cattura e ripresa)
  NativePiP.swift      gestione PiP nativa di Chrome (siti DRM)
  Player.swift         embed YouTube / Twitch / Vimeo
  FocusScript.swift    JS per pagine complete (solo video, salto spot)
  Views.swift          overlay ⌘, slider del menu
  HotKeys.swift        scorciatoie globali
  Settings.swift       preferenze
```

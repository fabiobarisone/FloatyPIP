# FloatyPIP

**La finestra video che non ti dà fastidio.**
Guardi YouTube, Twitch, Netflix… in una piccola finestra sempre in primo piano. Quando ci passi sopra col mouse diventa trasparente (e puoi cliccare quello che c'è sotto), oppure si sposta da sola dall'altra parte dello schermo. Non devi più trascinarla in continuazione.

Funziona su **Mac con macOS 13 Ventura o più recente** (sia Apple Silicon M1/M2/M3/M4 sia Intel).

---

## ⬇️ Installazione (5 minuti, nessuna competenza tecnica)

### 1. Scarica
Vai alla pagina **[Releases](https://github.com/fabiobarisone/FloatyPIP/releases/latest)** e clicca sul file **`FloatyPIP-x.x.dmg`** (sotto "Assets"). Finisce nella cartella **Download**.

### 2. Installa
1. Apri la cartella **Download** e fai doppio clic su **FloatyPIP-x.x.dmg**.
2. Si apre una finestra con l'icona di FloatyPIP e la cartella **Applicazioni**.
3. **Trascina l'icona di FloatyPIP sopra la cartella Applicazioni.** Fatto.
4. Puoi chiudere la finestra (e trascinare nel Cestino il disco "FloatyPIP" che compare a sinistra nel Finder).

### 3. Primo avvio (solo la prima volta)
FloatyPIP è gratuita e non è registrata presso Apple, quindi la prima volta macOS chiede conferma. È normale.

1. Apri **Applicazioni** e fai doppio clic su **FloatyPIP**.
2. Compare un avviso tipo *"Apple non può verificare che FloatyPIP sia privo di malware"*. Premi **Fine** (o **Annulla**). **Non** premere "Sposta nel Cestino".
3. Apri il menu  in alto a sinistra → **Impostazioni di Sistema** → **Privacy e sicurezza**.
4. Scorri in fondo: trovi la scritta *"FloatyPIP è stato bloccato…"*. Premi **Apri comunque** e inserisci la password del Mac (o usa Touch ID).
5. Premi di nuovo **Apri**.

> Su macOS 14 Sonoma o precedenti è più veloce: **tasto destro** (o ctrl+clic) su FloatyPIP → **Apri** → **Apri**.

Da ora si apre normalmente. FloatyPIP **non ha icona nel Dock**: vive in alto a destra nella **barra dei menu**, con un'icona a forma di finestrella (▣). Cliccala per il menu.

### 4. Collegala al browser (consigliato, una volta sola)
Serve per far passare in automatico nella finestrella il video che stai guardando.

**Google Chrome** (anche Brave, Edge, Arc):
1. Apri Chrome.
2. Nella barra dei menu in alto: **Visualizza** → **Opzioni per sviluppatori** → clicca **Consenti JavaScript da eventi Apple** (deve comparire la spunta ✓).

**Safari**:
1. Safari → **Impostazioni** → scheda **Avanzate** → attiva **Mostra funzionalità per sviluppatori web**.
2. Nella barra dei menu compare **Sviluppo**: clicca **Consenti JavaScript da Apple Events**.

La prima volta che FloatyPIP prova a leggere il browser, macOS chiede *"FloatyPIP vuole controllare Google Chrome"*: premi **OK** (o **Consenti**).

### 5. Solo per Netflix, Prime Video, Disney+ & co.
Questi siti sono protetti e non possono girare dentro FloatyPIP: l'app usa la finestrella di Chrome e la sposta quando ti avvicini. Per farlo serve un permesso:
**Impostazioni di Sistema** → **Privacy e sicurezza** → **Accessibilità** → attiva l'interruttore accanto a **FloatyPIP** (se non c'è, premi **+** e scegli FloatyPIP da Applicazioni).

### Avvio automatico (facoltativo)
Icona FloatyPIP nella barra dei menu → **Avvia al login**.

---

## 🎬 Come si usa

**Modo automatico** (dopo il punto 4): guarda un video nel browser e **cambia scheda o app** → il video continua nella finestrella dal punto in cui eri. **Torni alla scheda** → la finestrella si chiude e il video riprende lì.

**Modo manuale**: copia il link di un video e premi **⌃⌥V** (ctrl + option + V).

**Muovere e ridimensionare**: tieni premuto **⌘ (cmd)** e porta il mouse sulla finestra:
- trascina = sposta
- trascina da un angolo = ingrandisci / rimpicciolisci
- rotellina o due dita sul trackpad = zoom
- clic = usa il player normalmente (pausa, avanti, impostazioni…)

**Dal menu (icona nella barra in alto)**:
- *Quando il mouse si avvicina*: diventa trasparente · si sposta dall'altra parte · niente
- *Opacità* e *Opacità col mouse vicino*
- *Bordi sfumati*: il video sfuma ai lati
- *Al 100% quando parte*: secondi a piena opacità prima di sfumare
- *Angolo* e *Dimensione* (da Mini a Extra)

### Scorciatoie
| Tasti | Cosa fa |
|---|---|
| ⌃⌥C | prende il video dalla scheda del browser |
| ⌃⌥V | apre il link copiato |
| ⌃⌥P | mostra / nasconde la finestrella |
| ⌃⌥Spazio | play / pausa |
| ⌃⌥M | cambia comportamento (trasparente → si sposta → niente) |
| ⌃⌥↑ / ↓ | più / meno opaca |

⌃ = ctrl · ⌥ = option (alt) · ⌘ = cmd

---

## ❓ Problemi comuni

- **Non vedo l'icona nella barra dei menu** → se hai molte icone potrebbe essere nascosta dietro la "tacca" dello schermo. Chiudi qualche app della barra o usa ⌃⌥P.
- **Il video non passa da solo nella finestrella** → controlla il punto 4 (opzione JavaScript nel browser + permesso "controllare Google Chrome"). Puoi verificarlo in Impostazioni di Sistema → Privacy e sicurezza → **Automazione** → FloatyPIP.
- **Un video non parte o si blocca** → icona FloatyPIP → **Apri pagina completa (se il player non va)**.
- **Netflix dà errore dentro FloatyPIP** → è normale (protezione DRM): guardalo in Chrome e cambia scheda, vedi punto 5.

## 🗑️ Disinstallare
Icona FloatyPIP → **Esci**, poi trascina **FloatyPIP** da Applicazioni nel Cestino.

---

## Per sviluppatori
Compilare dal codice (servono solo i Command Line Tools: `xcode-select --install`):
```bash
git clone https://github.com/fabiobarisone/FloatyPIP.git && cd FloatyPIP
./build.sh install   # compila, installa in /Applications e avvia
./dmg.sh             # crea dist/FloatyPIP-<versione>.dmg (Apple Silicon + Intel)
```

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

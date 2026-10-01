# Ny slumpmässig bana vid omspel

Datum: 2026-10-01.

Rummets seed återanvändes tidigare vid varje omspel. Hosten väljer nu ett annat giltigt seed när ett slumpmässigt rum går in i nästa lobbycykel. Första rundan använder rummets ursprungliga seed. Ett seed som användaren anger vid skapandet innebär fortsatt återspel av samma bana; hjälptipset beskriver båda fallen.

Valet görs en gång per rum/lobbycykel och bevaras genom polling, återanslutning och publiceringsretry. Gäster väljer aldrig egna seed. Den nya banan och dess seed publiceras med befintlig multiplayer_v2_set_manifest, som atomiskt ändrar seed/hash/content_revision och återställer readiness/manifest-ACK. Ingen ny migration eller ändring av live-backend krävs.

Starten blockeras från ny lobbycykel tills den genererade banan matchar rummets bekräftade manifest. Ready är avstängt när den lokala banan ännu inte stämmer med rummets manifest. Befintliga kontroller av readiness och manifest-ACK gäller även den nya banan. Diagnostik registrerar seedbytet och bekräftad aktuell bana; round_started-händelsen innehåller seed och manifest_hash.

Verifierat:

- Nytt regressionstest: ursprunglig bana, andra/tredje rundans nya seed/hash, stabil retry/polling, gästparitet, startbarriär, uppdaterad diagnostik, fast seed och byte till nytt rum.
- Multiplayer contract, session lifecycle och retirement-tester passerade.
- Riktigt lokalt WebRTC-test passerade initial synk, 20 sekunders lobby och tre resultat-/ACK-/lobbycykler. Det använder en transportfixtur och verifierar inte live-backendens seedbyte i ett manuellt browserlopp.
- Godot-import utan parse-/scriptfel; sandlådans begränsningar för editorinställningar/certifikatlagring kvarstår.

Webversionen byggdes från källcommit 3fa07da och publicerades i Pages-commit be29160. Build-id: multiplayer-course-rotation-3fa07da-20261001. Azure-push och GitHub Pages-deploy lyckades. Den publicerade root-adressen laddade spelets neutrala game/index.html med rätt build-id i webbläsaren. Regressionstestet och kontraktstestet passerade även från den arkiverade källversion som användes för exporten.

Befintliga ocommittade singleplayer-fixturändringar hölls utanför ändringen och exporten. Publik adress och gamla kompatibilitetsadresser behålls. Ingen faktisk browsermatch kördes under denna kontroll. Testa genom att skapa ett nytt rum med seedfältet tomt, spela två rundor via samma lobby och kontrollera att banan byts. Ingen profilering eller diagnostikinsamling krävs för den kontrollen.

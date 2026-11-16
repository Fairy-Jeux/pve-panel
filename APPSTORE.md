# Déploiement iPhone & App Store — PVE Center (Liquid Glass)

PVE Command Center intègre une interface **Liquid Glass** inspirée d’iOS 26 (surfaces translucides spéculaires, barre d’onglets flottante iPhone, fiches modales `.ios-sheet`, support complet des Safe Areas) ainsi qu’un projet iOS natif **Capacitor 8** (`frontend/ios/`) prêt pour **TestFlight** et l’**App Store**.

---

## 1. Architecture mobile iOS

- **Bundle ID par défaut :** `io.github.pvepanel.app` (à adapter dans `frontend/capacitor.config.ts` et Xcode si nécessaire)
- **Nom de l’app :** `PVE Center`
- **Transport réseau natif (`CapacitorHttp`) :** activé dans `frontend/capacitor.config.ts` pour effectuer les requêtes HTTPS directement via `URLSession` iOS sans blocage CORS vers votre endpoint **Tailscale Serve** (`https://<nom-lxc>.<tailnet>.ts.net`).
- **Configuration `Info.plist` pré-appliquée :**
  - `ITSAppUsesNonExemptEncryption = false` (simplifie la déclaration d’exportation cryptographique App Store Connect)
  - `NSAppTransportSecurity` (`NSAllowsArbitraryLoads` et `NSAllowsLocalNetworking`) pour autoriser les connexions vers un homelab / Tailscale / IP LAN auto-hébergé
  - `UIViewControllerBasedStatusBarAppearance = true`
- **Icône App Store :** `AppIcon-512@2x.png` (`1024x1024`, RGB opaque sans canal alpha, générée depuis `frontend/public/icon.svg`).

---

## 2. Mode Démo interactif (Conformité Apple App Review — Guideline 2.1)

L’équipe de révision Apple ne dispose pas d’un accès au réseau privé Tailscale de votre homelab. L’application embarque donc un **Mode Démo interactif** dans `frontend/src/lib/apiClient.ts` :

- Au premier lancement sans serveur configuré, la fiche **« Connexion Serveur & Mode Démo »** propose en un toucher le bouton **« Activer le Mode Démo »** ainsi que la saisie de votre URL Tailscale Serve.
- Toutes les vues et actions fonctionnent localement en mémoire : démarrage/arrêt/redémarrage de LXC & VMs Proxmox, graphiques node & stockage 32 To, widgets Jellyfin / Radarr / Sonarr / Prowlarr / qBittorrent, approbation de demandes Jellyseerr, bascule mode tortue / torrents qBittorrent et gestion des comptes utilisateurs.

### Texte prêt à coller dans App Store Connect (`App Review Information -> Notes`)

> **Demo Mode (No private VPN required):**
> PVE Center is a remote companion dashboard for self-hosted Proxmox VE & homelab servers protected by Tailscale. Because private homelab servers are unreachable from outside the owner's Tailnet, we included a built-in interactive Demo Mode:
> 1. Launch the app. The **"Connexion Serveur & Mode Démo"** sheet opens automatically.
> 2. Tap **"Activer le Mode Démo"**.
> 3. You can browse all tabs (Overview, Storage & SMART Drives, Proxmox LXC/VM power actions, Media Services & Live Widgets, Operations / Queue / Requests, and User Management) and test interactive mutations in real time.
> You can reopen **"Serveur / Démo"** from the top bar at any time.

---

## 3. Comment tester ou compiler sur iPhone

### Option A — Installation instantanée PWA depuis votre iPhone (0 certificat requis)
1. Ouvrez `https://<votre-panel>.<tailnet>.ts.net` dans **Safari** sur iPhone (avec Tailscale actif sur l’iPhone).
2. Touchez **Partager** -> **Sur l’écran d’accueil**.
3. L’application s’ouvre en plein écran (`black-translucent`), sans barre Safari, avec la barre flottante Liquid Glass et les gestes iOS.

### Option B — Compilation locale avec Xcode (Mac avec Xcode installé)
```bash
cd frontend
npm install
npm run ios:sync
npm run ios:open
```
Dans Xcode :
1. Sélectionnez votre **Team** dans *Signing & Capabilities* et ajustez le **Bundle Identifier** si souhaité.
2. Branchez votre iPhone en USB et lancez (`Cmd + R`), ou utilisez **Product -> Archive -> Distribute App -> TestFlight & App Store**.

### Option C — Build Cloud automatique via GitHub Actions (`macos-15`)
Le workflow [`.github/workflows/ios-appstore.yml`](.github/workflows/ios-appstore.yml) compile le projet iOS sur `macos-15` :
- **Sans secrets Apple :** vérifie le build Release Xcode et publie l’archive `.xcarchive` en artefact GitHub.
- **Avec secrets Apple (`APPLE_CERTIFICATE_BASE64`, `APPLE_P12_PASSWORD`, `APPLE_PROVISIONING_PROFILE_BASE64`, `APPLE_PROVISIONING_PROFILE_NAME`, `APPLE_TEAM_ID`, et optionnellement `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_PRIVATE_KEY`) :** signe le `.ipa` et peut l’uploader automatiquement sur **TestFlight / App Store Connect**.

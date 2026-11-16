# Déploiement iPhone & App Store — PVE Center (100 % Natif SwiftUI + Alternative Web PWA)

PVE Command Center propose désormais une **application iOS 100 % native en Swift 6 & SwiftUI** (`ios-native/PVECenter.xcodeproj`) conçue selon les *Apple Human Interface Guidelines*, tout en conservant le dashboard web Liquid Glass déployé sur Proxmox.

---

## 1. Architecture iOS 100 % Native (`ios-native/`)

- **Projet Xcode natif :** `ios-native/PVECenter.xcodeproj` (schéma `PVECenter`, Bundle ID par défaut `io.github.pvepanel.app`)
- **Technologies Apple natives :**
  - **Swift 6** + **SwiftUI** (`NavigationStack`, `TabView` native, `.searchable`, `.refreshable`, `.confirmationDialog`, `.contextMenu`, `.sheet`)
  - **Observation Framework** (`@Observable`, `@Bindable`) + **Swift Concurrency** (`async/await`, `actor APIClient`, `actor DemoDataStore`)
  - **Swift Charts** (`BarMark` CPU/RAM/Système & `SectorMark` jauge circulaire Pool MergerFS)
  - **Matériaux & Haptique Apple HIG** : `.ultraThinMaterial` / `.regularMaterial`, `SF Symbols` hiérarchiques, Dynamic Type, adaptation automatique **Light Mode / Dark Mode**, retour haptique `.sensoryFeedback`
- **Configuration `ios-native/PVECenter/Resources/Info.plist` :**
  - `ITSAppUsesNonExemptEncryption = false`
  - `NSAppTransportSecurity` (`NSAllowsArbitraryLoads = true`, `NSAllowsLocalNetworking = true`) pour joindre tout serveur Tailscale Serve / LAN
  - `UIViewControllerBasedStatusBarAppearance = true`
- **Vérification locale en CLI (sans Xcode complet requis) :**
  ```bash
  cd ios-native
  swift build -c release
  ```

---

## 2. Mode Démo natif (`DemoDataStore`) & Conformité App Store (Guideline 2.1)

L’équipe de révision Apple ne peut pas accéder au Tailnet privé du propriétaire. L’application intègre donc un store Swift `actor DemoDataStore` entièrement autonome en mémoire :

- Au premier lancement sans URL serveur configurée, la fiche **« Serveur & Connexion »** s’ouvre automatiquement et propose en un toucher **« Activer le Mode Démo »**.
- Toutes les vues et actions fonctionnent localement : démarrage/arrêt/redémarrage de LXC & VMs Proxmox, graphiques Swift Charts, stockage & SMART, widgets Jellyfin/Radarr/Sonarr/Prowlarr/qBittorrent, demandes Jellyseerr, Mode Tortue qBittorrent et gestion complète des utilisateurs.

### Notes prêtes à coller dans App Store Connect (`App Review Information`)

> **Demo Mode (No private VPN required):**
> PVE Center is a native SwiftUI companion client for self-hosted Proxmox VE & homelab servers protected by Tailscale Serve. Because private homelab servers are unreachable from outside the owner's Tailnet, we built a full in-memory interactive Demo Mode:
> 1. Launch the app. The **"Serveur & Connexion"** sheet opens automatically.
> 2. Tap **"Activer le Mode Démo"**.
> 3. Explore all tabs (Accueil, Proxmox LXC/VM, Stockage & Swift Charts, Services, Actions / Jellyseerr / qBittorrent, and Comptes) and trigger real-time interactive mutations.
> You can reopen **"Serveur & Connexion"** anytime from the top-right toolbar icon.

---

## 3. Options d’installation & Build

### Option A — Compiler et installer l’app native SwiftUI avec Xcode
1. Ouvrez `ios-native/PVECenter.xcodeproj` dans Xcode (macOS avec Xcode 16+).
2. Sélectionnez votre **Team** dans *Signing & Capabilities* et ajustez le **Bundle Identifier** si souhaité.
3. Lancez sur votre iPhone (`Cmd + R`), ou utilisez **Product -> Archive -> Distribute App -> TestFlight & App Store**.

### Option B — Build Cloud automatique via GitHub Actions (`macos-15`)
Le workflow [`.github/workflows/ios-appstore.yml`](.github/workflows/ios-appstore.yml) exécute automatiquement :
1. **`swift-verify`** : `swift build -c release` dans `ios-native/` sur `macos-15`.
2. **`build-ios`** : archive Xcode `ios-native/PVECenter.xcodeproj` (ou `frontend/ios/App/App.xcodeproj` si `project_mode=capacitor`), signe le `.ipa` si vos secrets Apple (`APPLE_CERTIFICATE_BASE64`, `APPLE_P12_PASSWORD`, `APPLE_PROVISIONING_PROFILE_BASE64`, `APPLE_PROVISIONING_PROFILE_NAME`, `APPLE_TEAM_ID`) sont configurés, et publie l’artefact ou envoie vers TestFlight.

### Option C — PWA Safari (0 certificat requis)
Ouvrez `https://<votre-panel>.<tailnet>.ts.net` dans **Safari** sur iPhone -> **Partager** -> **Sur l’écran d’accueil**.

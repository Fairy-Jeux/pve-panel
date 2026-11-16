# Déploiement Apple (iPhone, iPad, Mac & Apple TV) & App Store — PVE Center (100 % Natif SwiftUI + Alternative Web PWA)

PVE Command Center propose une **application Apple 100 % native multi-plateformes en Swift 6 & SwiftUI** (`ios-native/PVECenter.xcodeproj`) conçue selon les *Apple Human Interface Guidelines* pour **iPhone, iPad, Mac et Apple TV (`tvOS 27.0`)**, tout en conservant le dashboard web Liquid Glass déployé sur Proxmox.

---

## 1. Architecture Apple 100 % Native (`ios-native/`)

- **Projet Xcode universel :** `ios-native/PVECenter.xcodeproj` (schéma `PVECenter`, Bundle ID par défaut `io.github.pvepanel.app`, `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx appletvos appletvsimulator"`, `TARGETED_DEVICE_FAMILY = "1,2,3"`, `TVOS_DEPLOYMENT_TARGET = 27.0`) et `ios-native/Package.swift` (`.iOS("27.0")`, `.macOS("27.0")`, `.tvOS("27.0")`).
- **Technologies Apple natives :**
  - **Swift 6** + **SwiftUI** (`NavigationStack`, `NavigationSplitView` sur iPad/Mac, `TabView` adaptée iOS & 10-foot UI sur Apple TV `tvOS 27.0`, `.searchable`, `.refreshable`, `.confirmationDialog`, `.contextMenu`, `.sheet`)
  - **Observation Framework** (`@Observable`, `@Bindable`) + **Swift Concurrency** (`async/await`, `actor APIClient`, `actor DemoDataStore`)
  - **Multi-serveurs, Deep-Link & Setup distant :** liste de serveurs persistés (`SavedServerProfile`), appairage en 1 clic via schéma d'URL `pvecenter://connect?url=...&name=...` (`CFBundleURLTypes` + `.onOpenURL`), et assistant `ServerSetupWizardSheet` pour configurer et tester Proxmox VE, Tailscale et les services médias directement depuis iPhone, iPad, Mac ou Apple TV.
  - **Swift Charts** (`BarMark` CPU/RAM/Système & `SectorMark` jauge circulaire Pool MergerFS)
  - **Matériaux & Haptique Apple HIG** : `.ultraThinMaterial` / `.regularMaterial`, `SF Symbols` hiérarchiques, Dynamic Type, adaptation automatique **Light Mode / Dark Mode**, retour haptique `.sensoryFeedback` (sur iOS/macOS)
- **Configuration `ios-native/PVECenter/Resources/Info.plist` :**
  - `ITSAppUsesNonExemptEncryption = false`
  - `NSAppTransportSecurity` (`NSAllowsArbitraryLoads = true`, `NSAllowsLocalNetworking = true`) pour joindre tout serveur Tailscale Serve / LAN
  - `CFBundleURLTypes` avec le schéma `pvecenter` (`pvecenter://connect`)
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

### Option A — Application macOS native (`PVE Center.app`) directement sur Mac
Générez, signez et installez le bundle macOS natif (`NavigationSplitView`, `MenuBarExtra` dans la barre des menus, raccourcis `⌘R` / `⌘L` / `⌘1`–`⌘6` / `⌘,`) sans même ouvrir Xcode :
```bash
cd ios-native
./build-macos-app.sh
```
Le script compile en Release Swift 6, génère `AppIcon.icns`, signe `ios-native/build/PVE Center.app` et l’installe dans `/Applications` (ou `~/Applications`).

### Option B — Compiler et installer l’app native SwiftUI iPhone / iPad / Mac / Apple TV (`tvOS 27.0`) avec Xcode
1. Ouvrez `ios-native/PVECenter.xcodeproj` dans Xcode (projet universel `iphoneos` + `iphonesimulator` + `macosx` + `appletvos` + `appletvsimulator`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`, `TVOS_DEPLOYMENT_TARGET = 27.0`, `TARGETED_DEVICE_FAMILY = "1,2,3"`).
2. Sélectionnez votre **Team** dans *Signing & Capabilities* et ajustez le **Bundle Identifier** si souhaité.
3. Lancez sur votre iPhone, iPad, Mac ou Apple TV (`Cmd + R`), ou utilisez **Product -> Archive -> Distribute App -> TestFlight & App Store**.
4. Vérification CLI dédiée Apple TV (`tvOS 27.0`) sans signature :
   ```bash
   xcodebuild -project ios-native/PVECenter.xcodeproj -scheme PVECenter -destination 'generic/platform=tvOS' -derivedDataPath /tmp/pve-tvos-ci CODE_SIGNING_ALLOWED=NO build
   ```

### Option C — Build Cloud automatique via GitHub Actions (`macos-15`)
Le workflow [`.github/workflows/ios-appstore.yml`](.github/workflows/ios-appstore.yml) exécute automatiquement :
1. **`swift-verify`** : exécute `./build-macos-app.sh` sur `macos-15`, vérifie la compilation **Apple TV (`tvOS 27.0`)** via `xcodebuild` (`generic/platform=tvOS`) et publie l’artefact `PVE-Center-macOS.zip`.
2. **`build-ios`** : archive Xcode `ios-native/PVECenter.xcodeproj` (ou `frontend/ios/App/App.xcodeproj` si `project_mode=capacitor`), signe le `.ipa` si vos secrets Apple (`APPLE_CERTIFICATE_BASE64`, `APPLE_P12_PASSWORD`, `APPLE_PROVISIONING_PROFILE_BASE64`, `APPLE_PROVISIONING_PROFILE_NAME`, `APPLE_TEAM_ID`) sont configurés, et publie l’artefact ou envoie vers TestFlight.

### Option D — PWA Safari (0 certificat requis)
Ouvrez `https://<votre-panel>.<tailnet>.ts.net` dans **Safari** sur iPhone -> **Partager** -> **Sur l’écran d’accueil**.

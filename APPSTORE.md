# Déploiement Apple (iPhone, iPad, Mac & Apple TV) & App Store — PVE Center

**PVE Command Center** (**PVE Center**) embarque une **application Apple 100 % native multi-plateformes en Swift 6 & SwiftUI** (`ios-native/PVECenter.xcodeproj`) conçue selon les *Apple Human Interface Guidelines* pour **iPhone, iPad, Mac et Apple TV (`tvOS 27.0`)**, en complément de l’interface web PWA Liquid Glass.

---

## 1. Architecture Xcode 27 / Swift 6 Multi-Plateformes (`ios-native/`)

| Élément | Valeur réelle dans le dépôt |
|---|---|
| **Projet Xcode** | `ios-native/PVECenter.xcodeproj` (Swift 6.0, compatibilité Xcode 27+) |
| **Cible universelle** | `PVECenter` (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx appletvos appletvsimulator"`, `TARGETED_DEVICE_FAMILY = "1,2,3"`) |
| **Schémas Xcode** | `PVECenter` (universel iOS / macOS / tvOS) et `PVECenter-iOS` |
| **Cibles de déploiement** | `IPHONEOS_DEPLOYMENT_TARGET = 27.0`, `MACOSX_DEPLOYMENT_TARGET = 27.0`, `TVOS_DEPLOYMENT_TARGET = 27.0` |
| **Bundle Identifier** | `io.ac.pvepanel.app` |
| **Package SwiftPM** | `ios-native/Package.swift` (`swift-tools-version: 6.2`, `.iOS("27.0")`, `.macOS("27.0")`, `.tvOS("27.0")`) |

> **Note sur les cibles multi-plateformes :** Le projet utilise une cible native unifiée `PVECenter` qui compile pour **iPhone/iPad (`iphoneos` / `iphonesimulator`)**, **Mac (`macosx`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`)** et **Apple TV (`appletvos` / `appletvsimulator`)** avec le même Bundle ID `io.ac.pvepanel.app`. Si vous préférez créer des schémas ou cibles séparés dans Xcode (`PVECenter-iOS`, `PVECenter-macOS`, `PVECenter-tvOS`), conservez `io.ac.pvepanel.app` pour que l’appairage `pvecenter://` et APNs restent alignés avec `config/config.yaml`.

### Stack technique Apple native

- **Swift 6 strict concurrency & SwiftUI** : `NavigationSplitView` + `MenuBarExtra` sur Mac (`⌘R`, `⌘L`, `⌘1`–`⌘6`, `⌘,`), `TabView` + `.sensoryFeedback` sur iPhone/iPad, 10-foot UI focus engine sur Apple TV (`tvOS 27.0`), thème **Système / Clair / Sombre** adaptatif.
- **Persistance locale sécurisée** : **SwiftData** (`ServerProfileEntity`, `CachedIncidentEntity`, `CachedCustomServiceEntity`) + **Keychain** (`KeychainStore` via `kSecClassGenericPassword`, sans jamais stocker les Bearer tokens en clair dans `UserDefaults`).
- **Découverte & Appairage chiffré** :
  - **Bonjour / mDNS natif** (`BonjourDiscoveryService` via `Network.framework` `NWBrowser` / `NWConnection`) pour `_pvecenter._tcp` et scan LAN (`_http._tcp`, `_ssh._tcp`, `_smb._tcp`).
  - **Appairage Apple TV par code PIN à 6 chiffres** (`PairingCryptoService`) : échange de clés éphémères **CryptoKit P-256 ECDH** -> dérivation **HKDF-SHA256** liée au PIN -> chiffrement **AES-256-GCM** via Bonjour (`_pvepair._tcp`) ou le relais HTTPS `/api/pairing/sessions/*`.
- **Temps réel & Graphiques** : `RealtimeEventsClient` (`URLSessionWebSocketTask` sur `/api/ws/events` + bascule automatique SSE `/api/events/stream`) et **Swift Charts** (`BarMark` & `SectorMark`).

---

## 2. Permissions & `Info.plist` (`ios-native/PVECenter/Resources/Info.plist`)

Toutes les clés requises par iOS, macOS et tvOS sont déjà configurées dans [`ios-native/PVECenter/Resources/Info.plist`](ios-native/PVECenter/Resources/Info.plist) :

| Clé `Info.plist` | Rôle | Détails configurés |
|---|---|---|
| `NSLocalNetworkUsageDescription` | Découverte LAN Bonjour & appairage Apple TV | Obligatoire depuis iOS 14+ / tvOS 14+ pour autoriser `NWBrowser` et `NWListener`. |
| `NSBonjourServices` | Types mDNS déclarés auprès d’iOS/tvOS | `_pvecenter._tcp`, `_pvepair._tcp`, `_http._tcp`, `_ssh._tcp`, `_smb._tcp` |
| `NSCameraUsageDescription` | Scanner de QR Code `pvecenter://` | Utilisé par `QRScannerView` (`AVCaptureSession` sous `#if os(iOS)`). macOS et tvOS basculent proprement vers la saisie/collage et Bonjour/PIN. |
| `CFBundleURLTypes` | Deep-linking d’appairage serveur | Schéma `pvecenter` (`pvecenter://connect?url=...&name=...&id=...`). |
| `NSAppTransportSecurity` | Connexions homelab locales & Tailscale | `NSAllowsArbitraryLoads = true`, `NSAllowsLocalNetworking = true` pour joindre les IP LAN HTTP, certificats auto-signés Proxmox ou `*.ts.net`. |
| `ITSAppUsesNonExemptEncryption` | Déclaration export App Store Connect | `false` (TLS Apple standard et échange éphémère exemptés). |

---

## 3. Notifications Push (APNs) : Compte Apple gratuit vs Apple Developer Program

### Pourquoi `aps-environment` n’est PAS forcé dans `project.pbxproj`

Dans [`ios-native/PVECenter.xcodeproj/project.pbxproj`](ios-native/PVECenter.xcodeproj/project.pbxproj), aucun fichier `CODE_SIGN_ENTITLEMENTS` imposant `aps-environment` n’est forcé par défaut :

- **Avec un compte Apple personnel gratuit (Personal Team) :** Apple n’autorise pas la capability *Push Notifications* (`aps-environment`) sur les profils gratuits. Ne pas forcer cet entitlement permet à **n’importe quel développeur de compiler et installer l’application immédiatement** sur simulateur ou iPhone/iPad/Apple TV physique via Xcode (Signature Automatique) ou `./ios-native/deploy-device.sh`, sans erreur de provisioning !
- **Fonctionnement immédiat sans `.p8` ni `aps-environment` :**
  - Connexion temps réel **WebSocket / SSE** (`/api/ws/events` et `/api/events/stream`).
  - **Notifications locales interactives** via `UNUserNotificationCenter` sur iOS, iPadOS et macOS (catégorie `SERVICE_ALERT` avec actions rapides **`Mute 1h`** et **`Tester`**).
  - **Bannières d’alerte temps réel sur Apple TV (`tvOS 27.0`)** via la file `PushNotificationManager.activeTVBanner` (tvOS ne supporte pas les actions de notification système, l’affichage in-app reste actif en direct).
  - Webhooks serveur (**Discord**, **Telegram**, **ntfy / Gotify / Home Assistant**) 100 % fonctionnels sans compte Apple payant.

### Activer les notifications Push APNs en arrière-plan (Compte Apple Developer Program payant)

Lorsque vous disposez d’un compte Apple Developer Program (99 $/an) et souhaitez recevoir les notifications même lorsque l’app est fermée :

1. **Dans Xcode :**
   - Ouvrez `ios-native/PVECenter.xcodeproj` -> sélectionnez la cible **`PVECenter`** -> onglet **Signing & Capabilities**.
   - Sélectionnez votre **Team** et vérifiez le Bundle Identifier (`io.ac.pvepanel.app`).
   - Cliquez sur **`+ Capability`** et ajoutez **Push Notifications** *(et **Background Modes -> Remote notifications** pour iOS si souhaité)*. Xcode générera le `.entitlements` contenant `aps-environment`.
2. **Sur le portail Apple Developer :**
   - Allez dans *Certificates, Identifiers & Profiles -> Keys* -> cliquez sur **`+`**.
   - Donnez un nom (ex. `PVE Center APNs`), cochez **Apple Push Notifications service (APNs)** et générez la clé.
   - Téléchargez le fichier `AuthKey_<KEY_ID>.p8` *(téléchargeable une seule fois !)* et notez votre **Key ID** ainsi que votre **Team ID** (*Membership Details*).
3. **Sur votre serveur PVE Command Center :**
   - Copiez le fichier dans `./config/AuthKey.p8` (monté dans Docker à `/app/config/AuthKey.p8` et ignoré par `.gitignore`).
   - Configurez `notifications.apns` dans `config/config.yaml` (ou depuis l’interface Web / Apple *Notifications*) :
     ```yaml
     notifications:
       apns:
         enabled: true
         team_id: "ABCDE12345"
         key_id: "XYZ1234567"
         bundle_id: "io.ac.pvepanel.app"
         private_key_path: "/app/config/AuthKey.p8"
         use_sandbox: false   # true pour Xcode Debug, false pour TestFlight / App Store
     ```
4. **Tester :** ouvrez l’app sur votre appareil (acceptez l’autorisation de notifications pour enregistrer le token via `POST /api/notifications/devices`), puis lancez un test depuis **Notifications -> Tester** (`POST /api/notifications/test`).

---

## 4. Mode Démo natif (`DemoDataStore`) & App Store Review (Guideline 2.1)

L’équipe de révision Apple ne pouvant pas accéder à votre réseau local ou Tailnet privé, l’application embarque `actor DemoDataStore` en mémoire :

- Au premier lancement sans serveur configuré, l’assistant d’onboarding s’ouvre et propose l’option **« Explorer en Mode Démo »** (également accessible à tout moment via *Serveurs & Connexion*).
- Toutes les vues sont interactives en mémoire : nœud & VMs/LXC Proxmox, stockage & SMART, graphiques Swift Charts, services personnalisés (`http_rest`, `tcp_port`, `icmp_ping`, `json_metrics`, `webhook_ingest`), timeline d’incidents (`Acquitter`, `Mute 1h`), webhooks de notifications, éditeur YAML, scan LAN et appairage Apple TV.

### Notes prêtes pour App Store Connect (`App Review Information`)

> **Demo Mode (No private VPN or homelab required):**
> PVE Center is a native SwiftUI client for self-hosted Proxmox VE & homelab servers (reachable via local Bonjour mDNS or Tailscale Serve). Because private homelab servers are unreachable from outside the owner's LAN/Tailnet, we provide a complete in-memory interactive Demo Mode:
> 1. Launch the app. On the onboarding screen, tap **"Explorer en Mode Démo"** (or open **"Serveur & Connexion"** and tap **"Activer le Mode Démo"**).
> 2. Explore all tabs (Accueil, Proxmox LXC/VM, Stockage & Swift Charts, Services & Custom Connectors, Activité & Incidents, Comptes) and Settings (YAML Editor, Notifications, Apple TV PIN Pairing).
> 3. Trigger live interactive actions (start/stop VM, test custom services, acknowledge or mute incidents).

---

## 5. Scripts de build, déploiement local, CI & Sideloading

### Scripts fournis dans `ios-native/`

| Script | Usage | Description |
|---|---|---|
| `./ios-native/run-iphone-sim.sh [UDID]` | Simulateur iOS | Démarre un simulateur iPhone (ferme les simulateurs Apple TV actifs pour éviter les conflits), compile en Debug `iphonesimulator`, installe et lance `io.ac.pvepanel.app`. |
| `./ios-native/run-appletv-sim.sh [UDID]` | Simulateur tvOS | Démarre un simulateur Apple TV 4K, compile en Debug `appletvsimulator`, installe et lance `io.ac.pvepanel.app`. |
| `./ios-native/install-mac.sh` | Mac natif (Xcode) | Compile la cible `PVECenter` pour `macosx` (Release, signature ad-hoc `-`) et installe `/Applications/PVE Center.app`. |
| `./ios-native/build-macos-app.sh` | Mac natif (SwiftPM) | Compile via `swift build -c release`, génère `AppIcon.icns`, signe `ios-native/build/PVE Center.app` (Bundle ID `io.github.pvepanel.app` dans ce script SwiftPM) et installe dans `/Applications` ou `~/Applications`. |
| `./ios-native/deploy-device.sh` | Appareil physique | Déploie en Release via `xcrun devicectl` sur iPhone, iPad ou Apple TV physique (`--list`, `-t <TEAM_ID>`, `-p ios\|tvos`, `-d <UDID>`). |

Exemples rapides :
```bash
# Lister les appareils physiques connectés (USB ou Wi-Fi jumelé)
./ios-native/deploy-device.sh --list

# Déployer sur iPhone/iPad physique
./ios-native/deploy-device.sh -t <VOTRE_TEAM_ID> -p ios

# Déployer sur Apple TV physique
./ios-native/deploy-device.sh -t <VOTRE_TEAM_ID> -p tvos -d <UDID_APPLE_TV>

# Vérifier la compilation Swift 6 & tvOS sans signature
cd ios-native && swift build
xcodebuild -project ios-native/PVECenter.xcodeproj -scheme PVECenter -destination 'generic/platform=tvOS' -derivedDataPath /tmp/pve-tvos-ci CODE_SIGNING_ALLOWED=NO build
```

### TestFlight & App Store Connect (Local ou GitHub Actions)

- **Via Xcode :** ouvrez `ios-native/PVECenter.xcodeproj`, choisissez la destination (`Any iOS Device (arm64)`, `Any Mac` ou `Any tvOS Device`), puis **Product -> Archive -> Distribute App -> TestFlight & App Store**.
- **Via GitHub Actions :** le workflow [`.github/workflows/ios-appstore.yml`](.github/workflows/ios-appstore.yml) sur `macos-15` :
  1. **`swift-verify`** : exécute `./build-macos-app.sh` et vérifie le build `generic/platform=tvOS` (`CODE_SIGNING_ALLOWED=NO`), puis publie `pve-center-macos-app`.
  2. **`build-ios`** : archive `ios-native/PVECenter.xcodeproj` (ou Capacitor si `project_mode=capacitor`), signe et exporte le `.ipa` si les secrets (`APPLE_CERTIFICATE_BASE64`, `APPLE_P12_PASSWORD`, `APPLE_PROVISIONING_PROFILE_BASE64`, `APPLE_PROVISIONING_PROFILE_NAME`, `APPLE_TEAM_ID`) sont configurés, et envoie vers TestFlight si `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID` et `APPSTORE_PRIVATE_KEY` sont renseignés. Sans secrets Apple, il génère une archive de vérification non signée.

### Sideloading sans compte payant (AltStore / SideStore / Sideloadly)

Si vous ne disposez pas d’un compte Apple Developer Program payant et souhaitez installer l’app sur votre iPhone/iPad pour un usage personnel :

1. **Via Xcode + `./ios-native/deploy-device.sh`** *(méthode la plus directe depuis Mac)* : activez le **Mode développeur** sur iPhone (*Réglages -> Confidentialité et sécurité -> Mode développeur*), connectez votre compte Apple gratuit dans Xcode (*Settings -> Accounts*), puis exécutez `./ios-native/deploy-device.sh -p ios`.
2. **Via AltStore / SideStore / Sideloadly (`.ipa`)** :
   - Générez une archive sans signature puis empaquetez `Payload/PVE Center.app` en `.ipa` :
     ```bash
     xcodebuild -project ios-native/PVECenter.xcodeproj -scheme PVECenter -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/PVECenter.xcarchive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" clean archive
     mkdir -p /tmp/Payload && cp -R "/tmp/PVECenter.xcarchive/Products/Applications/PVE Center.app" /tmp/Payload/
     (cd /tmp && zip -r PVECenter-unsigned.ipa Payload)
     ```
   - Importez `/tmp/PVECenter-unsigned.ipa` dans **AltStore**, **SideStore** *(renouvellement automatique en Wi-Fi sans PC/Mac après installation initiale !)* ou **Sideloadly**.
   - **Limitations connues des comptes gratuits (7 jours) :**
     * La signature expire tous les **7 jours** (SideStore / AltServer automatise le rafraîchissement en arrière-plan).
     * **APNs distant désactivé** par Apple sur les certificats gratuits (`aps-environment` absent) : conservez Discord / Telegram / ntfy et les alertes WebSocket/SSE temps réel.
     * Si AltStore/SideStore réécrit le Bundle Identifier avec un suffixe d’équipe personnelle, Bonjour (`_pvecenter._tcp`), le scan QR (`pvecenter://`), le Keychain et l’appairage Apple TV par PIN continuent de fonctionner normalement.

### Alternative zéro-certificat : PWA Safari

Ouvrez `https://<hostname>.<tailnet>.ts.net` dans **Safari** sur iPhone/iPad -> **Partager** -> **Sur l’écran d’accueil**.

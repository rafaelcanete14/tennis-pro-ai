# Installing Tennis Pro AI on Your iPhone 16 Pro Max via GitHub (From Windows)

Because iOS apps must be compiled with Apple's Xcode SDK on macOS, this repository includes an automated **GitHub Actions cloud macOS build pipeline** ([`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml)) that compiles **Tennis Pro AI** on GitHub's servers and produces a downloadable `.ipa` package for your **iPhone 16 Pro Max**—no Mac required.

---

## Step 1: Push This Project to Your GitHub Account

1. Go to https://github.com/new and create a new repository (for example, `tennis-pro-ai`). Leave **"Initialize this repository with a README"** unchecked.
2. Open **PowerShell** inside `d:\Antigravity Projects\Rj's Tennis Cut` and run (replacing `<YOUR-GITHUB-USERNAME>` with your username):
   ```powershell
   git remote add origin https://github.com/<YOUR-GITHUB-USERNAME>/tennis-pro-ai.git
   git push -u origin main
   ```

---

## Step 2: Download the Built `.ipa` from GitHub Actions

1. Open your repository on GitHub and click the **Actions** tab at the top.
2. You will see the workflow **"Build iOS IPA (iPhone 16 Pro Max)"** running automatically (takes ~3–5 minutes on GitHub's `macos-15` runner).
3. Once it turns green, click the completed workflow run and scroll down to **Artifacts**.
4. Click **`TennisProAI-Unsigned-IPA`** to download the `.zip` file, then extract **`TennisProAI-Unsigned.ipa`** on your Windows PC.

---

## Step 3: Install onto Your iPhone 16 Pro Max from Windows

Choose **Option A** (Free Apple ID via Sideloadly/AltStore on Windows) or **Option B** (Paid Apple Developer Account via TestFlight):

### Option A: Free Apple ID on Windows (Recommended — $0 Cost, No Mac Needed)

1. **Install Official Apple Drivers on Windows:**
   - Install **iTunes for Windows** and **iCloud for Windows** directly from Apple's website (the standalone installers, not the Microsoft Store versions) so Windows has Apple Mobile Device USB drivers.
2. **Install Sideloadly on Windows:**
   - Download and install **Sideloadly** from https://sideloadly.io (or use **AltStore** from https://altstore.io).
3. **Connect Your iPhone 16 Pro Max:**
   - Plug your iPhone 16 Pro Max into your Windows PC via USB-C and tap **Trust This Computer** on your iPhone screen.
4. **Sign & Install the `.ipa`:**
   - Open **Sideloadly**, verify your iPhone 16 Pro Max is selected under **iDevice**, and enter your **Apple ID email**.
   - Drag **`TennisProAI-Unsigned.ipa`** into Sideloadly and click **Start** (enter your Apple ID password + 2FA code if prompted; Sideloadly sends this directly to Apple's developer provisioning server to sign the app for your device).
5. **Trust Your Developer Profile & Enable Developer Mode on iPhone 16 Pro Max (iOS 18+):**
   - On your iPhone, open **Settings > General > VPN & Device Management**, tap your **Apple ID** under *Developer App*, and tap **Trust**.
   - Open **Settings > Privacy & Security > Developer Mode**, toggle **Developer Mode** ON, restart your iPhone when prompted, and confirm enabling Developer Mode after reboot.
6. Launch **Tennis Pro AI** on your iPhone 16 Pro Max!
   - *Note:* Apps signed with a free Apple ID remain valid for **7 days**; simply re-sideload or enable Sideloadly's Wi-Fi auto-refresh to renew without losing data.

---

### Option B: If You Have Access to a Mac (Direct Xcode Install)

If you ever open the GitHub repository on a Mac with Xcode 16+:
1. Run `git clone https://github.com/<YOUR-GITHUB-USERNAME>/tennis-pro-ai.git`
2. Open `TennisProAI.xcodeproj` in Xcode.
3. Under **Signing & Capabilities**, pick your **Apple ID Personal Team** and change the Bundle Identifier to a unique string (e.g., `com.yourname.tennisproai`).
4. Connect your **iPhone 16 Pro Max**, select it as the run destination, and press **`Cmd + R`**.

# Getting Started — running & testing the app

A from-scratch, click-by-click guide for a Windows machine. No prior Flutter
experience assumed. You do **not** need the sensor hardware or Bluetooth for
any of this — the app ships with a built-in *simulated* sensor that generates
realistic fake swings, so everything below works on a bare laptop.

---

## The big picture (read this first)

"Testing the app" means three different things, from easiest to most involved:

1. **Run the automated tests** — one command, needs only Flutter installed.
   No phone, no emulator. Confirms all the swing math, the Bluetooth
   protocol, and the storage work. This is your fast "is it healthy?" check.
2. **Run the app on a screen** — needs either an Android phone or an Android
   emulator. This is where you actually tap around and watch fake swings
   stream in.
3. **Run it with the real sensor** — later, once the parts arrive. Nothing to
   do now.

You'll install two things: **Flutter** (the toolkit that builds the app) and
**Android Studio** (which provides the Android SDK, an emulator, and phone
tools). Budget ~30–45 min for the one-time installs, mostly download waiting.

> Note on Windows: you can build the **Android** version but not the iOS
> version — iOS needs a Mac. That's fine; Android is all you need.

---

## Part 1 — Install Flutter

1. Open <https://docs.flutter.dev/get-started/install/windows> in a browser.
   This is the official page; if any detail below differs, trust the page.
2. Download the **Flutter SDK** (a large `.zip`).
3. Extract it to a simple path with **no spaces** and **not** inside
   `C:\Program Files` (permissions get in the way there). A good home is
   `C:\src`. After extracting you should have the folder:

   ```
   C:\src\flutter
   ```

   (so that `C:\src\flutter\bin` exists).
4. Add Flutter to your PATH so the terminal can find it:
   - Press **Start**, type `env`, open **"Edit the system environment
     variables."**
   - Click **Environment Variables…**
   - Under **User variables**, click **Path** → **Edit** → **New**, and paste:

     ```
     C:\src\flutter\bin
     ```
   - Click **OK** on all three dialogs to save.
5. **Close every open terminal window** and open a fresh **PowerShell**
   (Start → type `PowerShell` → Enter). PATH changes only apply to new
   windows.
6. Confirm it works:

   ```powershell
   flutter --version
   ```

   You should see a version line (e.g. `Flutter 3.x.x`). If it says the
   command isn't recognized, re-check step 4 and reopen the terminal.

---

## Part 2 — Install Android Studio (gives you the Android SDK + emulator)

You need this even if you plan to run on a real phone — it's what provides the
Android build tools.

1. Download from <https://developer.android.com/studio> and install with the
   default options.
2. Launch it once. A setup wizard runs — **let it download** the Android SDK,
   platform-tools, and an emulator image (click through, accepting defaults).
3. When you reach the welcome screen, click **More Actions → SDK Manager**:
   - On the **SDK Tools** tab, tick **"Android SDK Command-line Tools
     (latest)"** and click Apply to install it. (Flutter needs this.)
4. Accept the Android licenses. Back in PowerShell:

   ```powershell
   flutter doctor --android-licenses
   ```

   Press `y` and Enter for each prompt until it's done.

---

## Part 3 — Check your setup

```powershell
flutter doctor
```

This prints a checklist. You want green checkmarks on **"Flutter"** and
**"Android toolchain."** It's fine if **Chrome**, **Visual Studio**, or
**Xcode** show warnings — you're not using those. If Android shows a problem,
`flutter doctor` usually prints the exact command to fix it.

---

## Part 4 — One-time project setup

Point the terminal at the project folder:

```powershell
cd C:\GitProjects\GitHub\GolfSwingTrackerApp
```

Then run these three commands in order.

1. Generate the Android/iOS project files. These live in `android/` and
   `ios/` folders that aren't in the repo yet. The `.` means "here." This
   does **not** touch the app code — it only fills in the missing platform
   scaffolding.

   ```powershell
   flutter create . --platforms=android,ios --org com.jonwes --project-name golf_tracker_app
   ```

2. Apply the Bluetooth permissions and remove the throwaway template test.
   You'll see a few `DONE` lines. (Safe to run again anytime.)

   ```powershell
   dart run tool/setup_platforms.dart
   ```

3. Download the packages the app depends on:

   ```powershell
   flutter pub get
   ```

---

## Part 5 — Level 1: run the tests (no phone needed)

```powershell
flutter test
```

The first run takes a minute or two while it compiles. You're looking for:

```
All tests passed!
```

That's 43 tests covering the swing-speed/face-angle/path math, the Bluetooth
packet codec and link behavior (chunk reassembly, reconnect), and the
save-to-disk storage. If this passes, the guts of the app are healthy — and
you did it without any phone or emulator.

---

## Part 6 — Level 2: run the app on a screen

You need something to run it *on*. Pick **one** of the options below.

> Run it on **Android** (phone or emulator). Don't use "Chrome" or "Windows"
> as the target for now — the on-device database isn't wired up for those yet,
> and the app would crash at startup. (If you'd rather run on your Windows
> desktop to skip the emulator, that's doable with a small change — just ask.)

### Option A — Your own Android phone (recommended)

Closest to real-world use, and you'll need a phone eventually for the sensor.

1. On the phone: **Settings → About phone**, tap **"Build number" seven
   times** until it says you're a developer.
2. **Settings → System → Developer options**, turn on **"USB debugging."**
3. Plug the phone into the PC with a USB cable. On the phone, tap **"Allow"**
   / "Trust this computer" when prompted.
4. Confirm the PC sees it:

   ```powershell
   flutter devices
   ```

   Your phone should be listed.
5. Launch the app:

   ```powershell
   flutter run
   ```

   The first build takes several minutes (it downloads Android build pieces
   once). After that it's quick. The app opens on your phone.

### Option B — Android emulator (no physical phone)

1. In Android Studio: **More Actions → Virtual Device Manager → Create
   Device**. Pick e.g. **Pixel 7**, choose a system image (download one if
   asked), click **Finish**.
2. Press the ▶ **play** button next to your new virtual device and wait for
   the fake phone's home screen to appear.
3. In PowerShell:

   ```powershell
   flutter run
   ```

   It uses the running emulator. (The emulator can't do real Bluetooth, but
   the simulated sensor doesn't need it.)

---

## Part 7 — Playing with the app once it's open

You'll see **"Golf Swing Tracker"** with one card, **"Sensor 1 (simulated)."**
It auto-connects and arms itself — no buttons needed.

- Tap the **"Auto swings"** chip on the sensor card. It starts firing a random
  swing every ~6 seconds. Watch the big **speed / face-angle** card, the
  **swing-path** graph, and the **history** list all update live.
- Or tap **"Simulate swing"** for a single swing on demand.
- The **⚡ card** flashes the instant the "impact" is detected — the same
  sub-half-second number the AR glasses will show — then resolves into the
  full swing a moment later.
- Tap **＋** (top right) to add another simulated sensor. Rename it (a player
  or a club), give it its own club profile — swings get tagged per sensor and
  the history screen filters by device.
- Tap the **clock icon** for session history; the **golf-course icon** to edit
  club profiles (shaft lengths).
- **Close the app fully and reopen it** — your sensors, their names, and your
  swing history are all still there. That's the persistence layer working.
- **"Scan for GolfTracker sensor"** (under ＋) is for the real hardware later.
  With no sensor powered on, it just scans and finds nothing — expected.

While `flutter run` is active, these keys work in the terminal: **`r`** =
hot reload after a code change, **`R`** = full restart, **`q`** = quit.

---

## Troubleshooting

- **`flutter` not recognized** — PATH isn't set, or you didn't open a *new*
  terminal. Reopen PowerShell; confirm `C:\src\flutter\bin` is in your Path.
- **Android licenses not accepted** — run
  `flutter doctor --android-licenses` and press `y` through all prompts.
- **App crashes at launch complaining about `databaseFactory`** — you ran it
  on Chrome or Windows. Run it on Android (phone or emulator) instead.
- **Phone doesn't show in `flutter devices`** — use a data-capable USB cable
  (not charge-only), make sure USB debugging is on, and that you tapped
  "Allow" on the phone. `adb devices` should list it too.
- **First Android build is very slow** — normal; it downloads Gradle/Android
  dependencies once, then caches them.

---

## Housekeeping

There's a leftover `_to_delete/` folder in the project (it held a stray git
lock file). You can delete that folder — nothing depends on it.

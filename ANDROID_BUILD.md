# Readest — Build & Run Android (Windows)

> Panduan build APK Android dan menjalankannya di emulator, berdasarkan setup nyata di mesin Windows ini.
> Tanggal: 2026-06-23

---

## Daftar Isi

1. [Prasyarat](#1-prasyarat)
2. [Environment Variables](#2-environment-variables)
3. [Build APK Release](#3-build-apk-release)
4. [Menjalankan di Emulator](#4-menjalankan-di-emulator)
5. [Install ke Emulator / Device](#5-install-ke-emulator--device)
6. [Masalah yang Sudah Diperbaiki](#6-masalah-yang-sudah-diperbaiki)
7. [Catatan Arsitektur (ABI)](#7-catatan-arsitektur-abi)
8. [Troubleshooting Cepat](#8-troubleshooting-cepat)

---

## 1. Prasyarat

| Komponen | Keterangan |
|---|---|
| Node + pnpm | Package manager project (`pnpm install` di root) |
| Rust + targets | `rustup target add aarch64-linux-android x86_64-linux-android` |
| Android SDK | `C:\Users\Mocha\AppData\Local\Android\Sdk` |
| Android NDK | `...\Sdk\ndk\29.0.13846066` |
| Platform Tools | `adb` (`...\Sdk\platform-tools`) |
| Emulator + System Image | `emulator` + `system-images;android-34;google_apis;x86_64` |
| MSVC C++ Build Tools | VS Build Tools 2022 + workload **VCTools** (untuk `link.exe`) |
| Windows Developer Mode | **ON** — wajib agar Tauri bisa membuat symlink `.so` ke `jniLibs` |

> **PENTING:** Jalankan perintah build dari **PowerShell**, bukan Git Bash.
> Di Bash, coreutils `link` membayangi MSVC `link.exe` dan build-script host gagal.

---

## 2. Environment Variables

Set sekali (persisten via System env) atau per-sesi di PowerShell:

```powershell
$env:ANDROID_HOME = "C:\Users\Mocha\AppData\Local\Android\Sdk"
$env:NDK_HOME     = (Get-ChildItem "$env:ANDROID_HOME\ndk" -Directory | Select-Object -First 1).FullName
```

---

## 3. Build APK Release

Dari folder `apps/readest-app`:

```powershell
cd D:\Document\Project\readest\apps\readest-app
pnpm tauri android build -t aarch64
```

Output:

```
src-tauri\gen\android\app\build\outputs\apk\universal\release\app-universal-release-unsigned.apk   (~64 MB)
src-tauri\gen\android\app\build\outputs\bundle\universalRelease\app-universal-release.aab
```

> APK ini **unsigned** → tidak bisa langsung `adb install`. Untuk APK release yang
> installable (`app-universal-release.apk`) perlu keystore + `keystore.properties`.
> Untuk sekadar testing di emulator, gunakan **`tauri android dev`** (lihat bawah)
> yang otomatis menandatangani dengan debug key.

---

## 4. Menjalankan di Emulator

### Setup sekali (download ~1.5 GB)

```powershell
$sdk = "$env:ANDROID_HOME\cmdline-tools\latest\bin"

# Install emulator + system image x86_64 (Android 14)
& "$sdk\sdkmanager.bat" "emulator" "platform-tools" "system-images;android-34;google_apis;x86_64"

# Buat AVD
& "$sdk\avdmanager.bat" create avd -n readest_test -k "system-images;android-34;google_apis;x86_64" -d pixel_7
```

### Setiap kali mau jalan

```powershell
# Boot emulator (membuka jendela di desktop)
Start-Process "$env:ANDROID_HOME\emulator\emulator.exe" -ArgumentList "-avd","readest_test","-gpu","auto"

# Tunggu sampai boot selesai
adb wait-for-device
adb shell getprop sys.boot_completed   # harus "1"
adb devices                            # harus muncul: emulator-5554  device
```

---

## 5. Install ke Emulator / Device

### Cara A — `tauri android dev` (direkomendasikan untuk testing)

Build lib sesuai ABI emulator, **install + launch otomatis**, dengan hot-reload:

```powershell
cd D:\Document\Project\readest\apps\readest-app
pnpm tauri android dev
```

Tidak perlu `adb install` manual — Tauri yang melakukannya. Biarkan proses ini
tetap jalan selama development (Ctrl+C untuk berhenti).

### Cara B — `adb install` manual (untuk APK yang sudah ditandatangani)

```powershell
adb install -r path\ke\app-universal-release.apk
```

> Catatan: hanya berlaku untuk APK **signed**. APK `-unsigned` dari build release
> akan ditolak oleh Android.

### Script bawaan project

`package.json` punya `dev-android` yang build + install:

```
tauri android build -t aarch64 -- --features devtools
  && adb install -r src-tauri/gen/android/app/build/outputs/apk/universal/release/app-universal-release.apk
```

Script ini butuh APK **signed** di path tersebut (perlu setup keystore dulu).

---

## 6. Masalah yang Sudah Diperbaiki

Hambatan nyata yang ditemui saat setup pertama di mesin ini + solusinya:

| Masalah | Penyebab | Solusi |
|---|---|---|
| `Could not determine SDK root` | Struktur `cmdline-tools` salah | Pindah ke `cmdline-tools\latest\...` |
| Host build-script gagal (`link: extra operand`) | coreutils `link` membayangi MSVC `link.exe` di Bash | Jalankan dari **PowerShell** |
| `link.exe` tidak ada | VS Build Tools tanpa workload C++ | Install workload `Microsoft.VisualStudio.Workload.VCTools` |
| `ld.lld: unable to find library -ladvapi32` (target Android) | `turso_ext/build.rs` pakai `cfg!(target_os="windows")` (host, bukan target) | Patch `build.rs` pakai `env CARGO_CFG_TARGET_OS`, lalu `cargo clean -p turso_ext` |
| `Failed to create a symbolic link ... libreadestlib.so` | Windows Developer Mode OFF | Aktifkan Developer Mode (registry `AllowDevelopmentWithoutDevLicense=1`) |
| `gradlew not found` | Gradle wrapper belum ter-generate di `gen/android` | `pnpm tauri android init` (regenerate wrapper; file `app/` yang ke-track git aman) |
| `AAPT: resource color/ic_launcher_background not found` | `ic_launcher.xml` mereferensikan `@color/...` padahal resource-nya `@drawable/...` | Ubah jadi `@drawable/ic_launcher_background` |
| `IllegalArgumentException: this and base files have different roots: C:\... and D:\...` (Kotlin daemon) | Source plugin Tauri ada di cargo registry **drive C:**, project di **drive D:**; Kotlin incremental relativize antar-drive gagal | Transient — biasanya lolos saat rebuild (hot-reload `tauri android dev`). Fix durable: taruh `CARGO_HOME` di drive yang sama dengan project, atau set `kotlin.incremental=false` di `gradle.properties` |

> ⚠️ **Patch turso_ext rapuh:** perbaikan `build.rs` dilakukan langsung di cache crate
> (`~/.cargo/registry/...`). Akan hilang jika crate di-download ulang / `cargo clean` global.
> Solusi durable: tambahkan `[patch.crates-io]` untuk `turso_ext` di `Cargo.toml` root.

---

## 7. Catatan Arsitektur (ABI)

- Mesin host ini **x86_64**. Emulator tercepat memakai **system image x86_64** (akselerasi hardware).
- APK release yang dibuild di atas hanya berisi **`lib/arm64-v8a`** (karena `-t aarch64`).
  → **Tidak akan jalan** di emulator x86_64.
- `tauri android dev` mendeteksi ABI emulator yang aktif dan build lib yang cocok
  (di sini: `x86_64-linux-android`), jadi tidak perlu rebuild manual.
- Kalau ingin uji APK arm64 persis seperti release, pakai emulator dengan
  **system image arm64-v8a** — tapi emulasi ARM di host x86 jauh lebih lambat.

---

## 8. Troubleshooting Cepat

```powershell
# Emulator tidak terdeteksi
adb kill-server; adb start-server; adb devices

# Lihat AVD yang ada
& "$env:ANDROID_HOME\emulator\emulator.exe" -list-avds

# Log app saat crash (filter tag Tauri / Rust)
adb logcat | Select-String "readest|RustStdoutStderr|tauri"

# Uninstall app dari emulator
adb uninstall com.bilingify.readest
```

| Gejala | Cek |
|---|---|
| Build error `-ladvapi32` lagi | Patch `turso_ext/build.rs` hilang → re-apply / pasang `[patch.crates-io]` |
| Error symlink `.so` | Developer Mode OFF → aktifkan lagi |
| `link.exe` not found | Jalankan dari PowerShell; pastikan VCTools terpasang |
| App install tapi blank/crash | ABI mismatch → pakai `tauri android dev`, bukan APK arm64 di emulator x86 |

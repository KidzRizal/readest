# Readest — Dokumentasi Project

> Dianalisis menggunakan grepai (semantic search) + analisis manual kode.
> Versi app: 0.11.1 | Tanggal: 2026-05-24

---

## Daftar Isi

1. [Gambaran Umum](#1-gambaran-umum)
2. [Tech Stack](#2-tech-stack)
3. [Struktur Monorepo](#3-struktur-monorepo)
4. [Arsitektur Sistem](#4-arsitektur-sistem)
5. [Frontend Architecture](#5-frontend-architecture)
6. [Backend (API Routes)](#6-backend-api-routes)
7. [Native Shell (Tauri / Rust)](#7-native-shell-tauri--rust)
8. [Fitur-Fitur Utama](#8-fitur-fitur-utama)
9. [State Management](#9-state-management)
10. [Platform Abstraction](#10-platform-abstraction)
11. [Database Layer](#11-database-layer)
12. [Sync System](#12-sync-system)
13. [Konfigurasi Environment](#13-konfigurasi-environment)
14. [Build & Deploy](#14-build--deploy)
15. [Testing](#15-testing)
16. [Internasionalisasi (i18n)](#16-internasionalisasi-i18n)
17. [Subscription & Billing](#17-subscription--billing)

---

## 1. Gambaran Umum

**Readest** adalah aplikasi pembaca ebook open-source yang dirancang untuk pengalaman membaca yang imersif dan mendalam. Dibangun sebagai rewrite modern dari [Foliate](https://github.com/johnfactotum/foliate), menggunakan **Next.js 16** dan **Tauri v2** untuk menghadirkan pengalaman cross-platform yang mulus.

### Platform yang Didukung
| Platform | Target |
|---|---|
| macOS / Windows / Linux | Tauri v2 desktop |
| Android / iOS | Tauri v2 mobile |
| Web | Next.js + Cloudflare Workers |
| Browser Extension | "Send to Readest" Chrome/Firefox extension |
| Windows Shell | Windows thumbnail provider extension |

### Lisensi
GNU Affero General Public License v3 (AGPL-3.0)

---

## 2. Tech Stack

### Frontend
| Teknologi | Versi | Kegunaan |
|---|---|---|
| Next.js | 16.2.6 | Framework React utama (App Router + Pages Router) |
| React | 19.2.5 | UI library |
| TypeScript | ^5.7.2 | Bahasa utama |
| Tailwind CSS | ^3.4.18 | Styling |
| daisyUI | ^4.12.24 | Komponen UI |
| Radix UI | berbagai | Komponen primitif aksesibel |
| Zustand | 5.0.10 | State management |
| Lucide React | ^0.562.0 | Icon library |

### Backend & Cloud
| Teknologi | Kegunaan |
|---|---|
| Supabase | Auth + PostgreSQL database |
| Cloudflare Workers | Deployment web via OpenNext |
| AWS S3 / Cloudflare R2 | Object storage untuk file buku |
| Stripe | Billing & subscription |
| Docker | Self-hosting |

### Native (Tauri)
| Teknologi | Kegunaan |
|---|---|
| Tauri v2 | Desktop & mobile shell |
| Rust | Native commands & plugins |
| libSQL / Turso | Embedded database (native) |

### AI & Layanan Eksternal
| Layanan | Kegunaan |
|---|---|
| OpenAI / Ollama | AI chat & embeddings |
| DeepL / Google / Azure / Yandex | Terjemahan |
| Microsoft Edge TTS | Text-to-speech |
| Hardcover | Reading progress sync |
| Readwise | Highlight export |
| OPDS / Calibre | Katalog buku online |

### Build Tools
| Tool | Kegunaan |
|---|---|
| pnpm 11.1.1 | Package manager (monorepo) |
| Biome | Linter + formatter |
| Vitest | Unit testing |
| Playwright | E2E testing web |
| WebdriverIO | E2E testing Tauri |
| Husky + lint-staged | Git hooks |

---

## 3. Struktur Monorepo

```
readest/
├── apps/
│   ├── readest-app/          # Aplikasi utama (Next.js + Tauri)
│   │   ├── src/              # Source code Next.js/React
│   │   ├── src-tauri/        # Native shell Rust (desktop + mobile)
│   │   ├── extensions/       # Browser extension & Windows thumbnail
│   │   ├── workers/          # Cloudflare Worker (send-email)
│   │   ├── e2e/              # End-to-end tests
│   │   ├── docs/             # Dokumentasi arsitektur
│   │   └── public/           # Static assets + vendor libs
│   └── readest.koplugin/     # Plugin KOReader (Lua)
├── packages/
│   ├── foliate-js/           # Fork engine buku (EPUB/PDF/dll)
│   ├── js-mdict/             # Parser MDict dictionary
│   ├── qcms/                 # Color management (WASM)
│   ├── simplecc-wasm/        # Konversi Chinese Traditional/Simplified
│   └── tauri/                # Tauri framework (submodule)
├── docker/                   # Docker compose untuk self-hosting
├── fastlane/                 # Mobile release automation
├── data/                     # Screenshots, icons, metadata
└── ops/                      # Nix flakes untuk dev environment
```

### Struktur `apps/readest-app/src/`

```
src/
├── app/                      # Next.js App Router (pages + API)
│   ├── api/                  # Server-side API endpoints (App Router)
│   ├── auth/                 # Halaman autentikasi
│   ├── library/              # Halaman library buku
│   ├── reader/               # Halaman reader (komponen terbesar)
│   ├── opds/                 # OPDS catalog browser
│   ├── send/                 # "Send to Readest" inbox
│   ├── user/                 # Akun, subscription, settings
│   ├── updater/              # App updater UI
│   ├── offline/              # Halaman offline
│   └── s/, o/                # Share landing pages
├── pages/                    # Next.js Pages Router
│   ├── api/                  # Legacy API endpoints (sync, storage, dll)
│   ├── reader/               # Reader entry point legacy
│   ├── _app.tsx              # App wrapper
│   └── _document.tsx         # Document shell (COOP/COEP headers)
├── components/               # Reusable UI components
├── context/                  # React context providers
├── hooks/                    # Custom React hooks
├── store/                    # Zustand stores
├── services/                 # Domain/service layer (shared)
├── libs/                     # Library code (crypto, TTS, dll)
├── helpers/                  # Helper utilities
├── utils/                    # Shared utilities
├── types/                    # TypeScript type definitions
├── styles/                   # CSS & theme assets
├── i18n/                     # i18n setup
├── data/                     # Static app data
└── workers/                  # Browser web workers
```

---

## 4. Arsitektur Sistem

Readest adalah **satu codebase TypeScript/React** yang dikompilasi ke beberapa target. Yang membedakan antar target adalah **host shell** dan **set services** yang di-bind saat runtime.

```
┌─────────────────────────────────────────────────────────┐
│                        CLIENTS                          │
│  Desktop (Tauri)  │  Mobile (Tauri)  │  Web (Next.js)  │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│              BACKEND (Next.js / Cloudflare Worker)      │
│   src/app/api/*  │  src/pages/api/*  │  workers/        │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│                   EXTERNAL SERVICES                     │
│  Supabase │ S3/R2 │ Stripe │ AI │ TTS │ Translators    │
└─────────────────────────────────────────────────────────┘
```

### Tiga Runtime

1. **Browser / Tauri WebView** — React UI, foliate-js engine, Turso WASM
2. **Tauri Native Host (Rust)** — file system, native dialogs, TTS, database
3. **Next.js Server / Cloudflare Worker** — API routes, auth, storage, billing

---

## 5. Frontend Architecture

### App Router vs Pages Router

| Concern | Router | Alasan |
|---|---|---|
| Library, reader, auth, OPDS, send, user | App Router | Standard untuk halaman baru |
| Reader entry `/reader/[ids]` | Pages Router | Historical entrypoint |
| COOP/COEP document shell | Pages Router | `_document.tsx` masih milik Pages Router |
| HTTP API endpoints | Keduanya | Mix App Router (baru) + Pages Router (legacy) |

### Reader — Komponen Terbesar

`app/reader` adalah cluster UI terbesar dengan ~80 komponen dan ~30 hooks:

- **BookView** — rendering buku via foliate-js
- **Sidebar** — TOC, bookmarks, search
- **Notebook** — panel catatan & anotasi
- **Annotator** — highlight, notes, bookmarks
- **FootnotePopup** — popup footnote
- **Translator** — overlay terjemahan
- **RSVP Overlay** — rapid serial visual presentation
- **AIChat** — AI chat panel
- **ParallelView** — split-screen dua buku

### In-Browser Book Engine

Parsing dan rendering buku **tidak** dibuat dari scratch. Reader menggunakan `packages/foliate-js` (fork dari Foliate JS engine):

- **EPUB / MOBI / KF8 / FB2 / CBZ / TXT** → foliate-js
- **PDF** → pdfjs-dist (di-copy ke `public/vendor/pdfjs`)
- **Chinese conversion** → simplecc-wasm (`public/vendor/simplecc`)
- **Chinese segmentation** → jieba-wasm (`public/vendor/jieba`)

### Service Worker & Offline

`src/sw.ts` adalah Serwist service worker untuk web build:
- Cache static assets
- Cache API responses (read-only data)
- Offline route di `/offline`

---

## 6. Backend (API Routes)

### Pages Router (`src/pages/api`) — Legacy/Sync/Storage

```
sync.ts                  → KOReader-compatible sync
kosync.ts                → KOSync legacy bridge
sync/replicas.ts         → Replica sync (encrypted blobs)
sync/replica-keys.ts     → Replica key bootstrap
storage/upload.ts        → Presigned upload ke S3/R2
storage/download.ts      → Presigned download
storage/list.ts          → List user objects
storage/delete.ts        → Delete object
storage/purge.ts         → Bulk wipe (account deletion)
storage/stats.ts         → Per-user usage/quotas
send/inbox.ts            → "Send to Readest" inbox
send/fetch-url.ts        → Server-side URL fetcher
deepl/translate.ts       → DeepL proxy (sembunyikan API key)
user/delete.ts           → Account deletion
```

### App Router (`src/app/api`) — Fitur Baru

```
ai/chat                  → Streaming AI chat (Vercel AI SDK)
ai/embed                 → Embeddings untuk in-book RAG
metadata/search          → Metadata lookup (Google Books / Open Library)
opds/proxy               → CORS-friendly OPDS proxy
tts/edge                 → Edge TTS streaming
hardcover/graphql        → Hardcover GraphQL relay
stripe/checkout          → Create checkout session
stripe/portal            → Billing portal redirect
stripe/plans             → Plan listing
stripe/check             → Subscription state check
stripe/webhook           → Stripe webhook handler
google/iap-verify        → Google Play IAP verification
apple/iap-verify         → App Store IAP verification
share/*                  → Share-link landing + read-only render
```

### Cloudflare Worker (`workers/send-email`)

Worker terpisah untuk fitur "Send to Readest by email":
1. Menerima email masuk
2. Normalisasi attachment
3. Drop item ke inbox user
4. In-app `Send` page mengambil via `/api/send/inbox`

### Runtime Config

`src/app/runtime-config.js/route.ts` — server route yang emit config sebagai JS:
```js
window.__READEST_RUNTIME_CONFIG = {
  supabaseUrl, supabaseAnonKey, apiBaseUrl,
  objectStorageType, storageFixedQuota, translationFixedQuota
}
```
Ini memungkinkan **satu Docker image** di-rebrand per deployment tanpa rebuild.

---

## 7. Native Shell (Tauri / Rust)

### Rust Commands (`src-tauri/src/`)

```
lib.rs              → Command registration, scope grants, deep links
main.rs             → Entrypoint
clip_url.rs         → Clipboard URL extraction
dir_scanner.rs      → Recursive directory scan (library import)
transfer_file.rs    → Chunked upload/download untuk file besar
discord_rpc.rs      → Discord Rich Presence (desktop only)
android/, macos/, windows/  → Per-platform glue
```

### Custom Tauri Plugins (`src-tauri/plugins/`)

| Plugin | Fungsi |
|---|---|
| `tauri-plugin-native-bridge` | Android bridges (directory picker, open URL) |
| `tauri-plugin-native-tts` | Native text-to-speech |
| `tauri-plugin-turso` | Embedded libSQL/Turso database |
| `tauri-plugin-webview-upgrade` | WebView update flow |

### Security Note

`allow_paths_in_scopes` di `lib.rs` adalah shim keamanan penting: hanya mengizinkan akses file ke path yang sudah di-grant oleh Tauri dialog plugin. Ini mencegah XSS dari konten buku mendapatkan akses ke home directory user.

---

## 8. Fitur-Fitur Utama

### Format Buku yang Didukung
EPUB, MOBI, KF8 (AZW3), FB2, CBZ, TXT, PDF

### Reading Features
- **Scroll / Page View** — switch antara mode scroll dan paginasi
- **Parallel Read** — baca dua buku sekaligus dalam split-screen
- **RSVP** — Rapid Serial Visual Presentation (speed reading)
- **Full-Text Search** — cari di seluruh isi buku
- **Reading Ruler** — penggaris baca untuk fokus
- **Paragraph Mode** — baca paragraf per paragraf

### Annotations
- Highlight dengan warna kustom
- Bookmarks
- Notes
- Instant mode untuk interaksi cepat
- Export ke MoonReader format

### Lookup & Reference
- **Dictionary** — StarDict, SLOB, MDict format
- **Wikipedia / Wiktionary** — lookup online
- **Footnote Popup** — popup footnote inline

### Translation
- DeepL (via server proxy)
- Google Translate
- Azure Translator
- Yandex Translate
- Terjemahan per kalimat hingga seluruh buku

### Text-to-Speech (TTS)
Tiga backend di balik satu interface:
- `WebSpeechClient` — browser Web Speech API
- `NativeTTSClient` — native TTS via Tauri
- `EdgeTTSClient` — Microsoft Edge TTS (streaming, 400+ suara)

### AI Features
- **AI Chat** — chat tentang buku yang sedang dibaca
- **In-book RAG** — embed chapter lokal, query embeddings
- **AI Summarization** (dalam pengembangan)
- **Proofread** — saran koreksi teks

### Sync
- **Replica Sync** — sync progress, anotasi, settings antar device (encrypted)
- **KOReader Sync** — kompatibel dengan KOSync protocol
- **Cloud Library** — sync file buku via S3/R2

### Library Management
- Grid view dengan cover buku
- Sort & filter
- OPDS / Calibre integration
- Import dari file, URL, email

### Accessibility
- Full keyboard navigation
- Screen reader support (VoiceOver, TalkBack, NVDA, Orca)
- Spatial navigation untuk TV/gamepad

---

## 9. State Management

Menggunakan **Zustand** dengan store terpisah per concern:

| Store | Tanggung Jawab |
|---|---|
| `libraryStore` | Books, folders, selection, sort |
| `bookDataStore` | Per-book data (TOC, annotations, locations) |
| `readerStore` | Active views, layout, ribbon state |
| `parallelViewStore` | Two-pane reading |
| `notebookStore` | Notebook side panel |
| `settingsStore` | User/app settings |
| `themeStore` | Light/dark/atmosphere |
| `sidebarStore` | Sidebar visibility/width |
| `trafficLightStore` | macOS traffic-light positioning |
| `appLockStore` | App PIN lock |
| `deviceStore` | Device profile |
| `transferStore` | In-flight uploads/downloads |
| `aiChatStore` | AI chat sessions |
| `proofreadStore` | Proofread side flow |
| `atmosphereStore` | Ambient overlay |
| `customDictionaryStore` | User-imported dictionaries |
| `customFontStore` | User-imported fonts |
| `customTextureStore` | User-imported textures |
| `customOPDSStore` | User-added OPDS catalogs |

---

## 10. Platform Abstraction

Abstraksi terpenting di codebase adalah `src/services/appService.ts`. Semua kode yang menyentuh "platform" (filesystem, dialog, shell, TTS, IAP, dll) melewati interface ini.

### Tiga Implementasi

```
AppService (interface)
├── nativeAppService.ts  → Tauri desktop + mobile
│   ├── @tauri-apps/api invoke()
│   └── Tauri plugins (fs, dialog, http, oauth, native-tts, turso)
├── webAppService.ts     → Browser / web build
│   ├── browser APIs (File, IndexedDB, fetch)
│   └── fetch() ke /api/*
└── nodeAppService.ts    → Node tooling, tests, CLI
    └── node:fs, node:path
```

`environment.ts` memilih implementasi berdasarkan `NEXT_PUBLIC_APP_PLATFORM` dan runtime detection. Caller cukup `useEnv().appService` tanpa tahu implementasi mana yang dipakai.

---

## 11. Database Layer

Pola yang sama dengan AppService:

| Implementasi | Target | Backend |
|---|---|---|
| `webDatabaseService` | Browser | Turso WASM (libSQL in-browser) |
| `nativeDatabaseService` | Tauri | `tauri-plugin-turso` (embedded libSQL) |
| `nodeDatabaseService` | Node/tests | Node-compatible |

Semua implementasi berbagi `migrate.ts` dan `migrations/*` untuk schema management.

**Catatan penting**: `middleware.ts` set header `Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy: require-corp` agar browser expose `SharedArrayBuffer` yang dibutuhkan Turso WASM thread pool.

---

## 12. Sync System

### Dua Jalur Sync

**1. Legacy KOReader-compatible sync**
- Untuk kompatibilitas dengan KOSync clients
- `src/services/sync/KOSyncClient.ts` → `pages/api/sync.ts`
- Sync reading progress per buku

**2. Replica Sync (modern)**
- Enkripsi lokal dengan passphrase-derived key
- Publish delta ke `pages/api/sync/replicas.ts`
- Pull peer updates, apply via category adapters:
  - Annotations, settings, dictionaries, fonts, textures, OPDS catalogs
- Orchestrator: `replicaSyncManager.ts`
- Cursor store: `replicaCursorStore.ts` (incremental sync)

### Cloud Library (Book Bytes)
- Import: `ingestService.ts` — hash copy atau in-place
- Upload: `cloudService.uploadBook` → `pages/api/storage/upload.ts`
- Download: `pages/api/storage/download.ts`
- Delete: local/cloud/both semantics

---

## 13. Konfigurasi Environment

### File Environment

| File | Target |
|---|---|
| `.env` | Base config |
| `.env.web` | Web build |
| `.env.tauri` | Tauri build |
| `.env.tauri.local` | Local Tauri overrides |
| `.env.apple-*.local` | macOS/iOS signing |
| `.env.ios-*.local` | iOS App Store |
| `.env.google-play.local` | Google Play |

### Variabel Penting

```bash
# Platform
NEXT_PUBLIC_APP_PLATFORM=web|tauri

# Supabase
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

# Storage
S3_ENDPOINT=
S3_PUBLIC_ENDPOINT=
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=
S3_BUCKET_NAME=

# AI
AI_GATEWAY_API_KEY=
NEXT_PUBLIC_AI_GATEWAY_API_KEY=

# Stripe
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=
```

---

## 14. Build & Deploy

### Development

```bash
# Install dependencies
git submodule update --init --recursive
pnpm install
pnpm --filter @readest/readest-app setup-vendors

# Web development
pnpm dev-web

# Tauri desktop development
pnpm tauri dev

# Android
pnpm tauri android dev

# iOS
pnpm tauri ios dev
```

### Production Build

```bash
# Web (Cloudflare Workers)
pnpm deploy

# Desktop
pnpm tauri build

# Android
pnpm tauri android build

# iOS
pnpm tauri ios build
```

### Target Build Spesifik

```bash
pnpm build-win-x64          # Windows x64 NSIS installer
pnpm build-win-arm64        # Windows ARM64
pnpm build-linux-x64        # Linux AppImage
pnpm build-macos-universial # macOS Universal DMG
```

### Deployment Targets

| Target | Cara Deploy |
|---|---|
| Web | Cloudflare Workers via `pnpm deploy` |
| Self-hosted | Docker image (`ghcr.io/readest/readest`) |
| macOS | DMG / App Store |
| Windows | NSIS installer |
| Linux | AppImage / Flathub |
| Android | AAB → Google Play |
| iOS | IPA → App Store |

---

## 15. Testing

### Unit Tests (Vitest)

```bash
pnpm test                   # Run all unit tests
pnpm test:coverage          # With coverage report
pnpm test:browser           # Browser-specific tests
```

Coverage area:
- AI store, chunker, providers, retry
- Database (migrate, mock, turso variants)
- Document (paginator, PDF, TTS, series metadata)
- Components (BookCover, Dropdown, RSVP, dll)
- Hooks (useProgressSync, useTTSControl, dll)
- Libs (crypto: applock, derive, encrypt, envelope)
- Helpers (auth, settings, shortcuts, updater)

### E2E Tests

```bash
# Web E2E (Playwright)
pnpm test:e2e:web

# Tauri E2E (WebdriverIO)
pnpm test:e2e
```

### Lua Tests (KOReader Plugin)

```bash
pnpm test:lua               # busted unit tests untuk koplugin
```

### Verification Checklist (sebelum merge)

1. `pnpm test` — unit tests
2. `pnpm lint` — Biome + tsgo
3. `pnpm test:lua` — Lua tests (jika koplugin berubah)
4. `pnpm fmt:check` — Rust format (jika src-tauri berubah)
5. `pnpm clippy:check` — Rust lint (jika src-tauri berubah)

---

## 16. Internasionalisasi (i18n)

Menggunakan **i18next** dengan `i18next-browser-languagedetector` dan `i18next-http-backend`.

```bash
# Extract strings baru
pnpm i18n:extract

# Translate missing strings
/i18n   # via Claude Code skill
```

Locale files di `public/locales/{lang}/translation.json`. Coverage: 53% populasi dunia.

---

## 17. Subscription & Billing

### Plan Tiers

| Plan | Fitur |
|---|---|
| **Free** | Basic reading, limited AI translations |
| **Plus** | Unlimited AI Read Aloud, more translations, cloud sync |
| **Pro** | DeepL Pro, 100K chars/day translation, 5GB storage, priority support |
| **Lifetime** | Semua fitur Pro selamanya |

### Payment Providers
- **Stripe** — web subscription
- **Apple IAP** — iOS/macOS App Store
- **Google IAP** — Android Google Play

### Gating
Fitur premium di-gate via `src/app/user/plan.ts` yang check subscription state dari Stripe/IAP.

---

## Quick Reference

### Menemukan Kode

| Pertanyaan | Cari di |
|---|---|
| Endpoint HTTP | `src/pages/api`, `src/app/api`, `workers/` |
| UI halaman | `src/app/*` (kecuali `api/`) |
| Komponen reusable | `src/components/` |
| Logic domain/service | `src/services/` |
| Platform-specific | `nativeAppService.ts` / `webAppService.ts` |
| Native Rust | `src-tauri/src/` |
| State global | `src/store/` |
| Shared utilities | `src/utils/`, `src/libs/`, `src/helpers/` |
| Type definitions | `src/types/` |
| Tests | `src/__tests__/` |

### Commands Penting

```bash
pnpm dev-web          # Start web dev server
pnpm tauri dev        # Start Tauri dev
pnpm test             # Run tests
pnpm lint             # Lint code
pnpm format           # Format code
grepai search "..."   # Semantic search di codebase
```

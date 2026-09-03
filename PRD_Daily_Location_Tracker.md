# Product Requirement Document (PRD)

**Project Name:** Daily Location Tracker Mobile App  
**Platform:** Flutter (Android & iOS)  
**Backend & Database:** Supabase (PostgreSQL + PostGIS)  
**Design Project:** Daily Tracker Mobile Interface (Mobile) via Stitch AI  
**Version:** 2.1.0  
**Date:** September 2026  
**Status:** Ready for Development  

---

## 1. Overview & Objectives

### 1.1 Executive Summary
Daily Location Tracker adalah aplikasi mobile berbasis Flutter yang dirancang untuk mencatat riwayat lokasi pengguna secara otomatis minimal satu kali setiap hari. Seluruh data lokasi disimpan dan dikelola menggunakan cloud backend **Supabase** (PostgreSQL). Aplikasi menyajikan data dalam bentuk daftar kronologis harian sehingga pengguna dapat dengan mudah melacak keberadaan mereka pada hari dan tanggal tertentu (misalnya: Senin tanggal X berada di mana, Selasa tanggal Y berada di mana).

### 1.2 Core Goals
* **Otomatisasi Latar Belakang (*Background Tracking*):** Menjamin pencatatan lokasi berjalan otomatis minimal sekali per hari tanpa mengharuskan pengguna membuka aplikasi secara aktif.
* **Cloud Storage & Database Terintegrasi (Supabase):** Menyimpan histori lokasi langsung ke Supabase PostgreSQL database secara terstruktur, aman, dan dapat disinkronkan antarperangkat.
* **Penyajian Data Kronologis:** Menampilkan daftar log lokasi yang informatif (Hari, Tanggal, Jam, Titik Koordinat, dan Alamat hasil geocoding).
* **Modern & Clean UI (Stitch AI Integrated):** Desain visual dan wireframe terstandarisasi mengikuti proyek design system "Daily Tracker Mobile Interface (Mobile)" dari Stitch AI (bebas AI-slop, mengadopsi Material 3 dan Apple Human Interface Guidelines).
* **Cross-Platform Compatibility:** Menghasilkan build artefak yang siap diuji untuk Android (`.apk`) dan iOS (`.ipa`).

---

## 2. Target Users & User Persona

* **Persona Utama:** Pengguna smartphone yang membutuhkan catatan rekam jejak mobilitas harian (misal: pekerja lapangan, traveler, atau pencatatan log pribadi).
* **Karakteristik Kebutuhan:**
  * Tidak perlu check-in manual setiap hari.
  * Data tersimpan aman di cloud database (Supabase) sehingga tidak hilang saat ganti perangkat atau uninstall.
  * Tampilan antarmuka clean, intuitif, dan responsif.
  * Konsumsi baterai tetap hemat dengan periodic single-shot fetch.

---

## 3. Product Scope & Functional Requirements

### 3.1 Permission Management (FR-01)
* **Deskripsi:** Aplikasi mengelola alur izin perangkat sesuai standar iOS & Android.
* **Detail Kebutuhan:**
  * Meminta izin *Location* saat aplikasi aktif (*Foreground / While in Use*).
  * Meminta izin *Background Location* (*Always Allow*) agar pencatatan berkala harian tetap berjalan.
  * Meminta izin notifikasi (wajib di Android 13+ untuk foreground worker service).
  * Memberikan dialog edukatif (*rationale modal / bottom sheet*) jika izin ditolak.

### 3.2 Automated Daily Location Tracking (FR-02)
* **Deskripsi:** Mekanisme penjadwalan berkala untuk menangkap koordinat pengguna.
* **Detail Kebutuhan:**
  * Sistem menjadwalkan task latar belakang minimal 1x per hari (`workmanager` / background service).
  * Mengambil koordinat GPS terkini (`latitude`, `longitude`).
  * Menjalankan proses *Reverse Geocoding* untuk mendapatkan teks alamat.
  * Mengirimkan dan menyimpan data ke tabel Supabase `daily_locations`.
  * Menangani mekanisme *offline buffer* (jika tidak ada koneksi internet saat sinkronisasi, data diantrekan secara lokal via shared_preferences/cache dan dikirim ke Supabase begitu koneksi tersedia).

### 3.3 History List & Display (FR-03)
* **Deskripsi:** Layar antarmuka utama untuk melihat riwayat lokasi harian dari Supabase.
* **Detail Kebutuhan:**
  * Mengambil data dari Supabase via Supabase Flutter SDK dengan pengurutan *descending* berdasarkan tanggal/waktu.
  * Setiap entri menampilkan:
    * Hari dan Tanggal format bahasa Indonesia (Contoh: `Senin, 01 September 2026`).
    * Titik koordinat: `Lat: -6.2088, Long: 106.8456`.
    * Alamat lengkap hasil geocoding.
    * Stempel waktu pencatatan (Contoh: `08:30 WIB • Otomatis`).
  * Fitur *Pull-to-Refresh* untuk mengambil pembaruan terbaru dari Supabase.
  * Mendukung *Supabase Realtime Stream* (opsional, untuk pembaruan instan saat entri baru masuk).

### 3.4 Manual Tracking / Test Trigger (FR-04)
* **Deskripsi:** Tombol aksi cepat untuk mencatat lokasi seketika ke Supabase.
* **Detail Kebutuhan:**
  * Floating Action Button (FAB) "Catat Sekarang" / "Log Current Location Now".
  * Mengambil koordinat saat tombol ditekan dan langsung melakukan `insert` ke Supabase dengan status `is_manual = true`.

---

## 4. Technical Architecture & Stack

### 4.1 Tech Stack
* **Frontend:** Flutter SDK (Stable Channel, Flutter 3.x / Dart 3.x)
* **UI/UX Design Engine:** Stitch AI (Proyek: `Daily Tracker Mobile Interface (Mobile)`)
* **Backend & DB:** Supabase (BaaS) - PostgreSQL Database, PostGIS, Auth (Anonymous / Email), Row Level Security (RLS).
* **State Management:** BLoC / Cubit atau Provider.

### 4.2 Recommended Dependencies
| Package | Kegunaan |
| :--- | :--- |
| `supabase_flutter` | SDK resmi Supabase untuk client query, auth, dan realtime listener |
| `geolocator` | Pengambilan titik koordinat GPS foreground & background |
| `geocoding` | Reverse geocoding koordinat ke alamat human-readable |
| `workmanager` | Eksekusi background task terjadwal harian |
| `intl` | Pemformatan tanggal dan lokalisasi bahasa Indonesia (`id_ID`) |
| `permission_handler` | Manajemen perizinan Android & iOS |

---

## 5. Data Model & Database Schema (Supabase PostgreSQL)

```sql
-- 1. Enable extension PostGIS / UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Buat tabel daily_locations
CREATE TABLE public.daily_locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE, -- Opsional / terhubung dengan user Supabase Auth
    device_id TEXT,                                           -- Identifikasi unik perangkat jika tanpa login
    date_key DATE NOT NULL DEFAULT CURRENT_DATE,              -- Format YYYY-MM-DD
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),           -- Waktu presisi perekaman lokasi
    day_name TEXT NOT NULL,                                   -- 'Senin', 'Selasa', dll.
    latitude DOUBLE PRECISION NOT NULL,                       -- Contoh: -6.2088
    longitude DOUBLE PRECISION NOT NULL,                      -- Contoh: 106.8456
    address TEXT,                                             -- Alamat hasil reverse geocoding
    is_manual BOOLEAN DEFAULT FALSE,                          -- FALSE: Auto background, TRUE: Manual
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Indexes untuk optimasi query timeline harian
CREATE INDEX idx_daily_locations_date ON public.daily_locations (date_key DESC);
CREATE INDEX idx_daily_locations_user ON public.daily_locations (user_id);

-- 4. Keamanan Row Level Security (RLS)
ALTER TABLE public.daily_locations ENABLE ROW LEVEL SECURITY;

-- Policy jika menggunakan Anonymous Auth / Supabase Auth:
CREATE POLICY "Users can read their own location history"
ON public.daily_locations
FOR SELECT
USING (auth.uid() = user_id OR user_id IS NULL);

CREATE POLICY "Users can insert their own location history"
ON public.daily_locations
FOR INSERT
WITH CHECK (auth.uid() = user_id OR user_id IS NULL);
```

---

## 6. Integrasi Supabase di Flutter

### Inisialisasi:
```dart
await Supabase.initialize(
  url: 'https://<YOUR-PROJECT-REF>.supabase.co',
  anonKey: '<YOUR-ANON-KEY>',
);
```

### Query Pengambilan Riwayat (Read):
```dart
final data = await Supabase.instance.client
    .from('daily_locations')
    .select()
    .order('recorded_at', ascending: false);
```

### Penyimpanan Entri Lokasi (Insert):
```dart
await Supabase.instance.client.from('daily_locations').insert({
  'date_key': DateTime.now().toIso8601String().split('T').first,
  'recorded_at': DateTime.now().toUtc().toIso8601String(),
  'day_name': 'Rabu',
  'latitude': position.latitude,
  'longitude': position.longitude,
  'address': formattedAddress,
  'is_manual': false,
});
```

---

## 7. User Interface & Wireframe Concept (Stitch AI Project)

*Desain antarmuka merujuk pada workspace proyek **`Daily Tracker Mobile Interface (Mobile)`** yang dihasilkan melalui Stitch AI dengan prinsip desain utilitas modern (human-crafted utility design).*

### 7.1 Design Tokens & Guidelines
* **Filosofi Visual:** Mengacu pada Apple Health, Linear Mobile, dan Things 3. Bersih, modular, tipografi terstruktur, bebas dari elemen visual artifisial (*anti-AI slop*).
* **Color Palette:**
  * *Primary Accent:* `#1E40AF` (Deep Modern Indigo)
  * *Background Screen:* `#F8FAFC` (Slate Off-White)
  * *Card Surface:* `#FFFFFF` (Solid White dengan 1px subtle border `#E2E8F0` dan diffused elevation)
  * *Status Active Badge:* `#10B981` (Emerald Green text di atas `#ECFDF5` container)
  * *Typography:* Primary Slate 900 (`#0F172A`), Muted Text Slate 500 (`#64748B`), Monospace font untuk koordinat.
* **Spatial Grid:** 8pt spatial grid system dengan border-radius terstandarisasi (14px untuk cards, 24px untuk bottom sheet, full-pill untuk badges).

### 7.2 Layar 1: Home Timeline / History List Screen
```
+------------------------------------------------------+
|  09:41                             📶  🔋 100%       |
+------------------------------------------------------+
|  Daily Tracker                                 ( i ) | <- Top App Bar
+------------------------------------------------------+
|  ┌────────────────────────────────────────────────┐  |
|  │  🟢 Auto-Tracking Aktif                        │  | <- Background Status Banner
|  │     Sinkronisasi harian berjalan otomatis      │  |    (#ECFDF5 / #10B981)
|  └────────────────────────────────────────────────┘  |
|                                                      |
|  Riwayat Lokasi                        [Filter / Kal] | <- Section Header
|                                                      |
|  ┌────────────────────────────────────────────────┐  |
|  │  📅 Rabu, 02 September 2026       [08:30 • Auto]│  | <- Timeline Card (Today)
|  │  📍 Jl. Margonda Raya No. 100, Beji, Depok     │  |
|  │     Lat: -6.3728, Long: 106.8317 (Mono font)   │  |
|  └────────────────────────────────────────────────┘  |
|                                                      |
|  ┌────────────────────────────────────────────────┐  |
|  │  📅 Selasa, 01 September 2026     [09:15 • Auto]│  | <- Timeline Card (Yesterday)
|  │  📍 Jl. Jend. Sudirman Kav. 52, SCBD, Jakarta │  |
|  │     Lat: -6.2251, Long: 106.8094               │  |
|  └────────────────────────────────────────────────┘  |
|                                                      |
|  ┌────────────────────────────────────────────────┐  |
|  │  📅 Senin, 31 Agustus 2026      [18:02 • Manual]│ | <- Offline Card Fallback
|  │  📍 Alamat offline (hanya koordinat mentah)    │  |
|  │     Lat: -6.1754, Long: 106.8272               │  |
|  └────────────────────────────────────────────────┘  |
|                                                      |
|                                ┌───────────────────┐ |
|                                │ + Catat Sekarang  │ | <- Floating Action Button
|                                └───────────────────┘ |    (#1E40AF Pill Button)
+------------------------------------------------------+
```

### 7.3 Layar 2: Background Permission Modal (Bottom Sheet)
```
+------------------------------------------------------+
|                                                      |
|                  [ 📍 Location Icon ]                |
|                                                      |
|             Aktifkan Pelacakan Harian                |
|                                                      |
|    Untuk mencatat riwayat tempat setiap harinya      |
|    secara otomatis tanpa menguras baterai, pilih     |
|    "Selalu Izinkan" (Always Allow) pada izin lokasi.  |
|                                                      |
|    • Penyimpanan Cloud Supabase terenkripsi          |
|    • Snapshot harian berkala (Hemat daya)            |
|                                                      |
|    ┌────────────────────────────────────────────┐    |
|    │           Buka Pengaturan Izin             │    | <- Primary Button (#1E40AF)
|    └────────────────────────────────────────────┘    |
|    ┌────────────────────────────────────────────┐    |
|    │                Nanti Saja                  │    | <- Ghost Button (Text Only)
|    └────────────────────────────────────────────┘    |
|                                                      |
+------------------------------------------------------+
```

---

## 8. Non-Functional Requirements (NFR)

* **Cloud Sync & Latency:** Operasi *write* ke Supabase selesai dalam waktu < 1.5 detik dengan koneksi mobile 4G standar.
* **Offline Handling:** Jika background job berjalan saat perangkat offline, data ditampung sementara dan dikirim ke Supabase saat sinyal kembali aktif.
* **Deliverables:**
  * Berkas rilis Android: `.apk` (Release build).
  * Berkas rilis iOS: `.ipa` (Release / Ad-Hoc signed build).

---

## 9. Acceptance Criteria (AC)

1. **AC-01 (UI Fidelity - Stitch AI):** Tampilan mobile Flutter mengimplementasikan token warna, hierarki tipografi, dan layout sesuai proyek Stitch AI *"Daily Tracker Mobile Interface (Mobile)"*.
2. **AC-02 (Supabase Integration):** Data riwayat lokasi sukses di-*insert* dan muncul di tabel Supabase Table Editor secara akurat.
3. **AC-03 (Pencatatan Otomatis Harian):** Background task berjalan minimal 1 kali per 24 jam dan mengunggah koordinat terkini ke Supabase.
4. **AC-04 (Tampilan UI Real-time / Synchronized):** Layar utama menampilkan daftar lokasi hari demi hari yang ditarik langsung dari Supabase.
5. **AC-05 (Multi-Platform Build):** Berkas `.apk` dan `.ipa` dapat dikompilasi dengan lancar tanpa issue dependensi native dari `supabase_flutter`.

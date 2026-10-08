# Laporan Cara Kerja Aplikasi AIRA

**AIRA Mobile — Aplikasi Visualisasi Segmentasi MRI Prostat Berbantuan AI**

> **Catatan penting:** AIRA adalah alat *visualisasi segmentasi berbantuan AI* untuk keperluan peninjauan citra dan penelitian. Hasilnya **tidak ditujukan untuk diagnosis klinis**.

---

## Daftar Isi

1. [Pendahuluan](#1-pendahuluan)
2. [Ruang Lingkup](#2-ruang-lingkup)
3. [Arsitektur Sistem](#3-arsitektur-sistem)
4. [Teknologi yang Digunakan](#4-teknologi-yang-digunakan)
5. [Alur Kerja Aplikasi](#5-alur-kerja-aplikasi)
6. [Cara Kerja Backend (Image Processing API)](#6-cara-kerja-backend-image-processing-api)
7. [Cara Kerja Aplikasi Mobile](#7-cara-kerja-aplikasi-mobile)
8. [Integrasi Model ML](#8-integrasi-model-ml)
9. [Penanganan Error](#9-penanganan-error)
10. [Keamanan dan Privasi Data](#10-keamanan-dan-privasi-data)
11. [Pengujian](#11-pengujian)
12. [Status Pengembangan](#12-status-pengembangan)
13. [Kesimpulan](#13-kesimpulan)

---

## 1. Pendahuluan

AIRA adalah aplikasi mobile untuk meninjau citra **MRI prostat** dan menampilkan hasil **segmentasi berbasis AI**. Pengguna utamanya adalah radiolog atau dokter, dan pengguna sekundernya adalah peneliti pencitraan medis.

Secara garis besar, AIRA memungkinkan pengguna untuk:

- memilih dan mengunggah file studi MRI dalam format DICOM dari ponsel,
- memvalidasi file dan mengenali jenis sekuens MRI (T2W, DWI, ADC),
- mengonversi DICOM menjadi NIfTI agar siap diproses model AI,
- melihat citra MRI per irisan (*slice*) dengan zoom dan geser,
- menjalankan segmentasi menggunakan model AI yang sudah ada (*pre-trained*),
- melihat hasilnya dalam bentuk citra asli, *mask* segmentasi, dan *overlay*,
- mengekspor hasil.

Kontribusi utama proyek ini ada pada **pengembangan aplikasi dan pipeline integrasi sistem**, bukan pada model AI-nya. Model segmentasi adalah layanan eksternal yang sudah dilatih sebelumnya, dan proyek ini tidak mengembangkan, melatih, atau memodifikasinya.

---

## 2. Ruang Lingkup

| Termasuk dalam lingkup | Di luar lingkup |
|---|---|
| Pengembangan aplikasi mobile dan UI/UX | Pelatihan model ML |
| Unggah dan validasi studi DICOM | Perancangan arsitektur model ML |
| Konversi DICOM ke NIfTI dengan `dicom2nifti` | *Fine-tuning* atau optimasi model |
| Backend FastAPI | Pembuatan algoritma segmentasi baru |
| Integrasi dengan API model segmentasi yang sudah ada | Klaim diagnosis klinis |
| Visualisasi citra asli, *mask*, dan *overlay* | |
| Navigasi irisan, ekstraksi fitur (opsional), ekspor hasil | |
| Pengujian integrasi dan evaluasi performa/kegunaan | |

---

## 3. Arsitektur Sistem

AIRA terdiri dari tiga komponen utama yang dipisahkan dengan jelas:

```text
┌──────────────────────┐   HTTPS / REST   ┌───────────────────────────┐   NIfTI    ┌─────────────────────────┐
│   APLIKASI MOBILE    │ ───────────────▶ │   IMAGE PROCESSING API    │ ─────────▶ │  ML MODEL API (eksternal)│
│   (Flutter, mobile/) │ ◀─────────────── │   (FastAPI, backend/)     │ ◀───────── │  model pre-trained       │
│                      │   JSON / PNG     │                           │   Mask     │                         │
│ • Pilih & unggah     │                  │ • Terima & validasi DICOM │            │ • Preprocessing model   │
│ • Lihat MRI          │                  │ • Kelompokkan per series  │            │ • Inferensi             │
│ • Jalankan segmentasi│                  │ • DICOM → NIfTI           │            │ • Kembalikan mask       │
│ • Lihat hasil        │                  │ • Render slice ke PNG     │            │                         │
│ • Ekspor             │                  │ • Penyimpanan sementara   │            │                         │
└──────────────────────┘                  └───────────────────────────┘            └─────────────────────────┘
```

**Pembagian tanggung jawab:**

| Komponen | Tanggung jawab |
|---|---|
| **Aplikasi Mobile** | Interaksi pengguna, pemilihan file, unggah, tampilan studi, visualisasi MRI dan hasil segmentasi, navigasi irisan, ekspor. Ponsel **tidak** melakukan komputasi numerik berat. |
| **Image Processing API** | Menerima file, validasi DICOM, pengelompokan series, klasifikasi modalitas, konversi DICOM → NIfTI, rendering irisan ke PNG, manajemen penyimpanan sementara, dan menjadi perantara ke ML API. |
| **ML Model API** | Layanan eksternal yang menerima NIfTI, melakukan *preprocessing* khusus model, inferensi, dan mengembalikan *mask* segmentasi. |

Kredensial ML API hanya disimpan di backend dan tidak pernah dimasukkan ke dalam aplikasi mobile.

---

## 4. Teknologi yang Digunakan

### 4.1 Aplikasi Mobile (`mobile/`)

| Teknologi | Fungsi |
|---|---|
| **Flutter / Dart (≥ 3.8)** | Framework UI lintas platform (Android & iOS) |
| **flutter_riverpod** | Manajemen *state* dan *dependency injection* |
| **go_router** | Navigasi/rute antarlayar |
| **dio** | HTTP client untuk komunikasi REST, termasuk unggah *multipart* dengan progres |
| **file_picker** | Memilih file DICOM / `.zip` dari perangkat |
| **google_fonts, lucide_icons_flutter** | Tipografi dan ikon |

### 4.2 Backend (`backend/`)

| Library | Fungsi |
|---|---|
| **FastAPI** | Framework web: routing, validasi request/response, dokumentasi OpenAPI otomatis (`/docs`) |
| **Uvicorn** | Server ASGI untuk menjalankan FastAPI |
| **python-multipart** | Parsing form-data agar FastAPI dapat menerima unggahan file |
| **pydantic-settings** | Membaca konfigurasi dari *environment variable* / `.env` |
| **pydicom** | Membaca header DICOM tanpa men-*decode* data piksel |
| **dicom2nifti** | Inti konversi: satu folder series DICOM → satu file `.nii.gz`, termasuk penanganan orientasi |
| **nibabel** | Membaca file NIfTI hasil konversi (header dan data voxel) |
| **numpy** | Operasi array, *windowing* intensitas |
| **Pillow** | Meng-*encode* irisan menjadi gambar PNG |
| **pytest, httpx** | Pengujian otomatis |

Backend juga disediakan dalam bentuk **Docker image** (`backend/Dockerfile`).

---

## 5. Alur Kerja Aplikasi

### 5.1 Alur dari sisi pengguna

```text
 [1] Home ──▶ [2] Tambah Studi ──▶ [3] Detail Studi ──▶ [4] MRI Viewer
                 (pilih file,           (status,             (navigasi slice,
                  upload, konversi)      validasi modalitas)  zoom, pan)
                                              │
                                              ▼
                                    [5] Segmentasi AI ──▶ [6] Hasil ──▶ [7] Ekspor
                                                          (Original / Mask /
                                                           Overlay / Fitur)
```

### 5.2 Alur data end-to-end

```text
Pengguna memilih file DICOM / .zip di ponsel
        │
        ▼
POST /api/v1/studies/upload  (multipart)
        │  backend: simpan → ekstrak zip → baca header → validasi → kelompokkan per series
        │           → klasifikasi T2W / DWI / ADC
        ▼
Respons: study_id, daftar series, modalitas, jumlah file yang dilewati
        │
        ▼
POST /api/v1/studies/{study_id}/convert
        │  backend: dicom2nifti per series → baca header NIfTI (shape, spacing)
        ▼
Respons: daftar file NIfTI (resource_id, modality, shape, voxel_spacing)
        │
        ▼
GET /api/v1/resources/{resource_id}/slices/{index}
        │  backend: muat volume (cache) → windowing → potong irisan aksial → PNG
        ▼
Ponsel menampilkan PNG; pengguna menggeser antar irisan
        │
        ▼
(Fase 3) Segmentasi: backend mengirim NIfTI ke ML API → menerima mask
        │
        ▼
(Fase 4–5) Visualisasi mask & overlay, fitur opsional, ekspor
```

---

## 6. Cara Kerja Backend (Image Processing API)

### 6.1 Struktur kode

```text
backend/app/
├── main.py                  # membangun aplikasi FastAPI, middleware, lifespan, router
├── core/
│   ├── config.py            # pengaturan (environment variable)
│   ├── errors.py            # AppError + handler error → {"error": {code, message}}
│   └── logging.py           # logging minimal, tanpa data pasien
├── api/
│   ├── health.py            # GET /health
│   ├── studies.py           # upload, convert, get, delete studi
│   └── resources.py         # unduh .nii.gz, ambil irisan PNG
├── services/
│   ├── dicom_service.py     # simpan unggahan, ekstrak zip, validasi & kelompokkan DICOM
│   ├── nifti_service.py     # konversi DICOM → NIfTI
│   ├── slice_service.py     # render irisan NIfTI ke PNG (dengan cache)
│   ├── storage.py           # penyimpanan sementara per studi + pembersihan TTL
│   └── segmentation_service.py  # placeholder Fase 3
├── clients/ml_model_client.py   # antarmuka abstrak ke ML API eksternal
└── models/
    ├── study.py             # representasi internal (StudyRecord, SeriesRecord, NiftiRecord)
    └── schemas.py           # kontrak API publik — hanya ID opak, tanpa path file
```

### 6.2 Daftar endpoint REST

| Method | Path | Fungsi |
|---|---|---|
| `GET` | `/health` | Cek apakah server hidup |
| `POST` | `/api/v1/studies/upload` | Unggah file DICOM / `.zip` (boleh campuran), validasi, kelompokkan series, klasifikasi modalitas |
| `POST` | `/api/v1/studies/{study_id}/convert` | Konversi DICOM → NIfTI untuk modalitas yang diizinkan |
| `GET` | `/api/v1/studies/{study_id}` | Status studi, daftar series, dan file NIfTI |
| `DELETE` | `/api/v1/studies/{study_id}` | Hapus file sementara studi |
| `GET` | `/api/v1/resources/{resource_id}` | Unduh file `.nii.gz` hasil konversi |
| `GET` | `/api/v1/resources/{resource_id}/slices/{index}` | Ambil satu irisan aksial sebagai PNG grayscale |

### 6.3 Startup dan pembersihan otomatis

Saat server dijalankan (`main.py`):

1. Konfigurasi (`Settings`) dibaca dari *environment variable* / `.env`.
2. Objek `StudyStorage` dibuat untuk mengelola folder penyimpanan.
3. Middleware CORS, router (`health`, `studies`, `resources`), dan *exception handler* didaftarkan.
4. Fungsi `cleanup_expired()` dijalankan sekali, lalu diulang oleh *background task* setiap `cleanup_interval_minutes` (default 60 menit). Studi yang lebih tua dari `study_ttl_hours` (default 24 jam) dihapus otomatis.

### 6.4 Penyimpanan sementara per studi

Setiap studi punya folder sendiri:

```text
{storage_dir}/{study_id}/
    study.json      # status studi (StudyRecord) dalam JSON
    upload/         # file mentah hasil unggahan (dihapus setelah pengelompokan)
    dicom/{n}/      # file DICOM valid, satu folder per series
    nifti/          # file .nii.gz hasil konversi
```

- `study_id` dan `resource_id` berupa UUID heksadesimal 32 karakter yang dibuat server. ID yang formatnya tidak sesuai langsung ditolak, sehingga serangan *path traversal* tidak mungkin dilakukan.
- `study.json` ditulis secara atomik (tulis ke file `.tmp` lalu `replace`) dan dilindungi *lock* agar aman diakses beberapa *thread*.

### 6.5 Tahap Upload (`dicom_service.py`)

1. **Simpan file** — setiap file di-*stream* ke disk per potongan 1 MB dengan **nama yang dibuat server**, bukan nama dari klien. Total ukuran dibatasi `max_upload_mb` (default 1024 MB). Jika terlampaui, server mengembalikan error `UPLOAD_TOO_LARGE`.
2. **Ekstrak arsip** — setiap file `.zip` (boleh lebih dari satu, misalnya satu zip per modalitas) diekstrak. Anggota zip juga disimpan dengan nama dari server dan tetap dihitung terhadap batas ukuran.
3. **Validasi header** — setiap file dibaca dengan `pydicom.dcmread(..., stop_before_pixels=True)` (hanya header, tanpa piksel). File dibuang jika:
   - bukan DICOM yang valid,
   - berupa file `DICOMDIR`,
   - tidak memiliki tag wajib (`SeriesInstanceUID`, `SOPInstanceUID`, `Rows`, `Columns`),
   - modalitasnya bukan `MR`,
   - merupakan duplikat (`SOPInstanceUID` yang sama dalam satu series).
4. **Kelompokkan per series** — file valid dikelompokkan berdasarkan `SeriesInstanceUID` dan dipindahkan ke folder `dicom/000`, `dicom/001`, dan seterusnya.
5. **Klasifikasi modalitas** secara heuristik dari header DICOM:

   | Modalitas | Aturan pengenalan |
   |---|---|
   | **ADC** | `ImageType` atau teks deskripsi mengandung "ADC" / "APPARENT DIFFUSION" |
   | **DWI** | `ImageType` mengandung "DIFFUSION", atau teks mengandung DWI/DIFFUSION/TRACEW/EP2D_DIFF/B1000/B800, atau nilai *b-value* > 0 (tag standar, GE, atau Siemens) |
   | **T2W** | Teks mengandung "T2" (bukan "T2*"), atau *Echo Time* ≥ 80 ms dan *Repetition Time* ≥ 2000 ms |
   | **unknown** | Tidak memenuhi aturan di atas |

   Teks yang diperiksa adalah gabungan `SeriesDescription`, `ProtocolName`, dan `SequenceName`.

6. Folder `upload/` dihapus, status studi menjadi `uploaded`, lalu respons berisi `study_id`, daftar series, modalitas yang ditemukan, dan jumlah file yang dilewati dikirim ke aplikasi.

### 6.6 Tahap Konversi DICOM → NIfTI (`nifti_service.py`)

1. Pilih series yang modalitasnya termasuk `allowed_modalities` (default: T2W, DWI, ADC). Jika tidak ada satu pun, server mengembalikan `UNSUPPORTED_MODALITY`.
2. Periksa `required_modalities` (default: T2W). Jika tidak ada, server mengembalikan `MISSING_REQUIRED_MODALITY`.
3. Untuk setiap series, panggil:
   ```python
   dicom2nifti.dicom_series_to_nifti(source_dir, target.nii.gz, reorient_nifti=True)
   ```
   Proyek ini **tidak membuat konverter DICOM sendiri**. Seluruh penanganan geometri dan orientasi dikerjakan oleh library.
4. Header NIfTI dibaca kembali dengan `nibabel` untuk mencatat **shape** (dimensi voxel) dan **voxel spacing** (mm). Hasil yang bukan 3D/4D ditolak.
5. **Toleransi kegagalan:** series yang gagal dikonversi dilewati tanpa menggagalkan seluruh studi, **kecuali** jika series modalitas wajib (T2W) yang gagal. Dalam kasus itu semua hasil parsial dihapus (*rollback*) dan server mengembalikan `CONVERSION_FAILED`.
6. Konversi bersifat CPU/IO-bound, jadi dijalankan lewat `run_in_threadpool` agar *event loop* async tidak terblokir.

**Transisi status studi:**

```text
UPLOADED ──convert──▶ CONVERTING ──sukses──▶ CONVERTED
                           │
                           └──gagal──▶ FAILED (atau kembali ke status sebelumnya
                                               untuk error validasi)
```

Jika studi sedang dikonversi lalu diminta konversi lagi, server menolaknya dengan error `INVALID_STATE` (HTTP 409) agar tidak terjadi konversi ganda. Studi yang sudah `CONVERTED` langsung mengembalikan hasil sebelumnya.

### 6.7 Rendering irisan ke PNG (`slice_service.py`)

Agar ponsel tidak perlu mengurai file NIfTI/gzip yang berat, backend merender setiap irisan menjadi gambar:

1. **Muat volume** dengan `nibabel` lalu simpan di **cache memori** (maksimal 8 volume, FIFO, *thread-safe*). Akibatnya, menggeser antar irisan tetap cepat tanpa membaca file berulang kali.
2. **Windowing intensitas** dihitung **sekali per volume** dengan persentil ke-1 dan ke-99, bukan per irisan, sehingga kecerahan tetap stabil saat pengguna menggeser irisan.
3. **Ambil irisan aksial** pada sumbu ke-2 (sumbu aksial setelah reorientasi `dicom2nifti`). Untuk data 4D, misalnya DWI dengan beberapa *b-value*, yang diambil adalah volume pertama.
4. Irisan ditransposisi dan dibalik vertikal agar orientasinya sesuai tampilan standar.
5. Nilai intensitas di-*clip* dan dinormalisasi ke rentang 0–255 (8-bit).
6. Gambar diperkecil jika sisi terpanjangnya melebihi 512 piksel, lalu di-*encode* menjadi PNG grayscale.

### 6.8 Konfigurasi

| Variabel | Default | Keterangan |
|---|---|---|
| `STORAGE_DIR` | `storage` | Lokasi penyimpanan sementara |
| `MAX_UPLOAD_MB` | `1024` | Batas total ukuran unggahan |
| `STUDY_TTL_HOURS` | `24` | Umur maksimum studi sebelum dihapus |
| `CLEANUP_INTERVAL_MINUTES` | `60` | Interval pembersihan otomatis |
| `ALLOWED_MODALITIES` | `T2W,DWI,ADC` | Modalitas yang dikonversi |
| `REQUIRED_MODALITIES` | `T2W` | Modalitas wajib |
| `CORS_ORIGINS` | `*` | Origin yang diizinkan |
| `ML_API_URL`, `ML_API_KEY`, `ML_API_TIMEOUT_SECONDS` | – | Koneksi ke ML API (Fase 3), hanya di backend |

---

## 7. Cara Kerja Aplikasi Mobile

### 7.1 Struktur kode

Aplikasi disusun berdasarkan fitur (*feature-first*) dengan lapisan yang terpisah:

```text
mobile/lib/
├── main.dart              # entry point + failsafe error
├── app/                   # widget aplikasi, router, tema, shell navigasi bawah
├── core/
│   ├── config/            # AppConfig (URL API, timeout)
│   ├── network/           # ApiClient (Dio) + ApiException
│   ├── design_system/     # komponen UI (tombol, kartu, chip status, slider, dll.)
│   └── widgets/           # banner disclaimer, tampilan slice NIfTI, status views
├── data/
│   ├── models/study.dart          # model data sesuai kontrak API backend
│   └── repositories/study_repository.dart  # pemanggilan endpoint backend
└── features/
    ├── home/              # Beranda: ringkasan dan studi terbaru
    ├── study_import/      # Pilih file, unggah, konversi
    ├── studies/           # Daftar studi, detail studi, provider bersama
    ├── viewer/            # MRI Viewer: navigasi irisan, zoom
    ├── segmentation/      # Layar segmentasi AI
    ├── results/           # Hasil: Original / Mask / Overlay / Features
    ├── export/            # Ekspor hasil per studi
    ├── exports/           # Tab daftar ekspor
    └── settings/          # Pengaturan dan informasi
```

### 7.2 Lapisan arsitektur

```text
Presentation (Screen/Widget)
        │  membaca/menonton state
        ▼
Application (Riverpod Notifier/Provider)  ← StudyImportController, studyProvider, sliceProvider
        │  memanggil
        ▼
Data (StudyRepository)                    ← uploadStudy, convertStudy, getStudy, getSlice
        │  memakai
        ▼
Core (ApiClient → Dio)                    ← HTTP, konversi error ke ApiException
        │
        ▼
Backend FastAPI
```

### 7.3 Navigasi

Aplikasi memakai `go_router` dengan **shell navigasi bawah** berisi 4 tab: **Home, Studies, Exports, Settings**. Layar per studi dibuka sebagai layar penuh di atas shell:

| Rute | Layar |
|---|---|
| `/` | Home |
| `/studies` | Daftar studi |
| `/exports` | Daftar ekspor |
| `/settings` | Pengaturan |
| `/import` | Tambah studi (unggah & konversi) |
| `/studies/:studyId` | Detail studi |
| `/studies/:studyId/viewer` | MRI Viewer |
| `/studies/:studyId/segmentation` | Segmentasi |
| `/studies/:studyId/results` | Hasil |
| `/studies/:studyId/export` | Ekspor |

### 7.4 Penjelasan tiap layar

**1. Home**
Menampilkan ringkasan berupa jumlah studi, studi yang siap (*Ready*), dan studi yang perlu tindakan (*Needs action*), beserta daftar studi terbaru. Jika belum ada studi, muncul ajakan "Add your first study".

**2. Tambah Studi (Study Import)**
Dikendalikan oleh `StudyImportController` yang punya fase-fase berikut:

```text
selecting ──▶ uploading ──▶ converting ──▶ done
                  │              │
                  └──────────────┴──▶ error (bisa Retry)
```

- Pengguna memilih file lewat *file picker* dengan tipe file bebas, karena file DICOM sering tidak memiliki ekstensi. File `.zip` dari folder studi juga diterima.
- File dibaca sebagai **stream byte** (bukan lewat path), karena *picker* di Android bisa mengembalikan URI `content://` tanpa path lokal.
- Duplikat dicegah berdasarkan URI file. Pengguna bisa menghapus satu file atau mengosongkan pilihan.
- Tombol **Upload & convert** mengunggah file secara *multipart* dengan indikator progres (%) dan opsi **Cancel upload**, lalu otomatis memanggil endpoint konversi.
- Setelah selesai, ditampilkan **validasi modalitas** (T2W / DWI / ADC ditemukan atau tidak, jumlah gambar) dan jumlah file yang dilewati.
- Jika konversi gagal setelah upload berhasil, tombol **Retry** hanya mengulang konversi tanpa mengunggah ulang.

**3. Detail Studi**
Menampilkan status studi, metrik (jumlah series, jumlah irisan, bidang *Axial*), dan daftar modalitas. Jika T2W tidak ada, muncul peringatan "Missing modality" karena model membutuhkan T2W. Dari sini pengguna dapat membuka **MRI Viewer** atau **Run AI Segmentation**.

**4. MRI Viewer**
- Tab per modalitas yang tersedia.
- Navigasi irisan dengan slider dan tombol *previous/next*, ditambah label "Slice x / N".
- *Pinch-to-zoom*, geser (*pan*), dan *double-tap* untuk zoom 2× atau reset.
- Panel "Series details" menampilkan dimensi volume dan *voxel spacing* (mm).
- Setiap irisan diambil sebagai PNG dari backend melalui `sliceProvider`. Riverpod `family` meng-*cache* gambar per (`resourceId`, `index`), jadi kembali ke irisan yang pernah dibuka terjadi instan tanpa request ulang.
- **Prefetch:** irisan sebelum dan sesudahnya dimuat lebih awal supaya pergeseran irisan terasa mulus.

**5. Segmentasi**
Menampilkan volume input yang tersedia dan tombol **Run AI Segmentation**. Backend akan mengirim volume NIfTI ke ML API yang sudah ada (diimplementasikan di Fase 3).

**6. Hasil (Results)**
Empat tab:
- **Original:** volume MRI asli. Yang diutamakan adalah T2W sebagai referensi anatomi.
- **Mask:** *mask* segmentasi.
- **Overlay:** MRI + *mask* dengan pengatur **opacity**.
- **Features:** fitur bentuk/intensitas/tekstur (opsional).

**7. Ekspor**
Opsi ekspor yang direncanakan: **Overlay PNG**, **Report** (ringkasan studi dan hasil), **Mask NIfTI** (`.nii.gz`), dan **Features CSV/JSON**.

**8. Settings**
Informasi tentang hasil, alamat Image-processing API yang digunakan, dan catatan privasi.

### 7.5 Manajemen state

- **`studyProvider`** (FutureProvider per `studyId`): mengambil detail studi dari backend.
- **`recentStudiesProvider`**: daftar maksimal 20 studi yang dibuka selama sesi aplikasi. Daftar ini **hanya disimpan di memori**, jadi tidak ada data pasien yang tersimpan permanen di perangkat.
- **`studyImportControllerProvider`**: state proses impor (file, fase, progres, error). Bersifat *auto-dispose*, dan unggahan dibatalkan jika layar ditutup.
- **`sliceProvider`**: cache gambar irisan.

### 7.6 Konfigurasi dan ketahanan

- URL backend diatur saat build: `--dart-define=API_BASE_URL=...` (default `http://10.0.2.2:8000` untuk emulator Android).
- Timeout: koneksi 10 detik, terima 5 menit, kirim 10 menit (untuk unggahan besar).
- HTTP biasa hanya diizinkan pada build *debug* Android. Build *release* wajib memakai HTTPS.
- **Failsafe error:** layar error merah bawaan Flutter diganti pesan "Something went wrong" yang tenang dan sesuai desain aplikasi, karena aplikasi klinis tidak semestinya menampilkan *stack trace* kepada pengguna. Error tetap dicatat di log debug.
- **Banner disclaimer** "Not intended for diagnosis" ditampilkan di layar-layar terkait hasil.

---

## 8. Integrasi Model ML

Backend berkomunikasi dengan ML API melalui **antarmuka abstrak** (*adapter pattern*) di `clients/ml_model_client.py`:

```python
class MLModelClient(ABC):
    async def segment(self, inputs: list[ModelInput], output_dir: Path) -> SegmentationOutput:
        """Kirim volume NIfTI siap-model, kembalikan mask segmentasi."""

    async def health(self) -> bool:
        """Apakah layanan ML dapat dijangkau."""
```

- `ModelInput` berisi modalitas dan path NIfTI.
- `SegmentationOutput` berisi path *mask* dan label kelas (`dict[int, str]`).
- `SegmentationService` akan memuat NIfTI studi, memanggil `MLModelClient.segment`, lalu menyimpan *mask* sebagai resource hasil.

Dengan pola ini, implementasi bisa diganti dari **mock ke layanan nyata** tanpa mengubah logika bisnis. *Preprocessing* khusus model tetap dikerjakan di dalam layanan ML, bukan di AIRA. Saat ini antarmuka sudah didefinisikan, sedangkan implementasinya dijadwalkan pada Fase 3.

---

## 9. Penanganan Error

Semua error dari backend dikembalikan dalam format seragam:

```json
{ "error": { "code": "CONVERSION_FAILED", "message": "Unable to convert the selected MRI study. ..." } }
```

| Kode | HTTP | Arti |
|---|---|---|
| `INVALID_DICOM` | 400 | File bukan DICOM yang valid / zip rusak |
| `NO_DICOM_FOUND` | 400 | Tidak ada file DICOM dalam unggahan |
| `UPLOAD_TOO_LARGE` | 413 | Melebihi batas ukuran unggahan |
| `UNSUPPORTED_MODALITY` | 422 | Tidak ada series T2W/DWI/ADC |
| `MISSING_REQUIRED_MODALITY` | 422 | Modalitas wajib (T2W) tidak ada |
| `CONVERSION_FAILED` | 422 | Konversi gagal |
| `UNSUPPORTED_VOLUME` | 422 | Volume NIfTI tidak dapat ditampilkan |
| `INVALID_SLICE_INDEX` | 400 | Indeks irisan di luar rentang |
| `STUDY_NOT_FOUND` / `RESOURCE_NOT_FOUND` | 404 | Studi/resource tidak ada atau kedaluwarsa |
| `INVALID_STATE` | 409 | Studi sedang dikonversi |
| `INVALID_REQUEST` | 422 | Request tidak lengkap |
| `INTERNAL_ERROR` | 500 | Error tak terduga (pesan generik) |

Pesan error aman ditampilkan ke pengguna dan tidak memuat *stack trace* maupun path server. Di sisi mobile, `ApiClient` mengubah semua error jaringan/HTTP menjadi `ApiException`, lalu pesannya ditampilkan di UI, misalnya pada kartu "Import failed" dengan tombol Retry.

---

## 10. Keamanan dan Privasi Data

| Aspek | Penerapan |
|---|---|
| **Data sementara** | File studi disimpan sementara per studi dan dihapus otomatis setelah TTL (default 24 jam) atau saat pengguna menghapus studi. |
| **Tanpa log data pasien** | Identitas pasien tidak pernah dicatat. Untuk exception, yang dicatat hanya *tipe*-nya, bukan pesannya, karena pesan bisa memuat path atau nilai header DICOM. Log `dicom2nifti` dibisukan. |
| **Path traversal** | Nama file dari klien dan path di dalam zip tidak pernah dipakai. Semua nama dibuat server, dan ID divalidasi formatnya. |
| **ID opak** | API publik hanya mengembalikan ID acak (`study_id`, `resource_id`), tidak pernah path sistem file. |
| **Kredensial ML** | Hanya ada di environment backend, tidak di aplikasi mobile. |
| **Penyimpanan di ponsel** | Daftar studi hanya di memori selama sesi, tidak ada data pasien yang dipersistenkan. |
| **Transport** | Build *release* wajib HTTPS. |
| **Batas ukuran** | Total unggahan dan isi zip dibatasi agar tahan terhadap *zip bomb*. |
| **Data pengembangan** | Disarankan memakai data yang sudah dide-identifikasi, misalnya koleksi publik PROSTATEx di TCIA. |

---

## 11. Pengujian

### Backend (pytest)

| File uji | Cakupan |
|---|---|
| `test_health.py` | Endpoint `/health` |
| `test_dicom_service.py` | Validasi header dan klasifikasi modalitas |
| `test_studies_api.py` | Alur upload, konversi, get, delete, dan kasus error |
| `test_slices_api.py` | Rendering irisan PNG dan validasi indeks |

Menjalankan pengujian:

```bash
cd backend
python -m pip install -r requirements-dev.txt
python -m pytest
```

### Mobile (flutter test)

| File uji | Cakupan |
|---|---|
| `study_model_test.dart` | Parsing model `Study` dari JSON API |
| `widget_test.dart` | Uji widget dasar aplikasi |

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```

---

## 12. Status Pengembangan

| Fase | Lingkup | Status |
|---|---|---|
| 1 | Kerangka Flutter, FastAPI, `/health` | ✅ Selesai |
| 2 | Pemilihan DICOM, unggah *multipart*, validasi, konversi `dicom2nifti`, viewer irisan | ✅ Selesai |
| 3 | Klien ML API (mock terlebih dahulu), job segmentasi | 🔶 Antarmuka saja |
| 4 | Rendering *mask*, *overlay*, pengatur *opacity* | 🔶 UI sudah dirancang |
| 5 | Fitur opsional, ekspor/laporan | 🔶 UI sudah dirancang |
| 6–7 | Pengujian menyeluruh, *deployment* | ⏳ Direncanakan |

---

## 13. Kesimpulan

AIRA memisahkan tanggung jawab dengan jelas antara **aplikasi mobile** (antarmuka dan visualisasi), **Image Processing API** (validasi DICOM, konversi ke NIfTI, rendering irisan), dan **ML Model API eksternal** (inferensi segmentasi). Beberapa keputusan desain yang penting:

1. **Komputasi berat dilakukan di backend**, sehingga ponsel cukup menampilkan PNG per irisan. Hal ini membuat aplikasi ringan dan responsif.
2. **Konversi memakai library standar (`dicom2nifti`)** alih-alih konverter buatan sendiri, sehingga orientasi dan geometri citra lebih andal.
3. **Pola adapter untuk ML API** membuat model segmentasi dapat diganti (mock → nyata) tanpa mengubah logika aplikasi.
4. **Privasi diterapkan sejak awal**: penyimpanan sementara dengan TTL, ID opak, tidak ada log data pasien, dan tidak ada data yang tersimpan di perangkat.
5. **Toleransi kesalahan**: series yang gagal dikonversi dilewati selama modalitas wajib berhasil, dan pesan error selalu aman serta mudah dipahami pengguna.

Fase 1–2 (unggah, validasi, konversi, dan penampil MRI) sudah berfungsi penuh. Fase berikutnya akan menghubungkan model segmentasi yang sudah ada dan melengkapi visualisasi *mask*, *overlay*, serta fitur ekspor.

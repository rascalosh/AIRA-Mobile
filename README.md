# AIRA Mobile — Prostate MRI AI-Assisted Segmentation Visualization

A mobile application for prostate MRI review and **AI-assisted segmentation visualization**.
The contribution of this project is the **application and system integration pipeline**; the
segmentation model is an existing, pre-trained service and is not developed, trained or modified here.
Results are not intended for diagnosis.



```text
Flutter app ──HTTPS/REST──▶ FastAPI image-processing API ──NIfTI──▶ existing ML Model API
  (mobile/)                   (backend/: DICOM validation,            (external, Phase 3)
                               dicom2nifti conversion)
```

## Status

| Phase | Scope | State |
|---|---|---|
| 1 | Flutter skeleton, FastAPI, `/health` | ✅ |
| 2 | DICOM selection, multipart upload, validation, `dicom2nifti` conversion | ✅ |
| 3 | ML API client (mock first), segmentation jobs | interface only |
| 4 | Slice rendering, mask, overlay, opacity | UI scaffolded |
| 5 | Features, export/report | UI scaffolded |

## Backend (`backend/`)

Python 3.10+ (developed with 3.12).

```powershell
cd backend
if (-not (Test-Path .venv)) { python -m venv .venv }   # create once; don't re-run on an existing venv
.venv\Scripts\python -m pip install -r requirements-dev.txt
.venv\Scripts\python -m pytest
.venv\Scripts\uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

If you need to recreate or upgrade the venv, stop the running server first (Ctrl+C). Windows can't
replace `.venv\Scripts\python.exe` while uvicorn is using it (`Permission denied`).

Interactive API docs: http://localhost:8000/docs. Configuration: copy `.env.example` to `.env`.

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Liveness check |
| POST | `/api/v1/studies/upload` | Multipart `files` (DICOM files, one or more `.zip` archives, or a mix); validates and groups series, classifies T2W/DWI/ADC |
| POST | `/api/v1/studies/{study_id}/convert` | DICOM → NIfTI (`dicom2nifti`) for allowed modalities |
| GET | `/api/v1/studies/{study_id}` | Study status, series and NIfTI resources |
| GET | `/api/v1/resources/{resource_id}` | Download a converted `.nii.gz` |
| DELETE | `/api/v1/studies/{study_id}` | Remove the study's temporary files |

Errors are returned as `{"error": {"code", "message"}}` with user-safe messages; no stack traces or
server paths are exposed. Uploaded data lives in temporary per-study storage and is deleted after
`STUDY_TTL_HOURS`. Patient identifiers are never logged.

### Libraries

| Library | Purpose |
|---|---|
| FastAPI | Web framework — routing, request/response validation, dependency injection, auto OpenAPI docs at `/docs` |
| Uvicorn | ASGI server that runs the FastAPI app |
| python-multipart | Multipart form-data parsing, required by FastAPI to accept file uploads (`UploadFile`) |
| pydantic-settings | Loads `Settings` from environment variables / `.env` |
| pydicom | Reads DICOM headers (`SeriesInstanceUID`, `Modality`, `SeriesDescription`, …) without decoding pixel data |
| dicom2nifti | Core conversion library — turns one DICOM series folder into one `.nii.gz`, including orientation/geometry handling |
| nibabel | Reads the converted `.nii.gz` back — header (shape, voxel spacing) and voxel data |
| numpy | Array operations used internally by dicom2nifti/nibabel, and for windowing/normalization when rendering a slice to an image |
| Pillow | Encodes a numpy array to PNG when serving one slice to the mobile app |
| pytest, httpx | Dev-only: test runner and the HTTP client FastAPI's `TestClient` needs |

### Architecture

```text
app/
├── main.py              # builds the FastAPI app, middleware, lifespan, routers
├── core/
│   ├── config.py          # Settings (env vars)
│   ├── errors.py          # AppError + exception handlers -> {"error": {code, message}}
│   └── logging.py         # minimal logging; patient data is never logged
├── api/
│   ├── health.py          # GET /health
│   ├── studies.py         # upload, convert, get, delete study
│   └── resources.py       # download .nii.gz, fetch a rendered slice
├── services/
│   ├── dicom_service.py    # save uploads, expand zips, validate & group DICOM into series
│   ├── nifti_service.py    # DICOM -> NIfTI via dicom2nifti
│   ├── slice_service.py    # render one NIfTI slice to a PNG (with a small volume cache)
│   ├── storage.py          # temporary per-study storage on disk, including TTL cleanup
│   └── segmentation_service.py  # Phase 3 placeholder, not yet implemented
├── clients/ml_model_client.py   # abstract interface to the external ML API (Phase 3)
└── models/
    ├── study.py             # internal representation (StudyRecord, SeriesRecord, NiftiRecord)
    └── schemas.py            # public API contract — opaque IDs only, never filesystem paths
```

`models/study.py` is the internal representation (it may reference server-side file/folder names);
`models/schemas.py` is what's actually sent to the client and never exposes a filesystem path.

### Request flow

1. **Startup** (`main.py`): load `Settings`, create the `StudyStorage`, add CORS middleware,
   register the `health`/`studies`/`resources` routers and the exception handlers. The `lifespan`
   context runs `cleanup_expired()` once immediately, then a background task repeats it every
   `cleanup_interval_minutes` (default 60), deleting any study older than `study_ttl_hours`
   (default 24h).
2. **Upload** (`POST /studies/upload`, `dicom_service.py`): create a `study_id` and its
   `upload/`/`dicom/`/`nifti/` folders → stream each uploaded file to disk under a
   server-generated name (never the client's filename, which rules out path traversal) while
   enforcing `max_upload_mb` → expand any `.zip` archives into their member files → read every
   file's DICOM header, drop anything that isn't a valid MR image or is a duplicate instance,
   group the rest by `SeriesInstanceUID`, and classify each series' modality (T2W/DWI/ADC) from
   its `SeriesDescription`/`ProtocolName`/`SequenceName` or its b-value/echo-time/repetition-time.
3. **Convert** (`POST /studies/{study_id}/convert`): see the dedicated section below.
4. **Serve results** (`api/resources.py`): `GET /resources/{resource_id}` streams the raw
   `.nii.gz` back; `GET /resources/{resource_id}/slices/{index}` decodes the volume once (cached
   in memory, bounded to 8 volumes), windows it to 1st/99th percentile intensity, and returns one
   axial slice as a grayscale PNG — so the phone never has to parse NIfTI/gzip itself.
5. **Cleanup**: `DELETE /studies/{study_id}` removes a study's files immediately; otherwise the
   background task in step 1 removes it once it's older than the TTL.
6. **Errors**: any `AppError` raised anywhere in this flow is turned into a JSON body
   `{"error": {"code", "message"}}` by the handler in `core/errors.py`; unexpected exceptions are
   caught too and only their exception *type* is logged, never their message (which could contain
   a file path or DICOM header value), and the client gets a generic 500.

### DICOM → NIfTI conversion (`app/services/nifti_service.py`)

1. **Upload** (`POST /studies/upload`) first expands any `.zip` archives among the uploaded files
   (any number of them — e.g. one zip per modality is fine, they're all merged into one study),
   then groups every resulting file into series by `SeriesInstanceUID` and classifies each
   series' modality (T2W/DWI/ADC) from its `SeriesDescription` (`app/services/dicom_service.py`).
   No conversion happens yet.
2. **Convert** (`POST /studies/{study_id}/convert`) then, for each series whose modality is in
   `allowed_modalities` (default `T2W, DWI, ADC`):
   - runs `dicom2nifti.dicom_series_to_nifti(source_dir, target.nii.gz, reorient_nifti=True)` —
     no custom DICOM parsing/conversion code, the library does the geometry/orientation work;
   - reads back the written file's header with `nibabel` to record its voxel shape and spacing;
   - rejects the output if it isn't 3D/4D.
   A series that fails to convert is skipped (logged by exception type only, never the file path
   or patient data) rather than failing the whole study, *unless* a `required_modalities` series
   (default `T2W`) is among the failures — then the whole conversion is rolled back (partial
   `.nii.gz` outputs deleted) and the request fails.
3. Conversion is CPU/IO-bound, so the endpoint runs it via `run_in_threadpool` — it doesn't block
   the async event loop, and (per benchmarking) concurrent conversions across studies scale
   almost linearly with threads rather than serializing behind the GIL.
4. The study's status moves `UPLOADED → CONVERTING → CONVERTED`; a study already converting is
   rejected with a 409-style `invalid_state` error rather than double-converting.

Docker: `docker build -t aira-backend backend && docker run -p 8000:8000 aira-backend`

## Mobile (`mobile/`)

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (Dart ≥ 3.8).
The Dart sources are in the repo; generate the platform folders once:

```powershell
cd mobile
flutter create . --org com.aira --project-name aira_mobile --platforms android,ios
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator → local backend
```

On a physical device use your computer's LAN IP (e.g. `http://192.168.1.20:8000`); the phone must be on
the same Wi-Fi, and Windows Firewall must allow inbound TCP 8000 for Python. Plain HTTP is
allowed in Android **debug** builds only (`android/app/src/debug/AndroidManifest.xml`); release builds
must point to an HTTPS backend and need `<uses-permission android:name="android.permission.INTERNET"/>`
in `android/app/src/main/AndroidManifest.xml`.

```text
lib/
├── app/            # app widget, router, theme
├── core/           # config, network client, shared widgets
├── data/           # API models and repositories
└── features/
    ├── home/           # Screen 1: new / open / recent studies
    ├── study_import/   # Screen 2: select, upload, convert
    ├── viewer/         # Screen 3: modality tabs, slice navigation
    ├── segmentation/   # Screen 4
    ├── results/        # Screen 5: Original / Mask / Overlay / Features
    ├── export/         # Screen 6
    └── studies/        # shared study providers and scaffold
```

## Data & privacy

Use de-identified test data during development (e.g. public prostate MRI collections such as
PROSTATEx on TCIA). ML API credentials live only in the backend environment, never in the app.

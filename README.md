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

Interactive API docs (off by default; set `DOCS_ENABLED=true`): http://localhost:8000/docs. Configuration: copy `.env.example` to `.env`.

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

### Segmentation model (`app/ml/`, `app/clients/local_model_client.py`)

`POST /api/v1/studies/{id}/segment` runs a PyTorch model **on the server**; the phone only calls the endpoint.
The bundled model is a 3D multi-branch Dense U-Net (T2W branch + ADC/DWI branch) trained on PI-CAI lesion
masks. It needs **T2W, ADC and DWI**, and its validation Dice is only about 0.2, so every result carries an
"experimental" note (`MODEL_NOTE`) that the app shows next to the mask.

| Setting | Default | Purpose |
|---|---|---|
| `MODEL_PATH` | `models/prostate_segmentation.pth` | `state_dict` weights. Not in git; place the file here. |
| `MODEL_NAME`, `MODEL_NOTE` | see `core/config.py` | Name and accuracy caveat returned with each result. |

- **Upload formats:** DICOM (files or a `.zip`), or NIfTI (`.nii`/`.nii.gz`, also inside a `.zip`). A NIfTI file does not
  say what it is, so the file name decides: `_t2w`, `_adc`, and `_hbv` or `_dwi` (for example
  `case_t2w_preprocessed.nii.gz`). Mask files (`mask`, `seg`) and unrecognised names are skipped; a NIfTI study skips the
  DICOM conversion step and needs at least T2W. For best agreement with the training notebook use NIfTI files that are
  already pre-processed the same way.
- **Install:** `pip install torch --index-url https://download.pytorch.org/whl/cpu`, then `pip install -r requirements.txt`.
- **Replace the model:** same architecture, point `MODEL_PATH` at the new weights. A different architecture needs
  its own class beside `prostate_denseunet.py` and a change to `LocalTorchClient._load`.
- **Inputs match the training notebook:** no intensity normalisation, T2W resized to 256x256x32, ADC/DWI to
  88x88x32 (ADC first). The notebook trained on pre-processed PI-CAI data, so raw DICOM only approximates it.
  Array orientation (LPS index order) is an assumption to confirm on real data.

### Database, users and jobs (`app/db/`, `app/services/{storage,users,jobs}.py`)

Study metadata lives in **MySQL**; image and mask files stay on disk under `STORAGE_DIR`.

| Table | Holds |
|---|---|
| `users` | Anonymous device users. Only a SHA-256 hash of the bearer token is stored. |
| `studies`, `series`, `nifti_files` | Study state and the converted volumes (the old `study.json`). |
| `mask_versions` | Segmentation masks: the read-only `ai` version now, corrected versions later (`base_version_id`, `edited_slices`, `created_by`). |
| `jobs` | Segmentation jobs: `queued` → `running` → `completed`/`failed`, with the error and the result mask. |

- **Run with MySQL:** `cp .env.example .env`, set both passwords, put the weights in `backend/models/`, then
  `docker compose up --build`. The API creates the tables at startup (there are no migrations yet: add Alembic
  before the first schema change on data you want to keep).
- **Without Docker:** set `DATABASE_URL=mysql+pymysql://user:password@host:3306/aira`. When it is unset the API
  uses a SQLite file in `STORAGE_DIR`, which is also what the tests use.
- **Users:** the app calls `POST /api/v1/users/anonymous` once, keeps the token in the device keystore and sends
  it as `Authorization: Bearer ...`. Every study, resource and job is scoped to its owner; someone else's id is a 404.
- **Jobs:** `POST /studies/{id}/segment` returns `202` with a job id; poll `GET /jobs/{id}`. One job runs at a time
  on an in-process worker, so run a single API process. Jobs interrupted by a restart are marked failed.
- **Cleanup:** studies untouched for `STUDY_TTL_HOURS` are deleted (rows and files), except those with a running job.

### Mask versions, editing and refinement (`app/api/masks.py`, `app/services/{mask_version,refine}_service.py`)

The AI mask is stored as a read-only version and is never overwritten. A user's correction is saved as a *new*
version (`Corrected v1`, `v2`, ...), made from a copy of the base with the edited slices replaced, using the base's
affine and header. Every mask lives on the T2W array grid, and the MRI slice and the label slice use the same
transform, so they line up pixel for pixel.

| Endpoint | Purpose |
|---|---|
| `GET /api/v1/studies/{id}/mask/versions` | Versions with `name`, labels, volume, edited/refined slices, `slices_with_mask`. |
| `GET /api/v1/masks/{version_id}/slices/{z}` | One mask slice as a lossless 8-bit label PNG at native size (pixel = label). |
| `GET /api/v1/resources/{t2w_id}/slices/{z}?full=true` | The MRI slice at native size (no downscale), for editing. |
| `POST /api/v1/studies/{id}/mask/versions` | Save edited slices (`base_version_id`, files `slice_008.png`, optional `refined_slices`). **409 `VERSION_CONFLICT`** unless the base is the latest version. |
| `POST /api/v1/studies/{id}/mask/refine` | A *proposal* that fits a rough edit to the image edge (random walker in a band + cleanup). Stateless: nothing is stored. 5 s timeout. |
| `GET /api/v1/studies/{id}/mask/compare?a=&b=` | Dice, IoU, volumes (mL), changed voxels. |

Refinement only changes pixels in the neighbourhood of the edit (the changed pixels grown by twice the band width), never
overwrites other labels, and returns an unchanged edit as it is. `REFINE_ENABLED_METHODS` and `REFINE_TIMEOUT_SECONDS`
configure it. Studies, versions and files are removed together by the usual retention cleanup.

Refinement denoises the patch (total variation) before the random walk and uses a high edge sensitivity (`beta` 800). Both were
tuned on synthetic scenes with a known boundary (varied noise, blur, contrast, shape and edit roughness) and checked on held-out
scenes: mean Dice gain +0.07 against +0.03 for the plain walker, and 2% of edits made worse instead of 15%. That is evidence about
the algorithm, not about real lesions: validate on ground-truth masks before relying on it (the deferred M7 benchmark).

### Annotation module: decisions

- **Routes are study-based** (`/studies/{id}/mask/...`), not `result_id`-based: a mask version belongs to a study.
- **No schema change.** Corrections reuse `mask_versions` (`source=manual_correction`, `base_version_id`, `read_only`).
  The AI version is never written; a test checks its file hash and row after saves.
- **No reorientation.** The mask is stored on the T2W array grid and both PNGs use the same transform
  (`flipud(plane.T)`), so MRI and mask align by construction (tested).
- **Stale base = 409.** A save must name the latest version as its base; the app then offers to reload.
- **Refinement is random walker only**, in a band around the edit. The other methods in the plan are for the
  deferred benchmark (M7) and are not shipped. "Keep largest component" is off: lesions can be small and multiple.
- **Edits live in memory** until saved (not kept if the app is killed). History is capped at 50 steps per slice.
- **Input:** 1 finger draws in Edit mode and 2 fingers pan/zoom; once a stylus is seen, the stylus draws and fingers navigate.
- **Not done:** the offline refinement benchmark (needs ground truth), picking a version when exporting, and drawing
  frame-rate numbers (checked by hand on the emulator only). Measured on case 10008: refine round trip about 70 ms.

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

## Security

What is in place, and what you must still do before a public deployment.

**Backend**
- Every study, resource, mask version and job is scoped to its owner (another user's id gives 404). Ids are random 128-bit values.
- Bearer tokens are 256 random bits; only a SHA-256 hash is stored. `DELETE /api/v1/users/me` erases a user's studies, files and account.
- Abuse limits (`.env.example`): registration is rate limited per client address; upload, segmentation, save and refine per user;
  a cap on studies per user, active segmentations per user, files per upload, zip members and decoded volume size.
- Uploads are streamed with a byte budget; client file names and zip paths never reach the disk as paths; PNG and NIfTI
  headers are checked before voxels are read. Model weights load with `weights_only=True`.
- Responses carry `Cache-Control: no-store`, `X-Content-Type-Options`, `X-Frame-Options`. CORS and `/docs` are off by default.
- Errors never include paths or DICOM values; logs hold no patient data. Dependencies are pinned and `pip-audit` runs in CI.
- Docker: non-root, read-only filesystem, no capabilities, no new privileges, health check, MySQL not published, API on
  `127.0.0.1` unless `API_BIND` says otherwise.

**App**
- The token is kept in the Keystore/Keychain (`flutter_secure_storage`). Release builds refuse a non-`https://` `API_BASE_URL`,
  block screenshots and the recent-apps preview (`FLAG_SECURE`), and disable Android backups. Settings has *Delete all my data*.
- Release signing reads `mobile/android/key.properties` (git-ignored); without it the release is signed with the debug key.

**Still your job before going public**
- Put the API behind HTTPS (a reverse proxy such as Caddy or nginx); this service speaks plain HTTP. Set uvicorn `--proxy-headers`
  and a trusted-proxy list so the registration limit sees real client addresses.
- Registration is anonymous. If abuse matters, add device attestation (Play Integrity / App Attest) or real accounts.
- The rate limiter and job queue are per process: run one API process, or move both to Redis and a task queue.
- Tokens do not expire. Add expiry/rotation if the threat model needs it.
- Use de-identified data only; add audit logging, retention policy and a privacy review if real patient data is ever used.

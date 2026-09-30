# Build Specification — Prostate MRI Mobile AI Application

## 1. Project Overview

Build a **mobile application for prostate MRI visualization and AI-assisted segmentation**.

The application does **not develop, train, fine-tune, or modify the ML segmentation model**.

The ML model already exists as a **pre-trained model exposed through an API**. The mobile application integrates:

1. A FastAPI image-processing service for DICOM handling and DICOM → NIfTI conversion.
2. An existing ML Model API that accepts NIfTI, performs model-specific preprocessing + inference, and returns a segmentation mask.
3. A mobile UI for MRI viewing, segmentation visualization, optional feature/radiomic visualization, and result export.

The implementation should clearly separate mobile UI, image-processing backend, and external ML service.

---

# 2. Research Scope

## In scope

- Mobile application development
- Mobile UI/UX
- MRI file loading and upload
- DICOM study handling
- DICOM validation
- DICOM → NIfTI conversion using `dicom2nifti`
- FastAPI backend
- API communication
- Integration with an existing pre-trained segmentation model API
- Sending model-ready NIfTI to the ML API
- Receiving segmentation mask
- Visualization of:
  - original MRI
  - segmentation mask
  - MRI + segmentation overlay
- Slice navigation
- Optional feature/radiomic visualization
- Result export
- Application integration testing
- Basic performance/usability evaluation

## Explicitly out of scope

- ML model training
- ML model architecture development
- ML model fine-tuning
- ML model optimization/compression
- Creating a new segmentation algorithm
- Training a new classifier
- Clinical diagnosis claims

Use wording such as **"AI-assisted segmentation visualization"** rather than claiming autonomous diagnosis.

---

# 3. Target Users

Primary target:
- Radiologist / medical doctor

Secondary target:
- Medical imaging researcher

The app is intended for image review, AI segmentation visualization, research, and result analysis.

---

# 4. High-Level Architecture

```text
                    ┌──────────────────────┐
                    │      MOBILE APP      │
                    │                      │
                    │ • Load MRI           │
                    │ • Upload DICOM       │
                    │ • View MRI           │
                    │ • Run segmentation   │
                    │ • View results       │
                    │ • Export results     │
                    └──────────┬───────────┘
                               │
                         HTTPS / REST
                               │
                               ▼
                 ┌──────────────────────────┐
                 │ IMAGE PROCESSING API      │
                 │ FastAPI                   │
                 │                          │
                 │ • Receive DICOM          │
                 │ • Validate DICOM         │
                 │ • DICOM → NIfTI          │
                 │   using dicom2nifti       │
                 └────────────┬─────────────┘
                              │
                         NIfTI (.nii/.nii.gz)
                              │
                              ▼
                 ┌──────────────────────────┐
                 │   EXISTING ML MODEL API  │
                 │                          │
                 │ • Receive NIfTI          │
                 │ • Model preprocessing    │
                 │ • Existing pre-trained   │
                 │   segmentation model     │
                 │ • Inference              │
                 │ • Return segmentation    │
                 │   mask                   │
                 └────────────┬─────────────┘
                              │
                       Segmentation Mask
                              │
                              ▼
                 ┌──────────────────────────┐
                 │ RESULT PROCESSING        │
                 │                          │
                 │ • Mask handling          │
                 │ • Overlay generation     │
                 │ • Optional features      │
                 │ • Report/export          │
                 └────────────┬─────────────┘
                              │
                              ▼
                    ┌──────────────────────┐
                    │      MOBILE APP      │
                    │                      │
                    │ Original MRI         │
                    │ Segmentation Mask    │
                    │ Overlay              │
                    │ Features (optional)  │
                    │ Export / Report      │
                    └──────────────────────┘
```

---

# 5. Processing Responsibilities

## Mobile App

Handle:

- File selection
- User interaction
- Upload
- Study/session display
- MRI visualization
- Segmentation visualization
- Slice navigation
- Overlay opacity
- Result display
- Optional feature display
- Export/share

Do **not** require the mobile device to perform heavy DICOM conversion.

## Image Processing API

Handle:

1. Receiving DICOM files
2. Basic validation
3. DICOM → NIfTI conversion using `dicom2nifti`
4. Returning model-ready NIfTI or a secure job/result reference

Do not implement a custom DICOM-to-NIfTI converter.

## ML Model API

This is an existing/external service.

Handle:

1. Receiving NIfTI
2. Model-specific preprocessing
3. Existing pre-trained model inference
4. Returning segmentation mask

Do not duplicate model preprocessing in the mobile app unless the actual ML API contract explicitly requires it.

---

# 6. Recommended Technology Stack

## Mobile

Preferred:
- Flutter
- Dart

Architecture should separate:
- UI
- State management
- API client
- Data models
- Image viewer
- Result visualization

## Backend

- Python 3.10+
- FastAPI
- Uvicorn
- `dicom2nifti`
- `pydicom`
- `nibabel`
- `numpy`

Use `SimpleITK` only when justified by an actual backend requirement.

## ML API Client

Prefer:

```text
Mobile → FastAPI Image API → ML Model API
```

The mobile app should not need to know the internal details of the ML service.

---

# 7. MRI Input

Support prostate MRI modalities such as:

- T2W
- DWI
- ADC

Design the input model so modality combinations are configurable.

Examples:

```text
T2W
T2W + DWI
T2W + ADC
T2W + DWI + ADC
```

Do not assume that every study contains every modality.

The exact combination should be controlled by model/API configuration.

---

# 8. Data Flow

## Upload

```text
User selects DICOM study
        ↓
Mobile selects files
        ↓
POST /api/v1/studies/upload
        ↓
FastAPI receives DICOM
        ↓
Validate DICOM
        ↓
dicom2nifti conversion
        ↓
NIfTI generated
        ↓
Store temporary processing state
        ↓
Return study/job ID
```

## Segmentation

```text
Mobile requests segmentation
        ↓
FastAPI loads model-ready NIfTI
        ↓
FastAPI calls ML Model API
        ↓
ML service performs preprocessing
        ↓
Existing pre-trained model runs inference
        ↓
Segmentation mask returned
        ↓
FastAPI stores result/reference
        ↓
Mobile retrieves result
```

## Visualization

```text
Original MRI
     +
Segmentation Mask
     ↓
Overlay rendering
     ↓
Slice navigation
     ↓
User reviews result
```

---

# 9. Proposed REST API

## Health

```http
GET /health
```

```json
{
  "status": "ok"
}
```

## Upload Study

```http
POST /api/v1/studies/upload
Content-Type: multipart/form-data
```

Response:

```json
{
  "study_id": "study_123",
  "status": "uploaded",
  "modalities": ["T2W", "DWI", "ADC"]
}
```

## Convert Study

```http
POST /api/v1/studies/{study_id}/convert
```

Response:

```json
{
  "study_id": "study_123",
  "status": "converted",
  "nifti_files": [
    {
      "modality": "T2W",
      "resource_id": "nifti_t2w_001"
    }
  ]
}
```

Never expose raw server filesystem paths to the mobile client.

## Run Segmentation

```http
POST /api/v1/studies/{study_id}/segment
```

Response:

```json
{
  "study_id": "study_123",
  "job_id": "job_456",
  "status": "submitted"
}
```

For asynchronous processing:

```http
GET /api/v1/jobs/{job_id}
```

Example:

```json
{
  "job_id": "job_456",
  "status": "completed",
  "result_id": "result_789"
}
```

## Get Results

```http
GET /api/v1/results/{result_id}
```

Example:

```json
{
  "study_id": "study_123",
  "segmentation_mask": {
    "format": "nifti",
    "resource_id": "mask_001"
  },
  "overlay": {
    "format": "png",
    "resource_id": "overlay_001"
  },
  "features": null
}
```

Adapt all contracts to the real ML API when its documentation is available.

---

# 10. ML Model Adapter

Do not tightly couple business logic to the specific external ML service.

Suggested backend structure:

```text
backend/
├── app/
│   ├── api/
│   ├── services/
│   │   ├── dicom_service.py
│   │   ├── nifti_service.py
│   │   ├── segmentation_service.py
│   │   └── feature_service.py
│   ├── clients/
│   │   └── ml_model_client.py
│   ├── models/
│   ├── core/
│   └── main.py
├── tests/
├── requirements.txt
└── Dockerfile
```

Conceptual interface:

```python
class MLModelClient:
    async def segment(self, nifti_files: list[str]) -> dict:
        ...
```

The rest of the backend should call this interface.

---

# 11. Result Visualization

The mobile app should provide:

## Original MRI

Display original image/slices.

## Segmentation Mask

Display returned mask separately.

## Overlay

```text
Original MRI
      +
Segmentation Mask
      =
Overlay
```

Required controls:

- Slice slider
- Previous/next slice
- Zoom
- Pan
- Overlay opacity
- Show/hide mask
- Compare original vs segmentation

The output should be presented as an AI-assisted image analysis result, not as an autonomous diagnosis.

---

# 12. Optional Feature Extraction

Feature extraction is optional and must remain modular.

Concept:

```text
Segmentation Mask
       ↓
Segmented ROI
       ↓
Optional Feature Extraction
       ↓
Shape / Intensity / Texture
       ↓
Display / Export
```

Possible UI:

```text
Features
[✓] Shape
[✓] Intensity
[ ] Texture
```

Do not implement a full radiomics pipeline until the exact feature set and library are defined.

---

# 13. Mobile Screens

## Screen 1 — Home

- New study
- Open study
- Recent studies

## Screen 2 — Study Import

- Select DICOM folder/files
- Show selected files
- Upload
- Upload progress

## Screen 3 — MRI Viewer

- T2W
- DWI
- ADC
- Slice navigation

## Screen 4 — Segmentation

- Run segmentation
- Processing status
- Completion/error state

## Screen 5 — Result Viewer

Tabs:

```text
Original
Mask
Overlay
Features
```

## Screen 6 — Export

Possible outputs:
- Overlay PNG
- Report
- Mask NIfTI
- Features CSV/JSON
- Other outputs supported by the implementation

---

# 14. Error Handling

Handle:

- Invalid DICOM
- Unsupported modality
- Missing required modality
- DICOM conversion failure
- Network failure
- ML API unavailable
- ML inference timeout
- Invalid ML response
- Segmentation mask format mismatch
- Large-file upload failure

Never expose raw stack traces to users.

Use clear messages such as:

```text
Unable to convert the selected MRI study.
Please verify that the DICOM files are complete and valid.
```

---

# 15. Security / Privacy

Medical imaging may contain patient identifiers.

Use:

- HTTPS
- Minimal logging
- No unnecessary patient identifiers in logs
- Temporary storage for uploaded files
- Cleanup of temporary files
- Server-side secrets
- No API credentials embedded in the mobile application
- Authentication/authorization where required
- De-identified test data during development

---

# 16. Backend Starting Resource Target

For the image-processing backend prototype:

- 4 vCPU
- 8 GB RAM
- ~100 GB SSD
- No GPU required

The backend is mainly responsible for:

- DICOM receiving
- validation
- DICOM → NIfTI conversion
- API orchestration

ML inference is handled by the separate ML Model API.

Treat these as starting infrastructure targets, not hard requirements. Validate them using representative prostate MRI studies.

---

# 17. Evaluation

## Functional

Verify:

- DICOM upload
- DICOM validation
- DICOM → NIfTI conversion
- ML API communication
- Segmentation response
- Mask display
- Overlay display
- Export

## Performance

Measure:

- DICOM upload time
- DICOM → NIfTI conversion time
- ML API response time
- End-to-end processing time
- Mobile rendering responsiveness
- Backend peak RAM
- Backend CPU utilization
- Network transfer size

## Usability

Evaluate:

- Navigation
- Result readability
- Segmentation visibility
- Original vs overlay comparison
- Export workflow

Do not claim clinical diagnostic accuracy unless a separate clinically validated study is performed.

---

# 18. Development Strategy

## Phase 1 — Skeleton

Create:
- Flutter mobile app
- FastAPI backend
- `/health`
- Basic mobile → backend communication

## Phase 2 — DICOM Handling

Implement:
- DICOM file selection
- Multipart upload
- Validation
- `dicom2nifti` conversion
- Temporary NIfTI handling

## Phase 3 — ML API Integration

Implement:
- ML API client
- NIfTI upload
- Timeout/retry handling
- Segmentation response parsing

Use a **mock ML service** until the real ML API contract is known.

## Phase 4 — Visualization

Implement:
- MRI viewer
- Mask viewer
- Overlay
- Slice navigation
- Opacity control

## Phase 5 — Optional Features

Add:
- Feature extraction
- Feature display
- Export/report

## Phase 6 — Testing

Add:
- Backend unit tests
- API integration tests
- Mobile UI tests
- End-to-end test with representative prostate MRI data

## Phase 7 — Deployment

Containerize services and document:
- Environment variables
- API URLs
- Storage settings
- Deployment steps

---

# 19. First Vertical Slice

Do **not** build the entire system at once.

First milestone:

```text
Flutter Mobile App
       ↓
Upload DICOM
       ↓
FastAPI
       ↓
dicom2nifti
       ↓
NIfTI generated
       ↓
Mock ML API
       ↓
Mock segmentation mask
       ↓
FastAPI
       ↓
Flutter
       ↓
Display MRI + Mask Overlay
```

The first working feature should prove:

> Upload one representative DICOM prostate MRI study from the mobile app, convert it to NIfTI on the FastAPI backend using `dicom2nifti`, send the NIfTI to a mock ML API, receive a segmentation mask, and display the result as an overlay in the mobile app.

After that works, replace the mock ML API with the real pre-trained ML Model API.

---

# 20. Final System Flow

```text
DICOM MRI
   ↓
Mobile Upload
   ↓
FastAPI
   ↓
DICOM Validation
   ↓
dicom2nifti
   ↓
NIfTI
   ↓
Existing ML Model API
   ↓
Model Preprocessing
   ↓
Segmentation Inference
   ↓
Segmentation Mask
   ↓
Result Processing
   ↓
Mobile Visualization
   ↓
Overlay / Optional Features / Export
```

## Core Research Contribution

The contribution is the **application and system integration pipeline**, not development of the underlying ML segmentation model.

Use this distinction consistently throughout the codebase, documentation, thesis, and presentation.

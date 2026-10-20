import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)


class AppError(Exception):
    """An error whose message is safe to show to the end user."""

    def __init__(
        self, code: str, message: str, status_code: int = 400, headers: dict[str, str] | None = None
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.headers = headers


def invalid_dicom() -> AppError:
    return AppError(
        "INVALID_DICOM",
        "The selected files are not valid DICOM images. "
        "Please verify that the DICOM files are complete and valid.",
    )


def no_dicom_found() -> AppError:
    return AppError(
        "NO_DICOM_FOUND",
        "No DICOM images were found in the upload. Please select the files of an MRI study.",
    )


def unsupported_modality() -> AppError:
    return AppError(
        "UNSUPPORTED_MODALITY",
        "None of the uploaded series is a supported MRI sequence (T2W, DWI or ADC).",
        422,
    )


def missing_required_modality(missing: list[str]) -> AppError:
    return AppError(
        "MISSING_REQUIRED_MODALITY",
        f"The study is missing required MRI sequence(s): {', '.join(missing)}.",
        422,
    )


def conversion_failed() -> AppError:
    return AppError(
        "CONVERSION_FAILED",
        "Unable to convert the selected MRI study. "
        "Please verify that the DICOM files are complete and valid.",
        422,
    )


def invalid_image() -> AppError:
    return AppError(
        "INVALID_IMAGE",
        "One of the selected NIfTI files could not be read. Please check that the file is complete.",
        400,
    )


def upload_too_large(limit_mb: int) -> AppError:
    return AppError("UPLOAD_TOO_LARGE", f"The upload exceeds the {limit_mb} MB limit.", 413)


def study_not_found() -> AppError:
    return AppError("STUDY_NOT_FOUND", "The requested study was not found or has expired.", 404)


def resource_not_found() -> AppError:
    return AppError("RESOURCE_NOT_FOUND", "The requested resource was not found or has expired.", 404)


def invalid_slice_index() -> AppError:
    return AppError("INVALID_SLICE_INDEX", "The requested slice is out of range.", 400)


def unsupported_volume() -> AppError:
    return AppError("UNSUPPORTED_VOLUME", "This NIfTI volume cannot be displayed.", 422)


def unauthorized() -> AppError:
    return AppError("UNAUTHORIZED", "Authentication is required. Please restart the app and try again.", 401)


def job_not_found() -> AppError:
    return AppError("JOB_NOT_FOUND", "The requested job was not found.", 404)


def version_conflict() -> AppError:
    return AppError(
        "VERSION_CONFLICT",
        "This mask has newer changes. Reload it before saving, so nothing is overwritten.",
        409,
    )


def invalid_mask_slice(message: str) -> AppError:
    return AppError("INVALID_MASK_SLICE", message, 422)


def refine_timeout() -> AppError:
    return AppError("REFINE_TIMEOUT", "Refinement took too long. Your edit is unchanged.", 504)


def refine_failed() -> AppError:
    return AppError("REFINE_FAILED", "Refinement could not be completed. Your edit is unchanged.", 422)


def model_unavailable() -> AppError:
    return AppError("MODEL_UNAVAILABLE", "The segmentation model is not available on the server.", 503)


def segmentation_failed() -> AppError:
    return AppError(
        "SEGMENTATION_FAILED",
        "Segmentation could not be completed for this study. Please try again or use another study.",
        422,
    )


def too_many_requests(retry_after: int) -> AppError:
    return AppError(
        "TOO_MANY_REQUESTS",
        "Too many requests. Please wait a moment and try again.",
        429,
        {"Retry-After": str(retry_after)},
    )


def quota_exceeded(message: str) -> AppError:
    return AppError("QUOTA_EXCEEDED", message, 429)


def invalid_state(message: str) -> AppError:
    return AppError("INVALID_STATE", message, 409)


def _error_body(code: str, message: str) -> dict:
    return {"error": {"code": code, "message": message}}


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code, content=_error_body(exc.code, exc.message), headers=exc.headers
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content=_error_body("INVALID_REQUEST", "The request is missing required data."),
        )

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception) -> JSONResponse:
        # Log the type only: exception text may contain file paths or DICOM header values.
        logger.error("Unhandled error: %s", type(exc).__name__)
        return JSONResponse(
            status_code=500,
            content=_error_body("INTERNAL_ERROR", "An unexpected error occurred. Please try again."),
        )

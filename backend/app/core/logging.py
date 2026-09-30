import logging


def configure_logging(level: int = logging.INFO) -> None:
    """Minimal logging. Never log patient identifiers, DICOM header values or file names."""
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

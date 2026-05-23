"""Storage integration behavior tests."""

from __future__ import annotations

import pytest
from app.integrations.storage import LocalStorageService, StorageNotFoundError, StorageService


def test_storage_service_constructor_does_not_resolve_adc(
    monkeypatch,
) -> None:
    calls: list[str] = []

    class _FakeClient:
        def __init__(self) -> None:
            calls.append("client")

        def bucket(self, bucket_name: str) -> object:
            calls.append(bucket_name)
            return object()

    monkeypatch.setattr("app.integrations.storage.storage.Client", _FakeClient)

    StorageService("stima-test-bucket")

    if calls:
        raise AssertionError(f"StorageService constructor should be lazy, but touched ADC: {calls}")


def test_local_storage_round_trips_profile_logo_and_pdf_artifact_paths(tmp_path) -> None:
    storage_service = LocalStorageService(root=str(tmp_path / "objects"))

    logo_path = storage_service.upload(
        prefix="logos/user-1",
        filename="logo",
        data=b"logo-bytes",
        content_type="image/png",
    )
    pdf_path = storage_service.upload(
        prefix="pdf-artifacts/quotes/quote-1",
        filename="artifact.pdf",
        data=b"pdf-bytes",
        content_type="application/pdf",
    )

    assert logo_path == "logos/user-1/logo"  # nosec B101 - pytest assertion
    assert pdf_path == "pdf-artifacts/quotes/quote-1/artifact.pdf"  # nosec B101 - pytest assertion
    assert storage_service.fetch_bytes(logo_path) == b"logo-bytes"  # nosec B101 - pytest assertion
    assert storage_service.fetch_bytes(pdf_path) == b"pdf-bytes"  # nosec B101 - pytest assertion

    storage_service.delete(logo_path)
    storage_service.delete(logo_path)

    with pytest.raises(StorageNotFoundError):
        storage_service.fetch_bytes(logo_path)
    assert storage_service.fetch_bytes(pdf_path) == b"pdf-bytes"  # nosec B101 - pytest assertion


def test_local_storage_creates_root_and_verifies_writable(tmp_path) -> None:
    root = tmp_path / "missing" / "storage"

    LocalStorageService(root=str(root))

    assert root.is_dir()  # nosec B101 - pytest assertion


def test_local_storage_fetch_missing_file_raises_storage_not_found(tmp_path) -> None:
    storage_service = LocalStorageService(root=str(tmp_path))

    with pytest.raises(StorageNotFoundError):
        storage_service.fetch_bytes("pdf-artifacts/quotes/missing.pdf")


@pytest.mark.parametrize(
    "object_path",
    [
        "../secret",
        "logos/../secret",
        "/absolute/path",
        r"\absolute\path",
        r"logos\..\secret",
        r"C:\temp\secret",
        "C:/temp/secret",
    ],
)
def test_local_storage_rejects_traversal_and_escape_paths(tmp_path, object_path: str) -> None:
    storage_service = LocalStorageService(root=str(tmp_path))

    with pytest.raises(ValueError):
        storage_service.fetch_bytes(object_path)


@pytest.mark.parametrize(
    ("prefix", "filename"),
    [
        ("logos/..", "logo"),
        ("/absolute", "logo"),
        (r"\absolute", "logo"),
        (r"logos\..\secret", "logo"),
        ("logos", r"C:\temp\logo"),
        ("logos", "C:/temp/logo"),
        ("logos", "/logo"),
    ],
)
def test_local_storage_upload_rejects_unsafe_prefix_or_filename(
    tmp_path,
    prefix: str,
    filename: str,
) -> None:
    storage_service = LocalStorageService(root=str(tmp_path))

    with pytest.raises(ValueError):
        storage_service.upload(
            prefix=prefix,
            filename=filename,
            data=b"unsafe",
            content_type="application/octet-stream",
        )

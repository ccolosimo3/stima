"""Private object storage integrations."""

from __future__ import annotations

from functools import cached_property
from pathlib import Path, PureWindowsPath
from tempfile import TemporaryFile
from typing import Protocol

from google.api_core.exceptions import NotFound
from google.cloud import storage  # type: ignore[import-untyped]


class StorageNotFoundError(Exception):
    """Raised when a requested storage object does not exist."""


class StorageReaderProtocol(Protocol):
    """Structural protocol for read-only storage access."""

    def fetch_bytes(self, object_path: str) -> bytes: ...


class StorageServiceProtocol(StorageReaderProtocol, Protocol):
    """Structural protocol for full storage access."""

    def upload(
        self,
        *,
        prefix: str,
        filename: str,
        data: bytes,
        content_type: str,
    ) -> str: ...

    def delete(self, object_path: str) -> None: ...


class StorageService:
    """Upload, fetch, and delete objects in one configured private bucket."""

    def __init__(self, bucket_name: str) -> None:
        self._bucket_name = bucket_name

    def upload(
        self,
        *,
        prefix: str,
        filename: str,
        data: bytes,
        content_type: str,
    ) -> str:
        """Write bytes to a prefixed object path and return that path."""
        object_path = _build_object_path(prefix=prefix, filename=filename)
        blob = self._bucket.blob(object_path)
        blob.upload_from_string(data, content_type=content_type)
        return object_path

    def delete(self, object_path: str) -> None:
        """Delete an object, treating a missing object as an idempotent no-op."""
        blob = self._bucket.blob(object_path)
        try:
            blob.delete()
        except NotFound:
            return

    def fetch_bytes(self, object_path: str) -> bytes:
        """Read raw bytes for one object path."""
        blob = self._bucket.blob(object_path)
        try:
            return bytes(blob.download_as_bytes())
        except NotFound as exc:
            raise StorageNotFoundError(object_path) from exc

    @cached_property
    def _bucket(self):  # type: ignore[no-untyped-def]
        """Resolve the bucket lazily and reuse it across storage operations."""
        return storage.Client().bucket(self._bucket_name)


class LocalStorageService:
    """Upload, fetch, and delete private objects under a local root directory."""

    def __init__(self, root: str) -> None:
        self._root = Path(root).expanduser()
        self._ensure_root_writable()

    def upload(
        self,
        *,
        prefix: str,
        filename: str,
        data: bytes,
        content_type: str,
    ) -> str:
        """Write bytes to a prefixed object path and return that relative path."""
        del content_type
        _validate_upload_path_component(prefix)
        _validate_upload_path_component(filename)
        object_path = _validate_relative_object_path(
            _build_object_path(prefix=prefix, filename=filename)
        )
        local_path = self._resolve_local_path(object_path)
        local_path.parent.mkdir(parents=True, exist_ok=True)
        local_path.write_bytes(data)
        return object_path

    def delete(self, object_path: str) -> None:
        """Delete an object, treating a missing object as an idempotent no-op."""
        local_path = self._resolve_local_path(_validate_relative_object_path(object_path))
        try:
            local_path.unlink()
        except FileNotFoundError:
            return

    def fetch_bytes(self, object_path: str) -> bytes:
        """Read raw bytes for one object path."""
        local_path = self._resolve_local_path(_validate_relative_object_path(object_path))
        try:
            return local_path.read_bytes()
        except FileNotFoundError as exc:
            raise StorageNotFoundError(object_path) from exc

    def _ensure_root_writable(self) -> None:
        self._root.mkdir(parents=True, exist_ok=True)
        if not self._root.is_dir():
            raise NotADirectoryError(str(self._root))
        with TemporaryFile(dir=self._root):
            pass
        self._root = self._root.resolve()

    def _resolve_local_path(self, object_path: str) -> Path:
        local_path = (self._root / object_path).resolve()
        try:
            local_path.relative_to(self._root)
        except ValueError as exc:
            raise ValueError("Storage object path escapes LOCAL_STORAGE_ROOT") from exc
        return local_path


def _build_object_path(*, prefix: str, filename: str) -> str:
    normalized_prefix = prefix.strip("/")
    normalized_filename = filename.lstrip("/")
    if not normalized_prefix:
        return normalized_filename
    return f"{normalized_prefix}/{normalized_filename}"


def _validate_relative_object_path(object_path: str) -> str:
    normalized_path = object_path.strip()
    if not normalized_path:
        raise ValueError("Storage object path must be non-empty")
    if "\\" in normalized_path:
        raise ValueError("Storage object path must use forward slashes")
    if normalized_path.startswith("/"):
        raise ValueError("Storage object path must be relative")
    if PureWindowsPath(normalized_path).drive:
        raise ValueError("Storage object path must not include a Windows drive prefix")

    path_parts = normalized_path.split("/")
    if any(part in {"", ".", ".."} for part in path_parts):
        raise ValueError("Storage object path must not contain traversal segments")
    return normalized_path


def _validate_upload_path_component(value: str) -> None:
    normalized_value = value.strip()
    if "\\" in normalized_value:
        raise ValueError("Storage object paths must use forward slashes")
    if normalized_value.startswith("/"):
        raise ValueError("Storage object paths must be relative")
    if PureWindowsPath(normalized_value).drive:
        raise ValueError("Storage object paths must not include a Windows drive prefix")
    if any(part in {".", ".."} for part in normalized_value.split("/")):
        raise ValueError("Storage object paths must not contain traversal segments")

"""Shared dependency singleton tests."""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from app.core.config import get_settings
from app.integrations.storage import LocalStorageService, StorageService
from app.shared import dependencies


@pytest.fixture(autouse=True)
def _reset_dependency_caches(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.setenv("SECRET_KEY", "test-secret-key-that-is-at-least-32-bytes")
    monkeypatch.setenv("GCS_BUCKET_NAME", "stima-test-logos")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anthropic-test")
    monkeypatch.setenv("OPENAI_API_KEY", "openai-test")
    monkeypatch.setenv("EXTRACTION_MODEL", "claude-test")
    monkeypatch.setenv("EXTRACTION_FALLBACK_MODEL", "claude-fallback-test")
    monkeypatch.setenv("EXTRACTION_PRIMARY_PROMPT_VARIANT", "primary_v1")
    monkeypatch.setenv("EXTRACTION_FALLBACK_PROMPT_VARIANT", "fallback_v1")
    monkeypatch.setenv("TRANSCRIPTION_MODEL", "whisper-test")
    monkeypatch.setenv("PROVIDER_REQUEST_TIMEOUT_SECONDS", "21.5")
    monkeypatch.setenv("PROVIDER_MAX_RETRIES", "4")
    get_settings.cache_clear()
    dependencies._build_storage_service.cache_clear()  # noqa: SLF001
    dependencies.get_extraction_integration.cache_clear()
    dependencies.get_transcription_integration.cache_clear()
    yield
    dependencies._build_storage_service.cache_clear()  # noqa: SLF001
    dependencies.get_extraction_integration.cache_clear()
    dependencies.get_transcription_integration.cache_clear()
    get_settings.cache_clear()


def test_get_extraction_integration_returns_singleton() -> None:
    first = dependencies.get_extraction_integration()
    second = dependencies.get_extraction_integration()

    assert first is second


def test_get_transcription_integration_returns_singleton() -> None:
    first = dependencies.get_transcription_integration()
    second = dependencies.get_transcription_integration()

    assert first is second


def test_get_extraction_integration_applies_fallback_settings() -> None:
    integration = dependencies.get_extraction_integration()

    assert integration._primary_model == "claude-test"  # noqa: SLF001
    assert integration._fallback_model == "claude-fallback-test"  # noqa: SLF001
    assert integration._primary_prompt_variant == "primary_v1"  # noqa: SLF001
    assert integration._fallback_prompt_variant == "fallback_v1"  # noqa: SLF001


def test_get_extraction_service_reuses_provider_singletons() -> None:
    first = dependencies.get_extraction_service()
    second = dependencies.get_extraction_service()

    assert first._extraction is second._extraction  # noqa: SLF001
    assert first._transcription is second._transcription  # noqa: SLF001


def test_get_storage_service_cache_keys_backend_and_local_root(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path,
) -> None:
    monkeypatch.setenv("STORAGE_BACKEND", "local")
    monkeypatch.setenv("LOCAL_STORAGE_ROOT", str(tmp_path / "one"))
    monkeypatch.delenv("GCS_BUCKET_NAME", raising=False)
    get_settings.cache_clear()

    first = dependencies.get_storage_service()

    monkeypatch.setenv("LOCAL_STORAGE_ROOT", str(tmp_path / "two"))
    get_settings.cache_clear()
    second = dependencies.get_storage_service()

    monkeypatch.setenv("STORAGE_BACKEND", "gcs")
    monkeypatch.setenv("GCS_BUCKET_NAME", "stima-test-logos")
    get_settings.cache_clear()
    third = dependencies.get_storage_service()

    assert isinstance(first, LocalStorageService)
    assert isinstance(second, LocalStorageService)
    assert isinstance(third, StorageService)
    assert first is not second
    assert third is not first

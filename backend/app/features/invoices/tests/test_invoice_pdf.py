"""Invoice PDF generation endpoint behavior tests."""

from __future__ import annotations

from typing import cast

import pytest
from app.core.config import get_settings
from app.features.jobs.models import JobStatus
from app.features.quotes.models import QuoteStatus
from app.features.quotes.tests import test_pdf as quote_pdf_tests
from app.main import app
from app.shared.dependencies import get_inline_job_runner
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

pytestmark = pytest.mark.asyncio

_reset_rate_limit_state = quote_pdf_tests._reset_rate_limit_state
_storage_service_dependency = quote_pdf_tests._storage_service_dependency
_arq_pool_dependency = quote_pdf_tests._arq_pool_dependency
_override_quote_service_dependency = quote_pdf_tests._override_quote_service_dependency


async def test_generate_invoice_pdf_inline_runs_without_arq_and_returns_ready(
    client: AsyncClient,
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
    _arq_pool_dependency: quote_pdf_tests._MockArqPool,
    _storage_service_dependency: quote_pdf_tests._FakeStorageService,
    _override_quote_service_dependency: quote_pdf_tests._ConfigurablePdfIntegration,
) -> None:
    monkeypatch.setenv("JOB_EXECUTION_MODE", "inline")
    get_settings.cache_clear()
    quote_pdf_tests._install_inline_pdf_runner(
        db_session,
        pdf_integration=_override_quote_service_dependency,
        storage_service=_storage_service_dependency,
    )
    try:
        csrf_token = await quote_pdf_tests._register_and_login(
            client,
            quote_pdf_tests._credentials(),
        )
        customer_id = await quote_pdf_tests._create_customer(client, csrf_token)
        quote = await quote_pdf_tests._create_quote(client, csrf_token, customer_id)
        await quote_pdf_tests._set_quote_status(db_session, quote["id"], QuoteStatus.APPROVED)
        convert_response = await client.post(
            f"/api/quotes/{quote['id']}/convert-to-invoice",
            headers={"X-CSRF-Token": csrf_token},
        )
        assert convert_response.status_code == 201
        invoice_id = convert_response.json()["id"]

        response = await client.post(
            f"/api/invoices/{invoice_id}/pdf",
            headers={"X-CSRF-Token": csrf_token},
        )
    finally:
        app.dependency_overrides.pop(get_inline_job_runner, None)
        get_settings.cache_clear()

    payload = cast(quote_pdf_tests._PdfJobResponse, response.json())
    assert response.status_code == 202
    assert payload["job_type"] == "pdf"
    assert payload["status"] == JobStatus.SUCCESS.value
    assert payload["document_id"] == invoice_id
    assert payload["attempts"] == 1
    assert payload["terminal_error"] is None
    assert _arq_pool_dependency.calls == []

    artifact = await client.get(f"/api/invoices/{invoice_id}/pdf")
    assert artifact.status_code == 200
    assert artifact.content == b"PDF for I-001"
    assert _override_quote_service_dependency.last_context is not None
    assert _override_quote_service_dependency.last_context.doc_label == "Invoice"

"""Inline durable job runner tests."""

from __future__ import annotations

import sys
from typing import Any
from uuid import UUID, uuid4

import pytest
from app.features.auth.models import User
from app.features.jobs.models import JobRecord, JobStatus, JobType
from app.features.jobs.repository import JobRepository
from app.worker import inline as inline_module
from app.worker.inline import InlineJobRunner
from app.worker.runtime import (
    TERMINAL_ERROR_RETRY_EXHAUSTED,
    RetryableJobError,
    process_job,
)
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

pytestmark = pytest.mark.asyncio


async def test_inline_runner_does_not_import_arq_worker() -> None:
    assert "app.worker.arq_worker" not in sys.modules  # nosec B101 - pytest assertion


async def test_inline_runner_uses_single_attempt_terminal_failure(
    db_session: AsyncSession,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    user = await _seed_user(db_session)
    repository = JobRepository(db_session)
    record = await repository.create(user_id=user.id, job_type=JobType.PDF)
    await db_session.commit()

    async def _retryable_pdf_handler(ctx: dict[str, Any], job_id: str) -> None:
        await process_job(
            ctx,
            job_id=UUID(job_id),
            job_type=JobType.PDF,
            handler=_retryable_failure_handler,
        )

    monkeypatch.setattr(
        inline_module,
        "_job_handlers",
        lambda: {inline_module.PDF_JOB_NAME: _retryable_pdf_handler},
    )

    await InlineJobRunner(session_maker=_session_maker(db_session)).run(
        inline_module.PDF_JOB_NAME,
        record.id,
    )

    refreshed = await _load_job_record(db_session, record.id)
    assert refreshed is not None  # nosec B101 - pytest assertion
    assert refreshed.status == JobStatus.TERMINAL  # nosec B101 - pytest assertion
    assert refreshed.attempts == 1  # nosec B101 - pytest assertion
    assert refreshed.terminal_error == TERMINAL_ERROR_RETRY_EXHAUSTED  # nosec B101 - pytest


async def _retryable_failure_handler() -> None:
    raise RetryableJobError("temporary upstream outage")


async def _seed_user(db_session: AsyncSession) -> User:
    user = User(
        id=uuid4(),
        email=f"{uuid4().hex}@example.com",
        password_hash="hashed-password",  # nosec B106 - test-only stub value
    )
    db_session.add(user)
    await db_session.flush()
    return user


def _session_maker(db_session: AsyncSession) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(
        bind=db_session.bind,
        class_=AsyncSession,
        expire_on_commit=False,
    )


async def _load_job_record(db_session: AsyncSession, job_id: UUID) -> JobRecord | None:
    async with _session_maker(db_session)() as session:
        repository = JobRepository(session)
        return await repository.get_by_id(job_id)

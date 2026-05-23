"""Web-safe inline execution for selected durable jobs."""

from __future__ import annotations

import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from arq.worker import Retry
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.database import get_session_maker
from app.features.jobs.models import JobType
from app.features.jobs.repository import JobRepository
from app.worker.runtime import (
    DEFAULT_RETRY_BASE_SECONDS,
    DEFAULT_RETRY_JITTER_SECONDS,
    TERMINAL_ERROR_RETRY_EXHAUSTED,
    NonRetryableJobError,
    WorkerRuntimeSettings,
)

LOGGER = logging.getLogger(__name__)
INLINE_MAX_TRIES = 1
PDF_JOB_NAME = "jobs.pdf"
EMAIL_JOB_NAME = "jobs.email"

_InlineHandler = Callable[[dict[str, Any], str], Awaitable[None]]
_JOB_TYPES: dict[str, JobType] = {
    PDF_JOB_NAME: JobType.PDF,
    EMAIL_JOB_NAME: JobType.EMAIL,
}


@dataclass(slots=True)
class InlineJobRunner:
    """Run worker-registered jobs in-process without importing ARQ worker settings."""

    session_maker: async_sessionmaker[AsyncSession] | None = None
    pdf_integration: Any | None = None
    storage_service: Any | None = None
    email_service: Any | None = None

    async def run(self, job_name: str, job_id: UUID) -> None:
        """Run one supported job once and leave terminal failures in durable state."""
        handler = _job_handlers().get(job_name)
        if handler is None:
            raise ValueError(f"Inline execution is not supported for job {job_name!r}")

        ctx = self._build_context()
        try:
            await handler(ctx, str(job_id))
        except Retry:
            LOGGER.warning(
                "Inline job leaked ARQ retry; finalizing as terminal failure job_id=%s job_name=%s",
                job_id,
                job_name,
            )
            await self._mark_retry_leak_terminal(job_id=job_id, job_type=_JOB_TYPES[job_name])
        except NonRetryableJobError:
            LOGGER.info(
                "Inline job finished with terminal durable failure job_id=%s job_name=%s",
                job_id,
                job_name,
            )

    def _build_context(self) -> dict[str, Any]:
        ctx: dict[str, Any] = {
            "job_try": 1,
            "worker_runtime": self._build_runtime(),
        }
        if self.pdf_integration is not None:
            ctx["pdf_integration"] = self.pdf_integration
        if self.storage_service is not None:
            ctx["storage_service"] = self.storage_service
        if self.email_service is not None:
            ctx["email_service"] = self.email_service
        return ctx

    def _build_runtime(self) -> WorkerRuntimeSettings:
        return WorkerRuntimeSettings(
            session_maker=self.session_maker or get_session_maker(),
            max_tries=INLINE_MAX_TRIES,
            retry_base_seconds=DEFAULT_RETRY_BASE_SECONDS,
            retry_jitter_seconds=DEFAULT_RETRY_JITTER_SECONDS,
        )

    async def _mark_retry_leak_terminal(self, *, job_id: UUID, job_type: JobType) -> None:
        runtime = self._build_runtime()
        async with runtime.session_maker() as session:
            repository = JobRepository(session)
            await repository.set_terminal(
                job_id,
                reason=TERMINAL_ERROR_RETRY_EXHAUSTED,
                expected_job_type=job_type,
            )
            await session.commit()


def _job_handlers() -> dict[str, _InlineHandler]:
    from app.worker.job_registry import email_job, pdf_job

    return {
        PDF_JOB_NAME: pdf_job,
        EMAIL_JOB_NAME: email_job,
    }

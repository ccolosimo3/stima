# Historical backlog reconciliation

Snapshot: 2026-10-31. Scope: every issue still open from before the Flutter restart—eleven issues, #595, #603, #604, #616, #618, #668 and #695–#699. Source inspection used baseline `f0f4c192c6f5a6a321483597ac9392be95711f22`, complete issue bodies, child states and selected merged-PR history. Later reviewed Flutter/audio/test work is separately identified by the [shared handoff](https://github.com/ccolosimo3/stima/issues/723#issuecomment-6548090628).

This is a dated decision/evidence record. Source/test presence establishes available behavior or proof, not a new runtime, scan, production or device pass. Current execution state belongs in GitHub, not a second checklist here.

## Dispositions

| Issue | Disposition | Remaining outcome and next boundary |
| --- | --- | --- |
| [#595](https://github.com/ccolosimo3/stima/issues/595) Pilot-ready umbrella | Retain as deferred pilot/release context; current Flutter work follows the new roadmap. | #603/#604/#616/#618 retain obligations. Founder GTM #601 and quote-quality feedback #598 were closed not-planned, not shipped. Do not require those deferred business materials for a local portfolio Capture slice. |
| [#603](https://github.com/ccolosimo3/stima/issues/603) Maintenance/design closeout | Reconcile into the maintenance/verification parent rather than rerun the closed design programme. | Carry documentation/discoverability into #741 and the feature-owned mobile docs; retain the named verification Tasks #726–#734 and #740 with their own scope/policy decisions. |
| [#604](https://github.com/ccolosimo3/stima/issues/604) Pilot QA | Retain as a release-evidence gate, deferred behind a complete selected journey. | The required P1 QA artifact and current-candidate scenario results are absent. Reconcile the target (demo versus production pilot), environments, operational proof and explicit limitations before sign-off. |
| [#616](https://github.com/ccolosimo3/stima/issues/616) Production safety | Retain; partial implementation is not completed safety acceptance. | Logging/config guards advanced in #694/#692; #695–#699 and observability #618 still contain real residuals. Refresh the dated PR1 inventory before future release use. |
| [#618](https://github.com/ccolosimo3/stima/issues/618) Observability/alerting | Retain, but defer provider-specific setup until deployment and release target are selected. | Existing logs/Sentry initialization do not establish the requested event allowlist, query runbook, alert configuration, smoke results or founder response. Reuse current logging owners. |
| [#668](https://github.com/ccolosimo3/stima/issues/668) React Native/Expo | Superseded by the operator-selected Flutter client; close not-planned rather than completed. | Archive its sixteen planning files intact apart from navigation/status notices. Retain useful product constraints without porting Expo packages or its speculative all-at-once spike. |
| [#695](https://github.com/ccolosimo3/stima/issues/695) Tenant isolation | Retain; narrow execution to missing action/side-effect proof. | Reuse CRUD/catalog/public-token tests. Add the missing foreign-resource share/revoke/PDF/conversion and non-mutation outcomes; classify actual profile/logo/support/admin surfaces. |
| [#696](https://github.com/ccolosimo3/stima/issues/696) Public share/PDF | Retain; separate already-present token/schema behavior from residual public-boundary work. | Review the intentional allowed fields; bound PDF/logo errors and error-response headers; prove quote/invoice parity and record TTL/cache rationale. |
| [#697](https://github.com/ccolosimo3/stima/issues/697) Audio/upload failures | Retain as a concrete service-boundary correction before release exposure. | Extraction/transcription responses still interpolate exception text. Sanitize the established boundary while preserving validation/status and degraded-draft/retry classification. Reuse worker redaction from #694. |
| [#698](https://github.com/ccolosimo3/stima/issues/698) Extraction safety | Retain; reuse validation/logging and prove adversarial containment at real owners. | Cover primary/repair input separation and adversarial cases; assert reviewable draft or safe failure with no send/share/conversion side effects. Fake-provider containment is not live-model resistance. |
| [#699](https://github.com/ccolosimo3/stima/issues/699) Container/dependency/secrets | Retain; narrow build/runtime proof and deployment-specific checklist work. | Dockerfile has no non-root user. Prove runtime UID and writable app storage, exact audit commands and explicit operational assumptions; avoid a new scanner collection. #733/#734 own separate PR/enforcement policy. |

“Retain” does not make a giant old Task implementation-ready. Its next execution must ground one bounded residual against current owners, preserve the remaining acceptance, and use the required reviews.

## Maintenance candidates already disposed

The eight numbered candidates in #603 are all closed:

| Candidate | Recorded disposition |
| --- | --- |
| #392 Lucide migration | Completed; related merged work #609/#611. |
| #325 editor orchestration refactor | Not planned; the requested hook extraction must not be described as shipped. |
| #327 pilot event persistence reconciliation | Not planned/superseded, with specific completed versus deferred event decisions in its closure record. |
| #368 backend test organization | Completed; behavior-owned modules exist. |
| #485 design adoption | Completed. |
| #544 design audit closeout | Completed; related PR #545. |
| #519 UI-system documentation | Completed; related PR #546. |
| #520 design regression pass | Closed completed; this review did not recreate its full device evidence. |

The two unnumbered outcomes—stale-document reconciliation and architecture discoverability—now have named owners in #741 and the current feature docs. New verification work does not reopen the historical design programme.

## What the source actually establishes

- [Production configuration](../../backend/app/core/config.py) rejects unsafe deployed cookie/origin/host settings and production Redis degradation. The [May PR1 security inventory](../../docs/qa/P1_PRODUCTION_SECURITY_LLM_SAFETY_GATE.md) predates those guards and logging changes; it is not a current pass/fail report.
- [Extraction service](../../backend/app/features/quotes/extraction_service.py) still formats extraction/transcription exceptions into client-visible errors. [Public quote PDF service](../../backend/app/features/quotes/share/service.py) still forwards render-error text. These are concrete residuals, not merely missing paperwork.
- [Public response schemas](../../backend/app/features/quotes/schemas.py) and token lifecycle owners already constrain anonymous access. Selected tests do not establish a complete intentional field-set or every rejected action's lack of side effects.
- [Extraction integration](../../backend/app/integrations/extraction.py) already has system/user separation, structured parsing and validation. Existing malformed-output/normal-input tests do not replace adversarial route/repair proof or the [human-review boundary](../../docs/adr/007-human-review-boundary-for-ai-assisted-documents.md).
- [Dockerfile](../../backend/Dockerfile) has no runtime `USER`. [Dependency audit](../../.github/workflows/dependency-audit.yml) already exists; its existence is not current advisory cleanliness or enforced PR policy.
- [Demo deployment](../../docs/runbooks/demo-deployment.md) deliberately permits inline jobs and ephemeral storage. Successful demo smoke cannot establish production queue, storage, tenancy or operational readiness.
- The requested P1 readiness and production logging-runbook artifacts are absent at this baseline. Historical [P0 device QA](../../docs/qa/P0_FIELD_RESILIENT_CAPTURE_QA.md) includes an April Samsung run, not the current Flutter native journey.

## Verification overlap without duplicate closure

#726 supplies migrated-schema proof; #727 effective config checks; #728 a valid frontend binary oracle; #729 retry-cap proof and named trimming; #730 one built-browser recovery journey; #731 a hosted Flutter gate; #732 the real queue seam; #733/#734 selected dependency/merge policies. None by itself closes tenant isolation, public-data minimization, adversarial containment or a production pilot gate.

#740 addresses a separately reproduced online-listener registration gap in existing browser auth. Its correction does not implement native bearer authentication or replace #695's cross-tenant action evidence.

The completed [bulk-selection plan](../archive/2026-10-31/home-bulk-selection/spec-home-bulk-select-archive-delete.md) was also archived: #652 and all four children #653–#656 are closed completed. Their deletion/archive contracts remain authoritative in runtime code; archival does not reopen or weaken them.

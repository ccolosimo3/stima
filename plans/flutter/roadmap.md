# Stima Flutter roadmap

Build a dependable mobile quoting journey while learning Flutter through a serious portfolio project. Flutter is the selected client for Android and iPhone; retain the React web client, FastAPI/Python backend, PostgreSQL, server-generated documents and public customer links. The audit found no demonstrated need for a backend-language rewrite.

GitHub Tasks own acceptance and linked PRs own execution status. [The shared source handoff](https://github.com/ccolosimo3/stima/issues/723#issuecomment-6548090628) records exact candidate versions and platform evidence. This roadmap describes direction and dependencies, not a claim of native feature parity or production readiness.

## Deliver the working journey in order

| Boundary | Observable result | Dependency and parallel work |
| --- | --- | --- |
| Foundation | A reproducible Flutter build and reusable Capture presentation | Foundation #723 and presentation #724; web audio integrity #725 and HTTP oracle #728 remain independently useful. |
| Real local Capture | Enter notes, record/play/delete clips, safely stop on interruption, then reopen the same saved work | One current device-local Capture. Recorder/storage core precedes its thin UI binding within one end-to-end Task; authors hand off serially. Auth and backend calls are excluded. |
| Native authentication and Extraction | Sign in, submit one saved Capture with a stable retry identity, observe its Job and recover the resulting Quote Draft | Select the additive native credential contract without weakening browser cookies/CSRF. Prove actual native multipart/codec behavior before joining the backend journey. |
| Quote Review and delivery | Edit the Quote Draft, explicitly confirm, generate a server document and share its existing public link | Reuse server money, document, share and revision semantics. Cover ordinary failure and restart at the actual integrated boundary. |
| Portfolio breadth | Customers/history, reuse/catalog, onboarding/profile and invoice conversion where the core journey needs them | Choose independent vertical journeys after the first complete quote flow works; do not translate every old screen first. |
| Distribution and pilot | A bounded synthetic demo or a separately qualified release | Physical Android/iPhone checks, selected security/release evidence and distribution ownership precede claims for that target. |

Push notifications, ongoing background recording, broad offline document editing, payments and a full service-business platform are later product scope. Store enrollment, paid cloud builds and production deployment are separate decisions.

## Local Capture decisions

- Start with one active device-local Capture and autosave/reopen it. A multiple-Capture history selector is later breadth.
- On lock/background, stop recording safely and preserve captured input. Do not resume recording automatically or silently discard a failed save.
- Show saving/finalization separately from saved/playable state. Retained incomplete bytes are not proof of a finalized audio clip.
- Delete only after the persistence owner acknowledges the intended outcome; retain actionable feedback/retry when an operation fails.
- During a later submitted Extraction, lock its inputs. Failure preserves inputs and restores editing/retry; a separate unsent revision is excluded initially.
- Use synthetic data for development and public evidence. A fake recorder, screenshot or platform override cannot certify real microphone, filesystem or device lifecycle behavior.

## Keep architecture at its owners

The mobile feature owns its Capture state, serialized operations and recovery. Platform adapters own recorder/player and app-private paths; the store owns saved metadata/audio membership and reopen behavior. Widgets render state and request actions rather than maintaining a second recording or persistence state machine.

Select the smallest mechanism with a real consumer. One Capture does not automatically justify a query framework, global state container, dependency-injection framework, database or shared cross-language package. Compare persistence choices against actual partial-write/reopen/deletion behavior before committing to one. Keep app-owned audio out of temporary caches and retain stable independent clip identities.

The backend remains authoritative for credentials, ownership, money, Jobs, Quote Drafts and documents. Local save, server acceptance, Extraction completion and persisted Quote Draft are distinct facts. Preserve the existing human-review boundary before any customer-facing action.

## Verification foundation

Improve proof at demonstrated gaps; keep useful existing pytest/Vitest coverage.

| Sequence | Work | Required distinction |
| --- | --- | --- |
| Reconnect correctness | #740 | An event at offline-state commit must reach its listener and produce verified user/outbox behavior; preserve existing auth policy. |
| Static/config fidelity | #727 | Typecheck the real build/test configuration and resolve the demonstrated tool/type mismatch without suppression. |
| Migrated constraints | #726 | Prove fresh and populated Alembic schemas with named constraint outcomes; ORM metadata alone is insufficient. |
| Retry proof and trimming | #729 | Exercise actual retry exhaustion and remove only named redundant/incidental assertions with retained behavioral proof. |
| Native hosted gate | #731 | Run the pinned existing Flutter gate in hosted CI; Android build does not establish iPhone behavior. |
| Real consumer journeys | #730 and #732 | One built-browser recovery journey and the actual queue producer/worker seam; neither replaces fast owner tests. |
| Explicit hosted policy | #733 and #734 | Dependency-PR scanning and enforced PR/check rules require their selected policy and real hosted outcomes. |

Use the project's Flutter/Dart pin and locked dependencies. Reuse evidence only when relevant source, tests, configuration and environment remain equivalent. Required inner and risk-selected outer reviews use independent contexts; corrections return to the same reviewers. Combined delivery review checks the named integrated goal after its constituent work converges.

## Ownership and collaboration

- The main lead owns roadmap, backlog dispositions, dependencies and integration.
- The mobile lead owns recorder/storage architecture and native core; the design lead owns the subsequent real UI binding. One writer owns the shared Task checkout at a time.
- The verification lead owns #740 and selected verification work, isolated from the mobile source.
- The Mac lead owns source-identical iOS build/device observations and platform prerequisites. Windows and Mac exchange exact published commit IDs through the shared handoff, using separate owned worktrees.
- A branch push, source review or preview deployment does not establish a main merge, physical-device pass or release.

Both physical platforms are targets. Early iPhone work uses the owned Mac and free Personal Team signing; personal Stima ownership stays separate from the company Apple team. Device debugger/hot reload and physical input observations must be reported as actually observed, not inferred from successful installation.

## Retained release obligations

[The historical backlog review](backlog-review.md) owns disposition of the eleven older open issues. #595/#604 retain pilot/release outcomes; #616 and #695–#699 retain concrete security work; #618 retains operational detection/response. These are not all blockers to a synthetic local mobile project, and they are not satisfied by a polished UI.

The [original pilot proposal](../../docs/roadmaps/P1_PILOT_READY_PRODUCT_GTM.md) remains historical rationale. The [React Native archive](../archive/2026-10-31/react-native/SPEC-001-rn-expo-rewrite.md) is superseded source material, not Flutter execution guidance.

Before expanding scope, choose the next independently valid operation boundary, its real success/failure proof and owner. Release breadth, public distribution and hosted policy remain operator decisions; equivalent internal mechanisms within the selected behavior remain engineering choices.

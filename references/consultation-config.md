# Consultation Configuration

Stage-to-consultation mapping for the Aegis pipeline.
Consultation provides external model review at key pipeline gates.

## Stage Mapping

| Stage      | Consultation | Model                          | Context Limit |
|------------|-------------|--------------------------------|---------------|
| intake     | none        | —                              | —             |
| research   | routine     | DeepSeek (Sparrow)             | ~2000 chars   |
| roadmap    | routine     | DeepSeek (Sparrow)             | ~2000 chars   |
| phase-plan | routine     | DeepSeek (Sparrow)             | ~2000 chars   |
| execute    | none        | —                              | —             |
| verify     | critical    | Codex if opted-in, else DeepSeek | ~4000 chars |
| test-gate  | none        | —                              | —             |
| advance    | none        | —                              | —             |
| deploy     | critical    | Codex if opted-in, else DeepSeek | ~4000 chars |

## Consultation Types

- **none** — No consultation. Stage proceeds without external review.
- **routine** — DeepSeek review via Sparrow (free). Brief sanity check on stage output.
- **critical** — Codex review if user opted in, otherwise DeepSeek. Deeper review of important artifacts.

## Context Size Limits

- **Routine (DeepSeek):** ~2000 characters. Enough for a summary + key points.
- **Critical (Codex):** ~4000 characters. Allows more detailed artifact inclusion.

## Rationale

- **intake** and **execute** produce no reviewable artifacts (intake is user input; execute delegates to GSD).
- **research**, **roadmap**, **phase-plan** benefit from a quick sanity check — routine is sufficient.
- **verify** and **deploy** are high-stakes gates where deeper review catches architectural and security issues.
- **test-gate** and **advance** are mechanical (pass/fail, loop/continue) — no subjective review needed.

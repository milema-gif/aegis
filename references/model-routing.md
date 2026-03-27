# Model Routing Table

Maps each Aegis subagent role to its assigned model, with rationale and fallback behavior.

## Routing Table

| Agent Role | Model | Rationale | Fallback |
|------------|-------|-----------|----------|
| Orchestrator | Claude (main session) | Manages state, routes, validates | N/A |
| aegis-researcher | sonnet | Research follows instructions | haiku |
| aegis-planner | inherit (opus) | Planning needs architecture reasoning | sonnet |
| aegis-executor | sonnet | Follows explicit plan instructions | sonnet |
| aegis-verifier | sonnet | Goal-backward reasoning needs mid-tier | haiku |
| aegis-deployer | sonnet | Deploy actions need careful execution | sonnet |
| GPT-4 Mini (Sparrow) | External/DeepSeek | Cheap autonomous sub-tasks only | Skip (graceful degradation) |

## Routing Profiles

Three pre-defined profiles control model assignment across all agents:

### Quality Profile
All agents use the highest-tier model available. Best for complex or high-risk projects.

| Agent | Model |
|-------|-------|
| aegis-researcher | opus |
| aegis-planner | opus |
| aegis-executor | opus |
| aegis-verifier | opus |
| aegis-deployer | opus |

### Balanced Profile (Default)
Mixed assignment based on task complexity. The default routing table above represents this profile.

### Budget Profile
Minimizes cost by using lower-tier models and external delegation where safe.

| Agent | Model |
|-------|-------|
| aegis-researcher | haiku |
| aegis-planner | sonnet |
| aegis-executor | haiku |
| aegis-verifier | haiku |
| aegis-deployer | haiku |

## GPT-4 Mini Delegation via Sparrow

The Sparrow bridge provides access to DeepSeek (free) and GPT-5.3 Codex (paid, user-explicit only).

### Qualifying Tasks for Sparrow Delegation

Tasks that are safe to delegate to external models via Sparrow:

- **Formatting:** Converting between data formats, prettifying output
- **Summarizing:** Condensing research findings, generating descriptions
- **Boilerplate:** Generating repetitive code patterns, template expansion
- **Linting/review:** Surface-level code review, style checking

### Tasks That Must NOT Be Delegated

- **Architecture decisions:** Schema design, API design, system boundaries
- **Code logic:** Business logic, algorithms, security-sensitive code
- **Reasoning:** Dependency analysis, tradeoff evaluation, debugging

### Invocation Pattern

```bash
# Standard invocation (DeepSeek -- free)
${AEGIS_SPARROW_PATH:-sparrow} "Summarize these research findings: ..."

# With timeout (recommended)
timeout 60 ${AEGIS_SPARROW_PATH:-sparrow} "Format this routing table as markdown: ..."

# Codex invocation (paid -- user-explicit ONLY per CLAUDE.md)
# ONLY when user literally says "codex" in their message
${AEGIS_SPARROW_PATH:-sparrow} --codex "Review this architecture plan: ..."
```

### Fallback Behavior

If Sparrow is unavailable (detected via `detect_integrations()` from `lib/aegis-detect.sh`):

1. Skip external delegation entirely
2. Continue with Claude-only execution
3. Log that Sparrow was unavailable but do not fail the pipeline
4. No retry -- graceful degradation is the only fallback

### Cost Notes

- Sparrow default is DeepSeek (free, no budget impact)
- `--codex` flag routes to GPT-5.3 Codex (see your budget configuration)
- Codex is NEVER auto-invoked -- only when user explicitly says "codex"
- Budget tracking is the user's responsibility

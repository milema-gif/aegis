# Phase 11: Policy-as-Code - Research

**Researched:** 2026-03-21
**Domain:** Configuration extraction, gate policy management, bash/JSON config patterns
**Confidence:** HIGH

## Summary

Phase 11 extracts all hardcoded gate policies from three locations -- `lib/aegis-gates.sh` (gate evaluation logic), `lib/aegis-consult.sh` (consultation type mapping), and `templates/pipeline-state.json` (gate defaults) -- into a single versioned config file that the pipeline reads at startup. The existing code already uses JSON throughout (state files, templates), making JSON the natural config format.

The refactoring scope is well-defined: gate type/skippable/retry/backoff/timeout per stage are currently baked into `pipeline-state.json` template and read from `state.current.json` at runtime. Consultation type per stage is hardcoded as a bash `case` statement. Both need to move to a policy config file that is loaded once at startup, stamped with a version, and tracked in git.

**Primary recommendation:** Use a single `aegis-policy.json` file in the project root (or `.aegis/`) with a `policy_version` field. Gate evaluation functions read from this config instead of hardcoded values. The template generator reads from it too. Every evidence artifact (Phase 12+) stamps `policy_version`.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| POLC-01 | Gate policies (which gates block, retry limits, risk thresholds, consultation triggers) defined in versioned config file -- not hardcoded | Config file format defined; all hardcoded locations identified (3 files); loader function pattern documented |
| POLC-02 | Policy changes auditable -- config diffs tracked in git, policy version stamped in evidence artifacts | Version field in config; git-tracked file location; stamp function for evidence artifacts |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JSON | n/a | Config format | Already used for state.current.json, pipeline-state.json template; python3 json module available everywhere; bash has no native YAML/TOML parser |
| python3 json | stdlib | Config loading/validation | Already used in every lib/*.sh file for JSON manipulation; zero new dependencies |
| bash | 5.x | Shell functions | All existing lib code is bash |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSON | YAML | Would require `yq` or python yaml module; adds dependency; Aegis already standardized on JSON everywhere |
| JSON | TOML | Would require python tomllib (3.11+) or toml package; overkill for flat config; no existing tooling |
| Single file | Split per-stage files | Over-engineering; 9 stages fit comfortably in one file; harder to audit |

## Architecture Patterns

### Recommended Config File Location
```
project-root/
  aegis-policy.json          # <-- THE policy config (git-tracked)
  .aegis/
    state.current.json       # Runtime state (references policy_version)
    evidence/                # Future: Phase 12 artifacts stamp policy_version
  lib/
    aegis-policy.sh          # NEW: policy loader library
    aegis-gates.sh           # MODIFIED: reads from policy, not state
    aegis-consult.sh         # MODIFIED: reads from policy, not case statement
  templates/
    pipeline-state.json      # MODIFIED: gate fields populated from policy at init
    aegis-policy.default.json # NEW: shipped default policy (reference/reset)
```

### Pattern 1: Policy Config Schema
**What:** Single JSON file defining all gate behavior per stage
**When to use:** Pipeline startup, gate evaluation, evidence stamping
**Example:**
```json
{
  "policy_version": "1.0.0",
  "description": "Aegis gate policy configuration",
  "updated_at": "2026-03-21T14:00:00Z",
  "gates": {
    "intake": {
      "type": "approval",
      "skippable": true,
      "max_retries": 0,
      "backoff": "none",
      "timeout_seconds": 0
    },
    "research": {
      "type": "approval",
      "skippable": true,
      "max_retries": 0,
      "backoff": "none",
      "timeout_seconds": 0
    },
    "roadmap": {
      "type": "approval",
      "skippable": true,
      "max_retries": 0,
      "backoff": "none",
      "timeout_seconds": 0
    },
    "phase-plan": {
      "type": "quality",
      "skippable": false,
      "max_retries": 2,
      "backoff": "fixed-5s",
      "timeout_seconds": 120
    },
    "execute": {
      "type": "quality",
      "skippable": false,
      "max_retries": 3,
      "backoff": "fixed-5s",
      "timeout_seconds": 300
    },
    "verify": {
      "type": "quality",
      "skippable": false,
      "max_retries": 2,
      "backoff": "fixed-5s",
      "timeout_seconds": 120
    },
    "test-gate": {
      "type": "quality",
      "skippable": false,
      "max_retries": 3,
      "backoff": "exp-5s",
      "timeout_seconds": 180
    },
    "advance": {
      "type": "none",
      "skippable": true,
      "max_retries": 0,
      "backoff": "none",
      "timeout_seconds": 0
    },
    "deploy": {
      "type": "quality,external",
      "skippable": false,
      "max_retries": 1,
      "backoff": "none",
      "timeout_seconds": 60
    }
  },
  "consultation": {
    "intake": { "type": "none", "context_limit": 0 },
    "research": { "type": "routine", "context_limit": 2000 },
    "roadmap": { "type": "routine", "context_limit": 2000 },
    "phase-plan": { "type": "routine", "context_limit": 2000 },
    "execute": { "type": "none", "context_limit": 0 },
    "verify": { "type": "critical", "context_limit": 4000 },
    "test-gate": { "type": "none", "context_limit": 0 },
    "advance": { "type": "none", "context_limit": 0 },
    "deploy": { "type": "critical", "context_limit": 4000 }
  },
  "gate_rules": {
    "quality_never_skippable": true,
    "external_never_skippable": true,
    "compound_short_circuit": true
  }
}
```

### Pattern 2: Policy Loader Function
**What:** `load_policy()` reads config once, caches path in env var
**When to use:** Called once at pipeline startup, before any gate evaluation
**Example:**
```bash
# In lib/aegis-policy.sh
AEGIS_POLICY_FILE="${AEGIS_POLICY_FILE:-aegis-policy.json}"
AEGIS_POLICY_VERSION=""

load_policy() {
  if [[ ! -f "$AEGIS_POLICY_FILE" ]]; then
    echo "FATAL: Policy config not found: $AEGIS_POLICY_FILE" >&2
    return 1
  fi
  # Validate JSON and extract version
  AEGIS_POLICY_VERSION=$(python3 -c "
import json, sys
with open('${AEGIS_POLICY_FILE}') as f:
    p = json.load(f)
v = p.get('policy_version')
if not v:
    print('ERROR: policy_version missing', file=sys.stderr)
    sys.exit(1)
print(v)
") || return 1
  export AEGIS_POLICY_FILE AEGIS_POLICY_VERSION
}

get_policy_version() {
  echo "$AEGIS_POLICY_VERSION"
}
```

### Pattern 3: Gate Config Lookup (replaces hardcoded template values)
**What:** `evaluate_gate()` reads gate type/skippable from policy config, not from state.current.json gate fields
**When to use:** Every gate evaluation call
**Example:**
```bash
# In modified aegis-gates.sh
evaluate_gate() {
  local stage_name="${1:?evaluate_gate requires stage_name}"
  local yolo_mode="${2:-false}"

  python3 -c "
import json, sys

with open('${AEGIS_POLICY_FILE}') as f:
    policy = json.load(f)

gate_cfg = policy['gates'].get('${stage_name}')
if gate_cfg is None:
    print('error: unknown stage in policy', file=sys.stderr)
    sys.exit(1)

gate_type = gate_cfg['type']
yolo = '${yolo_mode}' == 'true'
types = [t.strip() for t in gate_type.split(',')]

# ... same evaluation logic, but from policy not state ...
"
}
```

### Pattern 4: Template Generation from Policy
**What:** `init_state()` populates `pipeline-state.json` gate fields from policy config
**When to use:** Pipeline initialization (`init_state()`)
**Example:**
```bash
# In modified aegis-state.sh init_state()
init_state() {
  local project_name="${1:?init_state requires project_name}"
  mkdir -p "$AEGIS_DIR"

  python3 -c "
import json
# Read policy
with open('${AEGIS_POLICY_FILE}') as f:
    policy = json.load(f)
# Read template
with open('${AEGIS_TEMPLATE_DIR}/pipeline-state.json') as f:
    state = json.load(f)
# Apply policy gate configs to each stage
for stage in state['stages']:
    name = stage['name']
    if name in policy['gates']:
        gcfg = policy['gates'][name]
        stage['gate']['type'] = gcfg['type']
        stage['gate']['skippable'] = gcfg.get('skippable', False)
        stage['gate']['max_retries'] = gcfg.get('max_retries', 0)
        stage['gate']['backoff'] = gcfg.get('backoff', 'none')
        stage['gate']['timeout_seconds'] = gcfg.get('timeout_seconds', 0)
# Stamp policy version
state['policy_version'] = policy['policy_version']
# ... rest of init ...
"
}
```

### Pattern 5: Policy Version Stamping
**What:** Every evidence artifact includes `policy_version` field
**When to use:** Phase 12 will consume this; wire it now
**Example:**
```bash
# Utility function in aegis-policy.sh
stamp_policy_version() {
  local artifact_file="${1:?stamp_policy_version requires file path}"
  python3 -c "
import json
with open('${artifact_file}') as f:
    data = json.load(f)
data['policy_version'] = '${AEGIS_POLICY_VERSION}'
with open('${artifact_file}', 'w') as f:
    json.dump(data, f, indent=2)
"
}
```

### Anti-Patterns to Avoid
- **Embedding policy in state.current.json:** State is per-run, policy is per-project. Mixing them means policy changes require state reset.
- **Using environment variables for policy:** Invisible, not auditable, not git-tracked, easy to forget.
- **Validating policy on every gate call:** Validate once at startup, fail fast. Per-call validation wastes cycles.
- **Making policy optional with fallback defaults:** If there is no policy file, that is an error. Silent fallback hides misconfiguration.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON schema validation | Custom field-by-field checks | python3 validation function with clear error messages | Schema is simple (9 stages x 5 fields); a validate function is sufficient. jsonschema package is overkill for this |
| Semantic versioning | String comparison | Simple `major.minor.patch` string; no semver library needed | Policy versions are informational stamps, not dependency constraints |
| Config file watching | File watcher / inotify | Read once at startup | Pipeline runs are short-lived; no need for hot-reload |
| Config migration | Schema migration framework | Manual version bump + validation | Config schema is stable; 9 fixed stages |

**Key insight:** The policy config is a simple flat structure (9 stages, 5-6 fields each). It does not need schema migration, hot-reload, or inheritance. Keep it dead simple.

## Common Pitfalls

### Pitfall 1: Dual Source of Truth
**What goes wrong:** Policy defines gate types, but `pipeline-state.json` template ALSO defines gate types. If someone edits the template directly, the two diverge.
**Why it happens:** The template currently IS the config. After refactoring, the template must be generated from policy.
**How to avoid:** Strip gate config from the template. Make `init_state()` populate gate fields from policy at runtime. The template only contains structural defaults (stage names, indices, initial status).
**Warning signs:** Test failures where gate behavior doesn't match policy file.

### Pitfall 2: Consultation Case Statement Left Behind
**What goes wrong:** `get_consultation_type()` in `aegis-consult.sh` uses a hardcoded `case` statement. If policy is updated but the case statement remains, consultation behavior won't change.
**Why it happens:** Easy to forget this second location of hardcoded config.
**How to avoid:** Replace the entire `case` statement with a policy lookup. Delete the case statement entirely.
**Warning signs:** Changing consultation type in policy has no effect.

### Pitfall 3: Breaking Existing Tests
**What goes wrong:** `test-gate-evaluation.sh` (14 tests) and `test-consultation.sh` create state files directly. After refactoring, they need a policy file present.
**Why it happens:** Tests bypass `init_state()` and create minimal state directly.
**How to avoid:** Create a test helper that writes a default policy file to the test temp dir. Update test setup functions.
**Warning signs:** All gate tests fail after refactoring with "policy file not found."

### Pitfall 4: check_gate_limits Still Reads From State
**What goes wrong:** `check_gate_limits()` reads `max_retries` and `timeout_seconds` from `state.current.json` gate object. These are runtime values that SHOULD come from policy.
**Why it happens:** After init, the values are copied to state. But `check_gate_limits` should read from policy for consistency.
**How to avoid:** Decide: either (a) always read policy for limits, or (b) copy policy values to state at init and read from state at runtime. Option (b) is simpler and matches current behavior -- the state snapshot captures what policy was active at init time.
**Warning signs:** Changing retry limits in policy mid-run has no effect.

### Pitfall 5: Version Stamp Without Consumers
**What goes wrong:** Building elaborate version stamping when Phase 12 (evidence artifacts) hasn't been built yet. No consumers exist.
**Why it happens:** POLC-02 says "policy version stamped in evidence artifacts."
**How to avoid:** Wire a simple `get_policy_version()` function and `stamp_policy_version()` utility. Phase 12 will call them. Don't build the evidence artifact format now.
**Warning signs:** Over-engineering the stamp format before knowing what evidence artifacts look like.

## What's Currently Hardcoded (Extraction Map)

### Location 1: `templates/pipeline-state.json` (lines 11-46)
**What:** Gate type, skippable, max_retries, backoff, timeout_seconds for all 9 stages
**Action:** Strip gate config fields from template; populate from policy in `init_state()`

### Location 2: `lib/aegis-consult.sh` (lines 17-35)
**What:** `get_consultation_type()` case statement mapping stage -> none/routine/critical
**Action:** Replace case statement with policy JSON lookup

### Location 3: `lib/aegis-consult.sh` (lines 82-86)
**What:** `char_limit` hardcoded as 2000 (routine) / 4000 (critical) in `build_consultation_context()`
**Action:** Read `context_limit` from policy consultation config

### Location 4: `references/gate-definitions.md`
**What:** Human-readable gate table documenting current policy
**Action:** Keep as reference doc; add note that `aegis-policy.json` is the machine-readable source of truth

### Location 5: `references/consultation-config.md`
**What:** Human-readable consultation mapping
**Action:** Keep as reference doc; add note that `aegis-policy.json` is the machine-readable source of truth

## Code Examples

### Default Policy File (aegis-policy.json)
```json
{
  "policy_version": "1.0.0",
  "description": "Default Aegis gate policy",
  "updated_at": "2026-03-21T00:00:00Z",
  "gates": {
    "intake":     { "type": "approval", "skippable": true,  "max_retries": 0, "backoff": "none",     "timeout_seconds": 0 },
    "research":   { "type": "approval", "skippable": true,  "max_retries": 0, "backoff": "none",     "timeout_seconds": 0 },
    "roadmap":    { "type": "approval", "skippable": true,  "max_retries": 0, "backoff": "none",     "timeout_seconds": 0 },
    "phase-plan": { "type": "quality",  "skippable": false, "max_retries": 2, "backoff": "fixed-5s", "timeout_seconds": 120 },
    "execute":    { "type": "quality",  "skippable": false, "max_retries": 3, "backoff": "fixed-5s", "timeout_seconds": 300 },
    "verify":     { "type": "quality",  "skippable": false, "max_retries": 2, "backoff": "fixed-5s", "timeout_seconds": 120 },
    "test-gate":  { "type": "quality",  "skippable": false, "max_retries": 3, "backoff": "exp-5s",   "timeout_seconds": 180 },
    "advance":    { "type": "none",     "skippable": true,  "max_retries": 0, "backoff": "none",     "timeout_seconds": 0 },
    "deploy":     { "type": "quality,external", "skippable": false, "max_retries": 1, "backoff": "none", "timeout_seconds": 60 }
  },
  "consultation": {
    "intake":     { "type": "none",     "context_limit": 0 },
    "research":   { "type": "routine",  "context_limit": 2000 },
    "roadmap":    { "type": "routine",  "context_limit": 2000 },
    "phase-plan": { "type": "routine",  "context_limit": 2000 },
    "execute":    { "type": "none",     "context_limit": 0 },
    "verify":     { "type": "critical", "context_limit": 4000 },
    "test-gate":  { "type": "none",     "context_limit": 0 },
    "advance":    { "type": "none",     "context_limit": 0 },
    "deploy":     { "type": "critical", "context_limit": 4000 }
  },
  "gate_rules": {
    "quality_never_skippable": true,
    "external_never_skippable": true,
    "compound_evaluation": "left-to-right-short-circuit"
  }
}
```

### Policy Validation Function
```python
# Called once at load_policy() time
import json, sys

def validate_policy(path):
    with open(path) as f:
        p = json.load(f)

    errors = []

    # Required top-level fields
    if 'policy_version' not in p:
        errors.append("Missing 'policy_version'")
    if 'gates' not in p:
        errors.append("Missing 'gates'")
    if 'consultation' not in p:
        errors.append("Missing 'consultation'")

    # Required stages
    required_stages = ['intake','research','roadmap','phase-plan','execute','verify','test-gate','advance','deploy']
    for stage in required_stages:
        if stage not in p.get('gates', {}):
            errors.append(f"Missing gate config for stage '{stage}'")
        if stage not in p.get('consultation', {}):
            errors.append(f"Missing consultation config for stage '{stage}'")

    # Required gate fields
    gate_fields = ['type', 'skippable', 'max_retries', 'backoff', 'timeout_seconds']
    for stage, cfg in p.get('gates', {}).items():
        for field in gate_fields:
            if field not in cfg:
                errors.append(f"Gate '{stage}' missing field '{field}'")

    # Valid gate types
    valid_types = {'approval', 'quality', 'external', 'cost', 'none'}
    for stage, cfg in p.get('gates', {}).items():
        types = [t.strip() for t in cfg.get('type', '').split(',')]
        for t in types:
            if t not in valid_types:
                errors.append(f"Gate '{stage}' has invalid type '{t}'")

    # Valid backoff values
    valid_backoffs = {'none', 'fixed-5s', 'exp-5s'}
    for stage, cfg in p.get('gates', {}).items():
        if cfg.get('backoff') not in valid_backoffs:
            errors.append(f"Gate '{stage}' has invalid backoff '{cfg.get('backoff')}'")

    return errors
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Gate config in template JSON | Gate config in template JSON (current) | v1.0 Phase 2 | Template IS the config; changing behavior requires editing template + re-init |
| Consultation in case statement | Consultation in case statement (current) | v1.0 Phase 6 | Adding a consultation type requires code change in aegis-consult.sh |

**What changes:**
- Gate config moves to `aegis-policy.json` (operator-editable, git-tracked)
- Template becomes a structural skeleton, populated from policy at init time
- Consultation mapping moves to policy config, case statement deleted
- All runtime reads go through policy loader

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (custom assert pattern) |
| Config file | none -- tests are standalone scripts in `tests/` |
| Quick run command | `bash tests/test-gate-evaluation.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| POLC-01 | Gate policies read from config file, not hardcoded | unit | `bash tests/test-policy-config.sh` | Wave 0 |
| POLC-01 | Changing config changes gate behavior without code edit | integration | `bash tests/test-policy-config.sh` | Wave 0 |
| POLC-01 | init_state populates state from policy | unit | `bash tests/test-policy-config.sh` | Wave 0 |
| POLC-01 | Consultation type read from policy | unit | `bash tests/test-policy-config.sh` | Wave 0 |
| POLC-02 | Policy version stamped in state | unit | `bash tests/test-policy-config.sh` | Wave 0 |
| POLC-02 | stamp_policy_version utility works | unit | `bash tests/test-policy-config.sh` | Wave 0 |
| POLC-02 | Policy file is git-tracked | smoke | `bash tests/test-policy-config.sh` | Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-gate-evaluation.sh && bash tests/test-consultation.sh && bash tests/test-policy-config.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-policy-config.sh` -- new test file covering all POLC requirements
- [ ] `aegis-policy.json` -- the policy config file itself
- [ ] `lib/aegis-policy.sh` -- policy loader library
- [ ] Update `tests/test-gate-evaluation.sh` setup to create policy file in temp dir
- [ ] Update `tests/test-consultation.sh` setup to create policy file in temp dir

## Open Questions

1. **Policy file location: project root vs `.aegis/`?**
   - Project root (`aegis-policy.json`): More visible, easier to find, natural for git tracking
   - `.aegis/policy.json`: Grouped with other aegis files, but `.aegis/` is sometimes gitignored
   - Recommendation: Project root. The file is meant to be visible and editable by operators.

2. **Should `check_gate_limits()` read from policy or state?**
   - What we know: Currently reads from state (which was copied from template at init). After refactoring, state still gets populated from policy at init.
   - Recommendation: Keep reading from state at runtime. The state captures what policy was active at pipeline init. This is correct behavior -- mid-run policy changes should not affect an active pipeline.

3. **Should `gate_rules` be configurable or hardcoded?**
   - What we know: Rules like "quality gates never skippable" are safety invariants. Making them configurable could allow unsafe configurations.
   - Recommendation: Include in config for documentation/auditability but enforce them regardless. If someone sets `quality_never_skippable: false`, the code ignores it and logs a warning. Safety rules are not configurable.

## Sources

### Primary (HIGH confidence)
- `lib/aegis-gates.sh` -- current gate evaluation implementation (read directly)
- `lib/aegis-consult.sh` -- current consultation mapping (read directly)
- `lib/aegis-state.sh` -- state management, init_state (read directly)
- `templates/pipeline-state.json` -- current gate defaults (read directly)
- `references/gate-definitions.md` -- gate type reference doc (read directly)
- `references/consultation-config.md` -- consultation mapping doc (read directly)
- `tests/test-gate-evaluation.sh` -- existing gate tests (read directly)

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` -- POLC-01/POLC-02 requirement text
- `.planning/ROADMAP.md` -- Phase 11 description and success criteria

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- JSON is already the project standard; no new dependencies
- Architecture: HIGH -- extraction map is complete; all hardcoded locations identified from source code
- Pitfalls: HIGH -- based on direct code analysis of existing tests and state management
- Validation: HIGH -- existing test patterns well understood

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable domain -- project-internal refactoring)

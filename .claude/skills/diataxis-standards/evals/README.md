# How to Run Evals

Evaluate whether the diataxis-standards skill produces correct, Diataxis-compliant documentation.

## Prerequisites

- Claude Code installed and authenticated
- `skill-creator` plugin installed (`/plugin` → Discover → skill-creator → Install for you)

## Run the evaluation

### Option A: skill-creator plugin (recommended)

In any Claude Code session:

```
Use the skill-creator to evaluate the diataxis-standards skill
```

The skill-creator reads `evals/evals.json`, spawns test runs with and without the skill loaded, grades each assertion, and produces a benchmark report with an interactive HTML viewer.

### Option B: Manual spot-check

Run a single eval manually to verify the skill works:

```bash
# With skill (uses diataxis-expert agent which loads diataxis-standards)
claude -p "Write a getting-started tutorial for a Python CLI tool called datapipe" --output-format json > with_skill.json

# Without skill (baseline)
claude -p "Write a getting-started tutorial for a Python CLI tool called datapipe" --output-format json --disallowedTools "Skill(diataxis-standards *)" > without_skill.json
```

Compare the two outputs against the assertions in `evals.json` for that eval.

## What gets tested

| # | Eval | Quadrant | Assertions | Tests |
|---|------|----------|------------|-------|
| 1 | Tutorial (getting-started) | Tutorial | 6 | Numbered steps, expected output blocks, no choices, no theory, achievement, cross-refs |
| 2 | How-to guide (deploy) | How-To Guide | 6 | Title format, assumes competence, variations, verification, troubleshooting table |
| 3 | Reference (API) | Reference | 6 | All endpoints documented, tables, neutral tone, no instructions, complete fields |
| 4 | Explanation (architecture) | Explanation | 6 | Explains WHY, trade-offs, Mermaid diagrams, no setup steps, no config tables |
| 5 | Mixing violation detection | Review | 5 | Identifies mixing, spots explanation in tutorial, spots reference in tutorial, recommends split |
| 6 | Cross-references | How-To Guide | 5 | Has see-also section, links to 2+ quadrants, links to reference, links to explanation |
| 7 | DOCUMENTATION_GUIDE.md generation | Meta-reference | 8 | Quadrant assignments, Mermaid chart, per-file specs, project-specific anti-patterns |
| 8 | Negative: coding task | Should NOT trigger | 1 | Skill should not activate for pure coding requests |
| 9 | Negative: git question | Should NOT trigger | 1 | Skill should not activate for git workflow questions |
| 10 | Negative: design doc | Should NOT trigger | 1 | Skill should not activate (design-doc-standards handles this) |

**Total: 10 evals, 45 assertions, 3 negative controls.**

Evals 1-7 test **output quality** (with-skill vs without-skill comparison). Evals 8-10 test **trigger accuracy** (the skill should NOT activate for these prompts). Trigger evals require the skill-creator's `run_loop.py` description optimization script.

## Cost and time expectations

- **Full suite (evals 1-7)**: 14 subagent spawns (7 with-skill + 7 without-skill), ~200k tokens, ~10-15 minutes
- **Single eval**: 2 subagent spawns, ~30-50k tokens, ~2-3 minutes
- **Trigger evals (8-10)**: run via `run_loop.py`, 3 runs per query, ~30 invocations total

## Output

Results are saved to a workspace directory (gitignored via `*-workspace/` in `.gitignore`):

```
diataxis-standards-workspace/
└── iteration-1/
    ├── benchmark.json          # Aggregated pass rates, token usage, timing
    ├── benchmark.md            # Human-readable summary
    └── eval-1-tutorial/
        ├── eval_metadata.json  # Eval prompt + assertions
        ├── with_skill/
        │   ├── outputs/        # Files produced by the skill
        │   ├── grading.json    # Assertion pass/fail with evidence
        │   └── timing.json     # Token count and duration
        └── without_skill/
            ├── outputs/        # Files produced without the skill (baseline)
            ├── grading.json
            └── timing.json
```

## Interpreting results

- **Pass rate delta > 0**: the skill improves output quality vs baseline
- **Pass rate delta = 0**: Claude already produces good output for this task without the skill — consider making assertions harder
- **Token delta**: how many extra tokens the skill costs (expect ~30-40% more due to skill context injection)
- **Negative controls**: should show 0% trigger rate (skill should NOT activate)

## Adding more evals

Add test cases to `evals.json` following the existing format. Each eval needs:

- `id`: unique number
- `name`: descriptive slug (used as directory name in workspace)
- `prompt`: realistic user message
- `expected_output`: what success looks like (human-readable)
- `assertions`: verifiable pass/fail checks (list of strings)
- `should_trigger` (optional): set to `false` for negative controls

Tips from [agentskills.io](https://agentskills.io/skill-creation/evaluating-skills):

- Start with 2-3 test cases per new capability, expand after seeing results
- Vary prompts: mix formal and casual, terse and detailed
- Cover edge cases: malformed input, ambiguous requests
- Use realistic context: file paths, column names, personal context
- Good assertions are specific and verifiable, not vague ("output is good")

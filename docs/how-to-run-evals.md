# How to Run Skill Evals

Run structured evaluations to measure whether a skill improves Claude's output compared to the baseline (no skill loaded).

## Prerequisites

- Claude Code installed and authenticated
- `skill-creator` plugin installed: `/plugin` → Discover → skill-creator → Install for you (user scope)

## Run evals for a skill

In any Claude Code session:

```
Use the skill-creator to evaluate the <skill-name> skill
```

The skill-creator:

1. Reads `evals/evals.json` from the skill directory
2. Spawns test runs WITH the skill loaded (via the skill's agent)
3. Spawns baseline runs WITHOUT the skill (vanilla Claude)
4. Grades each assertion as PASS or FAIL with specific evidence
5. Aggregates results into `benchmark.json` with pass rates, token usage, and timing
6. Opens an HTML viewer in your browser for human review

### Run a single eval manually

For a quick spot-check without the full suite:

```bash
# With skill (uses the agent that loads the skill)
claude -p "<eval prompt from evals.json>" --output-format json > with_skill.json

# Without skill (baseline)
claude -p "<eval prompt from evals.json>" --output-format json --disallowedTools "Skill(<skill-name> *)" > without_skill.json
```

Compare the two outputs against the assertions in `evals.json`.

## Where evals live

Each skill's evals are inside its own directory, following the [agentskills.io](https://agentskills.io/skill-creation/evaluating-skills) standard:

```
.claude/skills/<skill-name>/
├── SKILL.md
├── core.md
├── ...
└── evals/
    └── evals.json          # Test cases + assertions
```

Every `evals.json` includes a `_docs` field pointing back to this guide.

## Eval results (workspace)

Results are saved to a workspace directory alongside the repo root (gitignored via `*-workspace/`):

```
<skill-name>-workspace/
└── iteration-1/
    ├── benchmark.json          # Aggregated pass rates, token usage, timing
    ├── benchmark.md            # Human-readable summary
    └── eval-<name>/
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

Each iteration gets its own directory. When improving a skill, compare `iteration-N+1` against `iteration-N`.

## Interpreting results

| Metric | What it means |
|--------|--------------|
| Pass rate delta > 0 | Skill improves output quality vs baseline |
| Pass rate delta = 0 | Claude already handles this well without the skill — consider harder assertions |
| Token delta | Extra tokens the skill costs (~30-40% more is typical due to context injection) |
| High stddev | Flaky eval — skill instructions may be ambiguous, or the eval prompt is too open-ended |

## Cost and time expectations

| Scope | Subagent spawns | Estimated tokens | Estimated time |
|-------|----------------|-----------------|----------------|
| Single eval | 2 (with + without) | ~30-50k | 2-3 minutes |
| Full suite (7 evals) | 14 | ~200k | 10-15 minutes |
| With grading + benchmark | +1 grader agent | ~70k additional | +3-5 minutes |

## Which skills have evals

| Skill | Evals | Assertions | Negative controls |
|-------|-------|------------|-------------------|
| `diataxis-standards` | 10 | 45 | 3 |

To add evals to another skill, see [Adding evals to a skill](#adding-evals-to-a-skill) below.

## Adding evals to a skill

1. Create the evals directory:

```bash
mkdir -p .claude/skills/<skill-name>/evals
```

2. Create `evals.json` with the `_docs` pointer and test cases:

```json
{
  "skill_name": "<skill-name>",
  "_docs": "See docs/how-to-run-evals.md for instructions on running these evals",
  "evals": [
    {
      "id": 1,
      "name": "descriptive-name",
      "prompt": "Realistic user message",
      "expected_output": "What success looks like",
      "assertions": [
        "Specific, verifiable pass/fail check",
        "Another verifiable check"
      ]
    }
  ]
}
```

3. For negative controls (skill should NOT trigger), add `"should_trigger": false`:

```json
{
  "id": 8,
  "name": "negative-control-unrelated-task",
  "prompt": "A prompt the skill should NOT activate for",
  "expected_output": "The skill should not trigger",
  "should_trigger": false,
  "assertions": ["The skill should not activate for this request"]
}
```

### Tips for writing good evals

- Start with 2-3 test cases, expand after seeing first results
- Vary prompts: mix formal and casual, terse and detailed
- Cover edge cases: ambiguous requests, boundary conditions
- Use realistic context: file paths, column names, domain details
- Good assertions are specific and verifiable, not vague
- Include negative controls for adjacent skills that should NOT trigger

For the full methodology, see [agentskills.io: Evaluating skill output quality](https://agentskills.io/skill-creation/evaluating-skills).

## See also

- [How to Add a Skill](how-to-add-skill.md): create the skill that evals will test
- [Project Structure](project-structure.md): where eval files live in the repo
- [Architecture](architecture.md): how the agent+skill pattern works

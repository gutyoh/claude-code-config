# How to Run Evals

Evaluate whether the diataxis-standards skill produces correct, Diataxis-compliant documentation.

## Prerequisites

- Claude Code installed and authenticated
- `skill-creator` plugin installed (`/plugin` → Discover → skill-creator → Install for you)

## Run the evaluation

In any Claude Code session:

```
Use the skill-creator to evaluate the diataxis-standards skill
```

The skill-creator reads `evals/evals.json`, spawns test runs with and without the skill loaded, grades each assertion, and produces a benchmark report.

## What gets tested

| # | Eval | Quadrant | Assertions |
|---|------|----------|------------|
| 1 | Tutorial (getting-started) | Tutorial | 6 |
| 2 | How-to guide (deploy) | How-To Guide | 6 |
| 3 | Reference (API) | Reference | 6 |
| 4 | Explanation (architecture) | Explanation | 6 |
| 5 | Mixing violation detection | Review | 5 |
| 6 | Cross-references | How-To Guide | 5 |
| 7 | DOCUMENTATION_GUIDE.md generation | Reference | 8 |
| 8 | Negative: coding task | Should NOT trigger | 1 |
| 9 | Negative: git question | Should NOT trigger | 1 |
| 10 | Negative: design doc | Should NOT trigger | 1 |

**Total: 10 evals, 45 assertions, 3 negative controls.**

## Output

Results are saved to a workspace directory (gitignored):

```
diataxis-standards-workspace/
└── iteration-1/
    ├── benchmark.json      # Aggregated pass rates, token usage, timing
    ├── benchmark.md        # Human-readable summary
    └── eval-N/
        ├── with_skill/
        │   ├── outputs/
        │   ├── grading.json
        │   └── timing.json
        └── without_skill/
            ├── outputs/
            ├── grading.json
            └── timing.json
```

## Interpreting results

- **Pass rate delta > 0**: the skill improves output quality vs baseline
- **Token delta**: how many extra tokens the skill costs
- **Negative controls**: should show 0% trigger rate (skill should NOT activate)

## Adding more evals

Add test cases to `evals.json` following the existing format. Each eval needs:
- `id`: unique number
- `name`: descriptive slug
- `prompt`: realistic user message
- `expected_output`: what success looks like
- `assertions`: verifiable pass/fail checks
- `should_trigger` (optional): set to `false` for negative controls

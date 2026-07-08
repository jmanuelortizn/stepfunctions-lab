# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A 1-hour teaching lab that provisions an AWS Step Functions data pipeline via
Terraform, deliberately exercising **every core Step Functions concept** (Task,
Choice, Wait, Parallel, Map, Pass, Retry, Catch, Succeed, Fail, plus
ResultPath/Parameters/intrinsic functions). It is an interview/demo artifact,
not a production system — design choices optimize for observability and teaching,
not scale. Keep that framing when suggesting changes.

The `README.md` is the primary teaching artifact and is documentation-heavy
(English): a conceptual intro to Step Functions, a real-world use-cases table,
how the pipeline would be triggered in production, a concept map linking each
Step Functions feature to where it lives in the ASL, and interview talking
points. When you change the pipeline's behavior, states, or the ASL, keep the
README's architecture diagram, concept map, and trigger examples in sync —
several sections describe the concrete flow by name.

## Commands

```bash
terraform init
terraform plan
terraform apply
terraform destroy          # cleanup

# Trigger executions (ARNs are baked into these outputs):
terraform output -raw start_execution_happy_path      | bash   # Choice -> valid -> full pipeline
terraform output -raw start_execution_invalid_input   | bash   # Choice default -> Fail state
terraform output -raw start_execution_quality_failure | bash   # QualityCheck raises -> Catch -> HandleFailure
```

There is no build step, linter, or test suite. Lambda source is zipped at
`apply` time by the `archive_file` data source. State is local (no remote backend).

## Architecture

Three layers, tightly coupled by name:

1. **`statemachine/pipeline.asl.json`** — the Amazon States Language definition,
   a `templatefile()` with `${*_arn}` placeholders. This is the source of truth
   for the orchestration flow.
2. **`src/*.py`** — five single-file Lambda handlers, one per Task in the ASL.
   Each exports `handler(event, context)` and returns a dict that becomes the
   next state's input. No external dependencies (stdlib only).
3. **`*.tf`** — wiring. `lambdas.tf` and `step_functions.tf` hold the real logic;
   `variables.tf`, `outputs.tf`, `versions.tf` are supporting.

### The naming contract (critical)

Everything is keyed off the `local.lambda_functions` map in `lambdas.tf`. Each
map key must match, exactly:
- a file `src/<key>.py` exporting `handler` (packaged via `for_each`),
- a `${<key>_arn}` variable passed by `templatefile()` in `step_functions.tf`,
- a `"Resource": "${<key>_arn}"` reference in the ASL.

**To add a Lambda:** add the map entry in `lambdas.tf`, create `src/<key>.py`,
add the `<key>_arn = aws_lambda_function.pipeline["<key>"].arn` line to the
`templatefile()` call in `step_functions.tf`, then reference it in the ASL. The
`for_each` handles packaging, the function, and its log group automatically —
do not hand-write per-Lambda resources.

### Data flow through the pipeline

State output becomes the next state's input. The ASL threads a single evolving
JSON payload using `ResultPath` to graft results onto `$` without clobbering the
original (e.g. `$.parallel_results`, `$.processed_records`, `$.error`). The
Lambdas assume this shape — e.g. `IsInputValid` reads `$.is_valid` which
`validate_input.py` must set; `ProcessRecords` maps over `$.records`;
`BuildSummary` indexes `$.parallel_results[0]`/`[1]` (Parallel output is a
per-branch array). Changing a handler's return shape or an ASL `ResultPath` can
silently break a downstream state — trace the whole payload path when editing.

### Intentional behaviors (don't "fix" these)

- `validate_input.py` fails ~20% of the time via `TransientError` on purpose, so
  the Retry/backoff policy is visible in the execution history.
- `quality_check` raises on non-numeric record values to demonstrate Catch.
- Standard (not Express) workflow type, `MaxConcurrency=2` on the Map, and
  3-day log retention are deliberate teaching/cost choices, explained in
  comments in `step_functions.tf` and the README concept table.

## IAM

Least-privilege is a teaching point: the state machine role may only
`lambda:InvokeFunction` the five lab functions (`for` comprehension over the
Lambda ARNs in `step_functions.tf`); Lambdas get only `AWSLambdaBasicExecutionRole`.
Preserve this when adding permissions — scope to specific resources, not `*`
(the logs `*` block is a documented Step Functions requirement, the one exception).

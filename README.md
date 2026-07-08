# Step Functions Lab — Data Pipeline with Terraform

A 1-hour lab that deploys a data pipeline orchestrated with AWS Step
Functions, using **every core concept of the service**, all provisioned
with Terraform. Cost: pennies (5 Lambdas + 1 Standard state machine, logs
with 3-day retention).

## What are Step Functions? (start here)

AWS Step Functions is a **serverless orchestrator**. You describe a
workflow as a state machine — a set of steps ("states") and the
transitions between them — and AWS runs it for you: invoking services,
passing data from one step to the next, retrying failures, branching on
conditions, and recording every step of every run.

The mental shift: instead of writing one big function that calls service A,
waits, calls service B, handles errors, retries, and logs progress — all
tangled together in code — you **move that coordination logic out of your
code and into a declarative definition** (the Amazon States Language, or
ASL). Your Lambdas become small, single-purpose, and stateless; the *flow*
lives in the state machine.

### The two core components

There are really just two things to understand:

| Component | Role | In one line |
|---|---|---|
| **State machine** | The overall workflow — defines the sequence, branching, retries, and flow between steps. | *Controls the flow.* |
| **Task state** | An individual unit of work — usually invokes another AWS service, most commonly a Lambda (but it can integrate directly with SQS, API Gateway, and others, with no glue code). | *Does the actual work.* |

### The main state types

| State | What it does |
|---|---|
| **Pass** | Moves data through without doing any work (reshape/inject). |
| **Task** | Performs work — invokes a Lambda, sends a message to SQS, etc. |
| **Choice** | Adds branching logic based on conditions. |
| **Wait** | Pauses execution for a defined amount of time. |
| **Parallel** | Runs multiple branches at the same time. |
| **Map** | Takes an array and runs the same steps for each item. |
| **Succeed** | Ends the workflow successfully. |
| **Fail** | Ends the workflow with an error. |

### Why teams reach for it

- **The workflow becomes visible.** The console draws your pipeline as a
  graph and lights up each step as it runs. When something breaks at 3am,
  you *see* which step failed and the exact input/output — no
  grep-through-logs archaeology.
- **Retries and error handling are configuration, not code.** "Retry this
  step 3 times with exponential backoff, but if it's a data error, jump to
  the failure handler" is a few lines of JSON, applied consistently.
- **Built-in durability and state.** A Standard workflow can run for up to
  a year, survive failures, and remember exactly where it was — without you
  managing a database of "what step is this job on?".
- **It waits for free.** Steps can pause for seconds, days, or until a human
  approves — you're not paying for idle compute while it waits.
- **The execution history is free auditing.** Every run is recorded
  step-by-step: what ran, with what data, in what order.

### The trade-off

You're trading a bit of upfront structure (defining states, thinking about
how data flows between them) for operational clarity. For a single quick
Lambda, it's overkill. For anything with **multiple steps, retries,
branching, or that someone will have to debug later**, it usually pays off.

### Real-life use cases

| Scenario | How Step Functions helps |
|---|---|
| **ETL / data pipelines** | Extract → validate → transform → load, with retries per stage and fan-out (Map) over batches of records. This lab is a miniature of exactly this. |
| **Order / payment processing** | Reserve inventory → charge card → notify shipping. If the charge fails, run a **compensating** step (release the inventory) — the "saga" pattern. |
| **Human-in-the-loop approvals** | Submit request → **pause** → wait for a manager to click approve/reject (could be days) → continue. No polling, no idle cost. |
| **Microservice orchestration** | Coordinate a call across several services/Lambdas, keeping each one small and stateless while the flow and error handling live in one place. |
| **ML pipelines** | Preprocess data → train model → evaluate → conditionally deploy, with long-running steps and branching on evaluation metrics. |
| **Media / batch processing** | Fan out over thousands (or millions, with Distributed Map) of files — transcode, resize, scan — with `MaxConcurrency` protecting downstream systems. |
| **Scheduled / event-driven jobs** | Kicked off by EventBridge (cron or an event), run a multi-step job with built-in retries and alerting on failure. |

### Standard vs Express (which flavor)

- **Standard** — durable, exactly-once, runs up to a year, billed per state
  transition. For pipelines, business processes, human approvals. *This lab
  uses Standard.*
- **Express** — high-volume and short-lived (<5 min), at-least-once, billed
  per request + duration. For streaming, IoT, high-throughput event
  processing.

## Architecture

```
ValidateInput (Task + Retry + Catch)
      │
IsInputValid (Choice) ──false──> InvalidInputFail (Fail)
      │ true
WaitForBatchWindow (Wait 5s)
      │
EnrichAndCheckQuality (Parallel + Catch)
   ├─ EnrichData (Task)
   └─ QualityCheck (Task + Retry)   ── error ──> HandleFailure (Pass) ─> PipelineFailed (Fail)
      │
ProcessRecords (Map, MaxConcurrency=2)
   └─ ProcessSingleRecord (Task + Retry)
      │
BuildSummary (Pass + intrinsic functions)
      │
Notify (Task)
      │
PipelineSucceeded (Succeed)
```

## The use case, and how it'd be triggered in production

This lab models a **batch data-ingestion pipeline**: a payload arrives with
a `source` and a list of `records`, the pipeline validates it, waits for a
short batching window, enriches and quality-checks the batch (in parallel),
processes each record (fanning out with a bounded concurrency), assembles a
summary, and notifies a downstream consumer — with explicit success and
failure paths throughout. It's a miniature of the kind of ETL/order-style
workflow described in the use-cases table above.

In a real application you almost never start an execution by hand. The state
machine exposes a `StartExecution` API, so anything that can call AWS can
kick it off — and the input JSON this lab passes on the command line is
exactly what that caller would send:

- **An API / backend service** calls `StartExecution` via the AWS SDK when a
  user submits a request (e.g. an order is placed, a file is uploaded).
- **EventBridge** triggers it on a schedule (cron-style batch job) or in
  reaction to an event from another service.
- **S3 event notifications** start an execution when a new object lands in a
  bucket — the classic "file dropped → process it" pattern.
- **API Gateway** invokes it directly (no Lambda in between) to expose the
  workflow as an HTTP endpoint.
- **SQS / a queue consumer** pulls messages and launches an execution per
  batch, decoupling producers from the pipeline.

In every case the trigger just hands Step Functions the initial JSON and
walks away; the orchestrator owns the sequencing, retries, error handling,
and the full execution record from there.

## Deploy

```bash
terraform init
terraform plan
terraform apply

# Happy path (check the outputs for the 3 ready-to-run commands):
terraform output -raw start_execution_happy_path | bash
```

Then open the Step Functions console and watch the execution in the graph
inspector — you'll see the Wait, the two Parallel branches running in
parallel, and the Map fan-out. Also run the other two commands from the
outputs to see the Choice → Fail and the Catch → HandleFailure.

Note: `validate_input` fails randomly ~20% of the time on purpose, so you
can see the **Retry with exponential backoff** in the execution history.

Cleanup: `terraform destroy`.

## Concept map → where each one lives

| Concept | Description (what it's for) | State in the ASL | What it demonstrates |
|---|---|---|---|
| **Task** | Invokes a unit of work — a Lambda or another AWS service — and waits for its result. | `ValidateInput`, `Notify`, etc. | Invoke a Lambda (most common integration) |
| **Retry** | Automatically re-attempts a failed step with a backoff strategy before giving up. | `ValidateInput` | Exponential backoff on transient errors |
| **Catch** | Intercepts an error and reroutes the flow to a recovery handler instead of failing outright. | `ValidateInput`, `EnrichAndCheckQuality` | Route fatal errors to a handler |
| **Choice** | Picks the next state based on the data in the payload (if/else branching). | `IsInputValid` | Branching on data (`BooleanEquals`) |
| **Wait** | Delays the workflow for a fixed duration, until a timestamp, or a value from the payload. | `WaitForBatchWindow` | Fixed or dynamic pauses (`SecondsPath`) |
| **Parallel** | Runs several independent branches at once and gathers all their results. | `EnrichAndCheckQuality` | Concurrent branches; output = array per branch |
| **Map** | Iterates the same steps over every item in an array, optionally bounding concurrency. | `ProcessRecords` | Fan-out over `$.records` with `MaxConcurrency` |
| **Pass** | Forwards data along, optionally transforming or injecting fields, without calling any service. | `BuildSummary`, `HandleFailure` | Reshape without compute + intrinsic functions (`States.ArrayLength`) |
| **Succeed / Fail** | Terminates the execution — cleanly, or with an explicit error and cause. | `PipelineSucceeded`, `PipelineFailed` | Explicit terminal states |
| **ResultPath / Parameters** | Shape what a state receives and where its result is grafted onto the payload. | various | Input/output processing (the topic that confuses most) |
| **Standard vs Express** | Selects the workflow tier — durability, duration limit, and pricing model. | `type = "STANDARD"` in TF | See comment in `step_functions.tf` |
| **Observability** | Ships the full execution history to CloudWatch Logs for tracing and debugging. | `logging_configuration` | Execution history to CloudWatch Logs |
| **IAM least privilege** | Grants the state machine only the permissions it actually needs. | `step_functions.tf` | The SM can only invoke its 5 Lambdas |

## Interview talking points

- **Why Step Functions instead of just chained Lambdas?** The state, the
  retries, the error handling, and the visibility live in the
  orchestrator, not scattered across code. The execution history is free
  auditing.
- **Standard vs Express**: Standard = durable, exactly-once, up to 1 year,
  billed per state transition — ideal for data pipelines and business
  processes. Express = high volume, <5 min, at-least-once, billed per
  request/duration — ideal for streaming/IoT.
- **Map with MaxConcurrency**: controls the fan-out so you don't overwhelm
  downstream (API rate limits, DB connections). Distributed Map scales to
  millions of items reading directly from S3.
- **ResultPath vs OutputPath vs Parameters**: `Parameters` shapes the
  task's input, `ResultPath` decides where to inject the result without
  losing the original payload, `OutputPath` filters what comes out.
- **Selective Retry**: transient errors are retried
  (`Lambda.TooManyRequestsException`), never data errors — those go to
  Catch. Retrying bad data just burns money.
- **Terraform**: `templatefile()` injects the ARNs into the ASL, `for_each`
  over a `local` generates the 5 Lambdas without copy-paste, explicit log
  groups to control retention (cost) from IaC.

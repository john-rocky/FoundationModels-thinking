# DeepThinkKit

**Multi-pass reasoning and memory orchestration for Apple Foundation Models.**

Instead of asking the model once and hoping for the best, DeepThinkKit lets you compose multiple stages — analysis, planning, solving, critique, revision, merging, and finalization — into structured reasoning pipelines.

It is designed as an **engineering lab** for testing how far device-scale Foundation Models can go with staged prompting, branching, critique loops, and external memory.

Ships with a ChatGPT-style SwiftUI app for iOS and macOS.

```
Direct (single pass):    Query --> Response

DeepThink (multi-pass):  Query --> Analyze --> Plan --> Solve --> Critique --> Revise --> Finalize
```

---

## Why

Apple Foundation Models are great for lightweight, on-device tasks, but complex reasoning often breaks when everything is done in a single pass.

DeepThinkKit explores a different approach:

- Split one query into multiple stages
- Give each stage a clear role
- Pass intermediate outputs to the next stage
- Optionally branch, critique, revise, or aggregate
- Attach memory and trace the full execution

The goal is not to pretend the model is larger than it is.
The goal is to make reasoning behavior **observable, comparable, and hackable**.

---

## Quick Start

### As a Swift Package

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/john-rocky/DeepThinkKit.git", branch: "main")
]
```

```swift
import DeepThinkKit

let provider = FoundationModelProvider()
let context = PipelineContext(modelProvider: provider)

// CritiqueLoop: Analyze -> Solve -> Critique -> Revise -> Finalize
let pipeline = PipelineFactory.create(kind: .critiqueLoop)
let result = try await pipeline.execute(query: "Explain quantum computing to a 10-year-old", context: context)

print(result.finalOutput.content)

// Inspect intermediate stage outputs
for stage in result.stageOutputs {
    print("[\(stage.stageKind.rawValue)] \(stage.content.prefix(100))...")
}
```

### Running the App

```bash
git clone https://github.com/john-rocky/DeepThinkKit.git
cd DeepThinkKit
open DeepThinkApp.xcodeproj
```

Select the `DeepThinkApp_macOS` or `DeepThinkApp_iOS` scheme in Xcode and Run.

> **Requirements:** Xcode 26+, iOS 26+ / macOS 26+, Apple Silicon (M1+ / A17 Pro+), Apple Intelligence enabled

---

## Pipelines

| Pipeline | Flow | Best for |
|---|---|---|
| **Direct** | Query -> Response | Single-pass baseline for comparison |
| **Sequential** | Analyze -> Plan -> Solve -> Finalize | Structured answers, complex linear tasks |
| **CritiqueLoop** | Analyze -> Solve -> (Critique -> Revise) x N -> Finalize | Iterative refinement, catching omissions |
| **BranchMerge** | Analyze -> {Solve A, B, C} -> Merge -> Finalize | Diversity of answers, parallel exploration |
| **SelfConsistency** | Analyze -> {Solve 1, 2, 3} -> Aggregate -> Finalize | Consensus filtering, stability testing |

### CritiqueLoop in Detail

```
User: "Organize the ethical challenges of AI"

[Analyze]   Identify the core question, required knowledge areas, hidden assumptions (no answering)
    |
[Solve]     Generate an answer based on the analysis
    |
[Critique]  Verify factual accuracy, logical consistency, coverage, and clarity; flag issues
    |
[Revise]    Fix only what critique identified (keep everything else intact)
    |
    ^ (repeat if confidence is below threshold)
    |
[Finalize]  Remove internal notes and format for readability (content unchanged)
```

---

## Stage Roles

Each stage has a narrow, role-specific responsibility:

- **Analyze** — Identifies the core question, hidden assumptions, constraints, and ambiguities
- **Plan** — Designs how the answer should be structured
- **Solve** — Produces the actual answer following the analysis and plan
- **Critique** — Acts as a reviewer, pointing out weaknesses
- **Revise** — Repairs only what critique identified
- **Merge** — Combines the strongest parts from multiple parallel branches
- **Aggregate** — Trusts majority agreement over isolated claims
- **Finalize** — Formats the result without changing content

Each stage runs in a **fresh session** — no hidden conversational carry-over. All coordination happens through explicit context injection.

---

## Comparing Pipelines

```swift
let comparator = StrategyComparator()
let result = try await comparator.compare(
    query: "Challenges and solutions for renewable energy",
    pipelines: [
        PipelineFactory.create(kind: .direct),
        PipelineFactory.create(kind: .critiqueLoop),
    ],
    modelProvider: FoundationModelProvider()
)

for (name, metrics) in result.results {
    print("\(name): confidence=\(metrics.averageConfidence), latency=\(metrics.totalLatency)s")
}
```

The app's **Compare tab** provides a GUI for side-by-side comparison with latency bar charts, thinking overhead ratios, and output diffs.

---

## Memory Model

DeepThinkKit uses a layered memory model to keep useful information outside the model and re-inject only what matters.

| Layer | Lifetime | Purpose |
|---|---|---|
| **SessionMemory** | During execution | Recent conversation history |
| **WorkingMemory** | During pipeline run | Intermediate stage outputs (analysis, plan, critique findings, candidate answers) |
| **LongTermMemory** | Persistent (JSON file) | Facts, decisions, constraints, summaries stored and retrieved across runs |

```swift
// Save to long-term memory
let memory = LongTermMemory()
try await memory.save(MemoryEntry(kind: .fact, content: "Project X deadline is end of March", tags: ["project-x"]))

// Retrieve in a future run
let hits = try await memory.search(MemorySearchQuery(text: "Project X", limit: 3))
```

---

## Tracing

Each run can record the full execution trace:

- Pipeline name and stage order
- Inputs and recalled memory per stage
- Raw model output and parsed output
- Retry attempts and convergence decisions
- Confidence scores and duration
- Failure reasons

```swift
let result = try await pipeline.execute(query: "...", context: context)

for record in result.trace {
    print("[\(record.stageName)] \(record.duration)s - confidence: \(record.confidence ?? 0)")
    if !record.memoryHits.isEmpty {
        print("  memory hits: \(record.memoryHits)")
    }
    if let error = record.error {
        print("  ERROR: \(error)")
    }
}
```

In the app, each message has a **Show Trace** button to inspect per-stage inputs, outputs, duration, and confidence inline.

---

## Retry and Convergence

Built-in controls keep multi-pass experiments bounded and debuggable:

- Retry a failed stage up to a configurable limit
- Stop critique/revise loops after a maximum number of iterations
- Stop when confidence reaches a target threshold
- Stop when improvement falls below a minimum delta
- Roll back to the best-so-far answer if quality degrades

---

## Architecture

```
+---------------------------------------------+
|                  App Layer                   |
|   SwiftUI Chat / Compare / Memory Browser   |
+---------------------------------------------+
|               DeepThinkKit                   |
|                                              |
|  Pipeline --> Stage --> ModelProvider         |
|  (Direct,      (Analyze,   (FoundationModel  |
|   Sequential,   Plan,       Provider)        |
|   CritiqueLoop, Solve,                       |
|   BranchMerge,  Critique,                    |
|   SelfConsis.)  Revise,                      |
|                 Finalize)                    |
|                                              |
|  Memory <--> Trace <--> Evaluation           |
|  (Session,     (Record,    (Metrics,          |
|   Working,      Collector)  Comparator)       |
|   LongTerm)                                  |
+---------------------------------------------+
         |
         v
   Apple Foundation Models (on-device)
```

---

## Design Principles

- **Fresh sessions per stage** — No hidden shared chat history across stages
- **Explicit context passing** — Previous outputs are summarized and injected intentionally
- **Role-separated prompts** — Each stage is specialized, not overloaded
- **Trace first** — Intermediate reasoning matters, not just the final answer
- **Experiment-friendly** — Pipelines are easy to swap, compare, and extend

---

## What DeepThinkKit Is Not

- A ChatGPT replacement
- A general-purpose agent platform
- A training or fine-tuning framework
- A generic RAG backend

---

## Requirements

- Xcode 26+
- iOS 26.0+ / macOS 26.0+
- Apple Silicon (M1+ / A17 Pro+)
- Apple Intelligence enabled (Settings -> Apple Intelligence & Siri)

---

## License

Apache License 2.0 — See [LICENSE](LICENSE) for details.

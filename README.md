# DeepThinkKit

**Multi-pass reasoning and memory orchestration for Apple Foundation Models.**

Instead of asking the model once and hoping for the best, DeepThinkKit lets you compose multiple stages — solving, verification, constraint extraction, deterministic solving, and explanation — into structured reasoning pipelines.

It is designed as an **engineering lab** for testing how far device-scale Foundation Models can go with staged prompting, independent verification, and external memory.

Ships with a ChatGPT-style SwiftUI app for iOS and macOS.

```
Direct (single pass):    Query --> Response

Rethink (multi-pass):    Query --> Solve --> Verify (independent) --> Final Answer

Verified (CSP):          Query --> Extract Constraints --> Deterministic Solve --> Explain
```

---

## Why

Apple Foundation Models are great for lightweight, on-device tasks, but complex reasoning often breaks when everything is done in a single pass.

DeepThinkKit explores a different approach:

- Split one query into multiple stages
- Give each stage a clear role
- Pass intermediate outputs to the next stage
- Verify answers independently in a fresh session
- Optionally extract constraints and solve deterministically
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

#### Basic Usage

```swift
import DeepThinkKit

let provider = FoundationModelProvider()
let context = PipelineContext(modelProvider: provider)
let pipeline = PipelineFactory.create(kind: .rethink)

let result = try await pipeline.execute(query: "Explain quantum computing to a 10-year-old", context: context)
print(result.finalOutput.content)
```

#### Streaming with Real-Time UI Updates

```swift
import DeepThinkKit

let provider = FoundationModelProvider()
let context = PipelineContext(modelProvider: provider)
let pipeline = PipelineFactory.create(kind: .rethink)

// Set up event stream
let (stream, continuation) = AsyncStream<PipelineEvent>.makeStream()
await context.setEventContinuation(continuation)

// Run pipeline in background
Task.detached {
    let result = try await pipeline.execute(query: "Why is the sky blue?", context: context)
    await context.finishEventStream()
}

// Consume events for real-time UI
for await event in stream {
    switch event {
    case .pipelineStarted(let name, let stageCount):
        print("Pipeline: \(name) (\(stageCount) stages)")
    case .stageStarted(let name, _, _):
        print("  Starting: \(name)")
    case .stageStreamingContent(let name, let content):
        print("  [\(name)] \(content.suffix(40))...")
    case .stageCompleted(let name, _, _, _):
        print("  Completed: \(name)")
    default:
        break
    }
}
```

#### With Web Search

```swift
let config = PipelineConfiguration(
    webSearchEnabled: true,
    maxSearchDepth: 1        // Set to 3 for deep search
)
let pipeline = PipelineFactory.create(kind: .rethink, configuration: config)
let result = try await pipeline.execute(query: "Latest Swift concurrency features", context: context)
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
| **Direct** | Query -> Response | Simple questions, greetings, fast baseline |
| **Rethink** | Solve -> Verify (independent) | General reasoning, fact-checking, accuracy |
| **Verified** | Extract Constraints -> CSP Solve -> Explain | Logic puzzles, constraint problems, deterministic answers |
| **Auto** | Classifies query, then routes to Direct / Rethink / Verified | Default mode — picks the best pipeline automatically |

### Rethink Pipeline

```
User: "What are the ethical challenges of AI?"

[Solve]     Analyze the question and generate an answer with explicit state tracking
    |
[Verify]    Re-solve independently in a fresh session, compare with original,
            improve if the new answer is better
    |
--> Final Answer
```

Each stage runs in a **fresh session** — no hidden conversational carry-over. The Verify stage independently re-solves the problem and compares both answers, keeping the stronger one.

### Verified Pipeline (CSP)

```
User: "A is not next to B. C is before D. B is at position 3."

[Extract]   Use LLM + @Generable to extract variables, domains, and constraints
    |
[Solve]     Run deterministic CSP solver (no LLM) — brute-force all valid assignments
    |
[Explain]   Generate human-readable explanation of the solution
    |
--> Final Answer
```

The Solve stage uses a **deterministic constraint solver**, not the LLM, so the answer is provably correct when constraints are extracted properly.

### Auto Classification

When `PipelineKind.auto` is selected, `PipelineClassifier` routes the query:

- **Greetings / short input** -> Direct
- **Math / puzzles / constraints** -> Verified
- **Everything else** -> Rethink

Classification uses heuristic pattern matching (no LLM call).

---

## Streaming Events

DeepThinkKit provides real-time pipeline events via `AsyncStream<PipelineEvent>` for building responsive UIs.

### Event Types

| Event | When |
|---|---|
| `pipelineStarted(name, stageCount)` | Pipeline execution begins |
| `stageStarted(name, kind, index)` | A stage begins execution |
| `stageStreamingContent(name, content)` | Token-by-token streaming output (cumulative) |
| `stageCompleted(name, kind, output, index)` | A stage finishes successfully |
| `stageFailed(name, error)` | A stage fails |
| `stageRetrying(name, attempt)` | A stage is being retried |
| `webSearchStarted(keywords)` | Web search begins |
| `webSearchCompleted(resultCount)` | Web search finished |
| `webPageFetchStarted(count)` | Fetching web pages |
| `deepSearchRoundStarted(round, keywords)` | Multi-round deep search |
| `autoClassified(resolvedKind)` | Auto mode selected a pipeline |
| `pipelineCompleted(result)` | Pipeline finished with result |

---

## Web Search

Pipelines can optionally perform web search using DuckDuckGo before answering.

```swift
let config = PipelineConfiguration(
    webSearchEnabled: true,
    maxSearchResults: 5,
    webSearchContextBudget: 2000,  // Max chars of search context injected into prompt
    maxSearchDepth: 1              // 1 = single round, 3 = deep search with LLM evaluation
)
```

The `WebSearchStage` autonomously decides whether search is needed based on the query, extracts keywords, fetches pages, and injects relevant content into the prompt.

Custom search providers can be implemented via the `WebSearchProvider` protocol.

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

Memory entries have `.kind` (fact, decision, constraint, summary, critique, etc.), `.tags`, `.priority` (low/normal/high/pinned), and `.source` for traceability.

---

## Tracing

Each run records the full execution trace:

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

## Custom Model Provider

`ModelProvider` is a protocol — you can plug in any backend:

```swift
public protocol ModelProvider: Sendable {
    func generate(systemPrompt: String?, userPrompt: String) async throws -> String
    func generateStream(systemPrompt: String?, userPrompt: String) -> AsyncThrowingStream<String, Error>
}
```

`FoundationModelProvider` is the built-in implementation using Apple's on-device Foundation Models. The `generateStream` default implementation wraps `generate` in a single-yield stream, so you only need to implement `generate` for basic providers.

---

## Benchmarks

DeepThinkKit includes a benchmark suite for comparing pipeline accuracy:

```swift
let runner = BenchmarkRunner()
let report = await runner.run(
    problems: BenchmarkProblem.standardSet,
    pipelineKinds: [.direct, .rethink, .verified],
    modelProvider: FoundationModelProvider(),
    onProgress: { stage, current, total in
        print("\(stage) \(current)/\(total)")
    }
)

for (kind, accuracy) in report.pipelineAccuracies {
    print("\(kind.displayName): \(String(format: "%.0f%%", accuracy * 100))")
}
```

The app includes a **Benchmark tab** for running evaluations with progress UI and per-problem result inspection.

---

## Architecture

```
+---------------------------------------------+
|                  App Layer                   |
|   SwiftUI Chat / Benchmark / Memory Browser  |
+---------------------------------------------+
|               DeepThinkKit                   |
|                                              |
|  Pipeline --> Stage --> ModelProvider         |
|  (Direct,      (Solve,     (Foundation       |
|   Rethink,      Verify,     ModelProvider)    |
|   Verified)     Extract,                     |
|                 Explain,                     |
|                 WebSearch)                   |
|                                              |
|  PipelineEvent  Memory        Trace          |
|  (AsyncStream)  (Session,     (Record,       |
|                  Working,     Collector)      |
|                  LongTerm)                   |
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
- **Deterministic where possible** — CSP solver provides provably correct answers for constraint problems
- **Streaming first** — Real-time events for responsive UIs
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

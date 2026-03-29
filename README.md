<p align="center">
  <img src="https://github.com/user-attachments/assets/8259bc35-5dfd-4bf1-b426-d2bfa0e27b61" alt="DeepThinkKit" width=600>
</p>

<h3 align="center">Make Apple Foundation Models think harder.</h3>

<p align="center">
  Multi-pass reasoning & memory orchestration — fully on-device, fully private, zero API cost.
</p>

<p align="center">
  <a href="#quick-start"><img src="https://img.shields.io/badge/Swift_Package-compatible-orange?style=for-the-badge&logo=swift&logoColor=white" alt="Swift Package"></a>&nbsp;
  <img src="https://img.shields.io/badge/iOS_26%2B_%7C_macOS_26%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Platform">&nbsp;
  <img src="https://img.shields.io/badge/100%25_On--Device-34C759?style=for-the-badge" alt="On-device">&nbsp;
  <a href="LICENSE"><img src="https://img.shields.io/badge/Apache_2.0-blue?style=for-the-badge" alt="License"></a>
</p>

<br>

<p align="center">
  <img src="https://private-user-images.githubusercontent.com/23278992/570943422-50401d1a-5463-4a7a-93d7-d2b447712846.gif?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NzQ3NjE4OTcsIm5iZiI6MTc3NDc2MTU5NywicGF0aCI6Ii8yMzI3ODk5Mi81NzA5NDM0MjItNTA0MDFkMWEtNTQ2My00YTdhLTkzZDctZDJiNDQ3NzEyODQ2LmdpZj9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNjAzMjklMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjYwMzI5VDA1MTk1N1omWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPTk5NTgyNjBmODY5MmI4NTY1NjUxYzQ5OTY1NDBkN2UzYTQzYTRjMmU3NzBhYmI5ZjVlZGI3NDUzY2U5MzAxM2EmWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.TAxud-t34dMyrRpG95g0GxT-nhSYgIM-aN6UeRIAhas" alt="Chat Demo" width="280">
</p>

<p align="center">
  <sub><b>Multi-pass reasoning with real-time thinking visualization</b></sub>
</p>

<br>

## Why?

Apple Foundation Models are fast, private, and free — but **one-pass reasoning breaks on hard questions**.

DeepThinkKit takes a different approach: split the problem, solve it, then verify independently.

```
                        ┌──── Single Pass ────┐
  Typical LLM:          Query ────────────────── Answer     (hope for the best)

                        ┌──── Multi Pass ─────────────────────────┐
  DeepThinkKit:          Query ──> Solve ──> Verify (fresh) ──> Answer ✅
                                              │
                                    independent re-solve
                                    no confirmation bias
```

> **The verifier never sees the solver's reasoning.** It re-solves from scratch and picks the stronger answer.

---

## How It Works

<table>
<tr>
<td width="33%" align="center">
<h3>1. Solve</h3>
<sub>Fresh session with explicit state tracking</sub>
</td>
<td width="33%" align="center">
<h3>2. Verify</h3>
<sub>Independent re-solve in isolated session</sub>
</td>
<td width="33%" align="center">
<h3>3. Answer</h3>
<sub>Strongest reasoning wins</sub>
</td>
</tr>
</table>

DeepThinkKit ships **4 pipelines** — pick one, or let Auto choose for you:

| Pipeline | Flow | Best For |
|:---|:---|:---|
| **Auto** | Classifies & routes automatically | Default — just works |
| **Direct** | `Query → Answer` | Simple questions, fast baseline |
| **Rethink** | `Query → Solve → Verify → Answer` | General reasoning, accuracy |
| **Verified** | `Query → Extract → CSP Solve → Explain` | Logic puzzles, math — **provably correct** |

---

## Quick Start

**Install**

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/john-rocky/DeepThinkKit.git", branch: "main")
]
```

**3 lines to think deeper**

```swift
import DeepThinkKit

let context = PipelineContext(modelProvider: FoundationModelProvider())
let pipeline = PipelineFactory.create(kind: .rethink)
let result = try await pipeline.execute(query: "Why do we dream?", context: context)

print(result.finalOutput.content) // Verified, multi-pass answer
```

**Stream the thinking process**

```swift
let (stream, continuation) = AsyncStream<PipelineEvent>.makeStream()
await context.setEventContinuation(continuation)

Task {
    let result = try await pipeline.execute(query: "Why is the sky blue?", context: context)
    await context.finishEventStream()
}

for await event in stream {
    switch event {
    case .stageStarted(let name, _, _):
        print("⟳ \(name)")
    case .stageStreamingContent(_, let content):
        print(content)
    case .stageCompleted(let name, _, _, _):
        print("✓ \(name)")
    default: break
    }
}
```

---

## Web Search

Pipelines can search the web before reasoning — powered by DuckDuckGo, with multi-round deep search.

<p align="center">
  <img src="https://github.com/user-attachments/assets/3d3726d6-cadb-4ebd-90a5-30556df1abe0" alt="Web Search Demo" width="280">
</p>

```swift
let config = PipelineConfiguration(
    webSearchEnabled: true,
    maxSearchDepth: 3  // Deep search: multiple rounds with LLM evaluation
)
let pipeline = PipelineFactory.create(kind: .rethink, configuration: config)
```

---

## Key Capabilities

<table>
<tr>
<td width="50%">

### Memory System

Three-layer architecture for persistent context:

| Layer | Lifetime | Purpose |
|:---|:---|:---|
| **Session** | Execution | Conversation history |
| **Working** | Pipeline run | Stage intermediates |
| **LongTerm** | Persistent | Facts across sessions |

```swift
let memory = LongTermMemory()
try await memory.save(MemoryEntry(
    kind: .fact,
    content: "User prefers concise answers",
    tags: ["preference"]
))
```

</td>
<td width="50%">

### Execution Tracing

Every run is fully observable — no black boxes.

```swift
let result = try await pipeline.execute(
    query: "...", context: context
)

for record in result.trace {
    print("""
    [\(record.stageName)]
      \(record.duration)s
      confidence: \(record.confidence ?? 0)
    """)
}
```

The app includes a **Show Trace** button on every message for inline inspection.

</td>
</tr>
<tr>
<td>

### Deterministic CSP Solver

For logic puzzles and constraint problems, the solver is **not an LLM** — it's a brute-force constraint satisfaction engine.

```
Extract constraints (LLM)
        ↓
Solve deterministically (no LLM)
        ↓
Explain solution (LLM)
```

Provably correct when constraints are extracted properly.

</td>
<td>

### Pluggable Model Providers

`ModelProvider` is a protocol — bring your own backend:

```swift
struct MyProvider: ModelProvider {
    func generate(
        systemPrompt: String?,
        userPrompt: String
    ) async throws -> String {
        // Your API call here
    }

    func generateStream(
        systemPrompt: String?,
        userPrompt: String
    ) -> AsyncThrowingStream<String, Error> {
        // Streaming API call
    }
}
```

</td>
</tr>
</table>

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│               Your SwiftUI App                  │
│         Chat  ·  Benchmark  ·  Memory           │
├─────────────────────────────────────────────────┤
│                                                 │
│   Pipeline ──> Stage ──> ModelProvider          │
│   (Auto,       (Solve,    (FoundationModel      │
│    Rethink,     Verify,    Provider)             │
│    Verified,    Extract,                        │
│    Direct)      Explain,                        │
│                 WebSearch)                       │
│                                                 │
│   Events          Memory           Trace        │
│   AsyncStream     Session/Working  Per-stage    │
│                   /LongTerm        recording    │
│                                                 │
├─────────────────────────────────────────────────┤
│        Apple Foundation Models (on-device)       │
└─────────────────────────────────────────────────┘
```

---

## Run the App

```bash
git clone https://github.com/john-rocky/DeepThinkKit.git
cd DeepThinkKit
open DeepThinkApp.xcodeproj
```

Select `DeepThinkApp_iOS` or `DeepThinkApp_macOS` and run.

**Included:** Chat UI with pipeline selection, real-time thinking visualization, execution trace inspector, pipeline comparison, memory browser, benchmark runner.

---

## Requirements

| | |
|:---|:---|
| **Xcode** | 26+ |
| **Platform** | iOS 26.0+ / macOS 26.0+ |
| **Hardware** | Apple Silicon (M1+ / A17 Pro+) |
| **Setting** | Apple Intelligence enabled |

---

<p align="center">
  <a href="LICENSE"><b>Apache License 2.0</b></a>
</p>

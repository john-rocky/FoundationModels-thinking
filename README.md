<p align="center">
  <img src="https://github.com/user-attachments/assets/8259bc35-5dfd-4bf1-b426-d2bfa0e27b61" alt="DeepThinkKit" width=600>
</p>

<p align="center">
  <b>Make Apple Foundation Models think harder.</b><br>
  Multi-pass reasoning & memory orchestration — fully on-device.
</p>

<p align="center">
  <a href="#quick-start"><img src="https://img.shields.io/badge/Swift_Package-compatible-orange?style=flat-square&logo=swift" alt="Swift Package"></a>
  <img src="https://img.shields.io/badge/platform-iOS_26%2B_%7C_macOS_26%2B-blue?style=flat-square&logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/100%25-on--device-green?style=flat-square" alt="On-device">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache_2.0-lightgrey?style=flat-square" alt="License"></a>
</p>

<br>

<p align="center">
  <img src="https://private-user-images.githubusercontent.com/23278992/570943422-50401d1a-5463-4a7a-93d7-d2b447712846.gif?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NzQ3NjE4OTcsIm5iZiI6MTc3NDc2MTU5NywicGF0aCI6Ii8yMzI3ODk5Mi81NzA5NDM0MjItNTA0MDFkMWEtNTQ2My00YTdhLTkzZDctZDJiNDQ3NzEyODQ2LmdpZj9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNjAzMjklMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjYwMzI5VDA1MTk1N1omWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPTk5NTgyNjBmODY5MmI4NTY1NjUxYzQ5OTY1NDBkN2UzYTQzYTRjMmU3NzBhYmI5ZjVlZGI3NDUzY2U5MzAxM2EmWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.TAxud-t34dMyrRpG95g0GxT-nhSYgIM-aN6UeRIAhas" alt="Chat Demo" width="280">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
</p>

<br>

---

## The Problem

Apple Foundation Models are fast, private, and free — but ask a hard question and the answer falls apart.

**DeepThinkKit fixes this.** Instead of one pass, it orchestrates multiple reasoning stages — solving, verifying, constraint-extracting, and explaining — each in an isolated session with no hidden context carry-over.

```
Direct (1 pass):     Query ──────────────────────────────────> Answer

Rethink (2 pass):    Query ──> Solve ──> Verify (fresh) ──> Answer  ✅ More accurate

Verified (CSP):      Query ──> Extract ──> Deterministic Solve ──> Explain  ✅ Provably correct
```

> The verifier doesn't see the solver's work. It re-solves independently and picks the stronger answer. No confirmation bias.

---

## Features

| | Feature | Description |
|---|---|---|
| 🧠 | **Multi-Pass Reasoning** | Split complex queries into Solve → Verify stages with independent sessions |
| 🔒 | **Deterministic Solver** | CSP engine for logic puzzles — provably correct, no LLM guessing |
| 🌐 | **Web Search** | Optional DuckDuckGo integration with multi-round deep search |
| 💾 | **3-Layer Memory** | Session → Working → Long-Term persistent memory across runs |
| 📡 | **Real-Time Streaming** | `AsyncStream<PipelineEvent>` — token-by-token UI updates |
| 🔍 | **Full Execution Trace** | Inspect every stage's input, output, confidence, and duration |
| 🌏 | **12 Languages** | Auto-detected, directive-injected language support |
| 📊 | **Built-in Benchmarks** | Compare pipeline accuracy across problem categories |
| 🔌 | **Pluggable Backends** | `ModelProvider` protocol — swap in any model |

---

## Quick Start

### Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/john-rocky/DeepThinkKit.git", branch: "main")
]
```

### 3 Lines to Think Deeper

```swift
import DeepThinkKit

let context = PipelineContext(modelProvider: FoundationModelProvider())
let pipeline = PipelineFactory.create(kind: .rethink)
let result = try await pipeline.execute(query: "Why do we dream?", context: context)

print(result.finalOutput.content) // Verified, multi-pass answer
```

### Stream Thinking in Real-Time

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
        print(content)  // Token-by-token output
    case .stageCompleted(let name, _, _, _):
        print("✓ \(name)")
    default: break
    }
}
```

### Add Web Search

<p align="center">
  <img src="https://github.com/user-attachments/assets/2432a573-cb7f-4de2-a038-1efec1ab8b5f" alt="Web Search Demo" width="280">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
</p>

```swift
let config = PipelineConfiguration(
    webSearchEnabled: true,
    maxSearchDepth: 3  // Deep search: multiple rounds with LLM evaluation
)
let pipeline = PipelineFactory.create(kind: .rethink, configuration: config)
```

---

## Pipelines

<table>
<tr><td width="25%"><b>Auto</b><br><sub>Default — routes automatically</sub></td><td>Classifies your query and picks the best pipeline. Just use <code>.auto</code> and forget about it.</td></tr>
<tr><td><b>Direct</b><br><sub>Single pass</sub></td><td><code>Query → Response</code><br>Fast baseline. Good for greetings, simple Q&A.</td></tr>
<tr><td><b>Rethink</b><br><sub>Solve + Verify</sub></td><td><code>Query → Solve → Verify (independent) → Answer</code><br>Each stage runs in a <b>fresh session</b>. The verifier re-solves independently and compares both answers.</td></tr>
<tr><td><b>Verified</b><br><sub>Deterministic CSP</sub></td><td><code>Query → Extract Constraints → CSP Solve → Explain</code><br>The solver is deterministic — <b>no LLM involved</b>. Provably correct when constraints are extracted properly.</td></tr>
</table>

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│               Your SwiftUI App                  │
│         Chat  ·  Benchmark  ·  Memory           │
├─────────────────────────────────────────────────┤
│                DeepThinkKit                     │
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
├─────────────────────────────────────────────────┤
│        Apple Foundation Models (on-device)       │
└─────────────────────────────────────────────────┘
```

---

## Memory

Three layers, each with a clear lifetime:

```swift
// Persist facts across sessions
let memory = LongTermMemory()
try await memory.save(MemoryEntry(
    kind: .fact,
    content: "User prefers concise answers",
    tags: ["preference"]
))

// Retrieve later
let hits = try await memory.search(MemorySearchQuery(text: "preference", limit: 3))
```

| Layer | Lifetime | Role |
|---|---|---|
| **Session** | Single execution | Conversation history |
| **Working** | Pipeline run | Intermediate stage outputs |
| **LongTerm** | Persistent (JSON) | Facts, decisions, constraints across runs |

---

## Tracing

Every run is fully observable. No black boxes.

```swift
let result = try await pipeline.execute(query: "...", context: context)

for record in result.trace {
    print("[\(record.stageName)] \(record.duration)s — confidence: \(record.confidence ?? 0)")
}
```

The included app has a **Show Trace** button on every message — inspect per-stage inputs, outputs, duration, and confidence inline.

---

## Run the Demo App

```bash
git clone https://github.com/john-rocky/DeepThinkKit.git
cd DeepThinkKit
open DeepThinkApp.xcodeproj
```

Select `DeepThinkApp_iOS` or `DeepThinkApp_macOS` and run.

The app includes:
- ChatGPT-style conversation UI with pipeline selection
- Real-time thinking process visualization
- Execution trace inspector
- Pipeline comparison mode
- Memory browser
- Benchmark runner

---

## Custom Model Provider

`ModelProvider` is a protocol — plug in any backend:

```swift
struct MyCloudProvider: ModelProvider {
    func generate(systemPrompt: String?, userPrompt: String) async throws -> String {
        // Your API call here
    }

    func generateStream(systemPrompt: String?, userPrompt: String) -> AsyncThrowingStream<String, Error> {
        // Your streaming API call here
    }
}
```

---

## Requirements

| | Requirement |
|---|---|
| Xcode | 26+ |
| iOS | 26.0+ |
| macOS | 26.0+ |
| Hardware | Apple Silicon (M1+ / A17 Pro+) |
| Setting | Apple Intelligence enabled |

---

## License

Apache License 2.0 — See [LICENSE](LICENSE) for details.

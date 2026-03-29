# DeepThinkKit — Pipeline Modes & Prompts Reference

All pipeline modes, classification logic, and exact prompts used in the DeepThinkKit framework.

---

## Pipeline Modes Overview

| Mode | Flow | Description |
|------|------|-------------|
| **Auto** | Query → Classify → (delegate) | Automatically selects the best pipeline |
| **Direct** | Query → Response | Single-pass, no reasoning stages |
| **Sequential** | Think → Answer (multi-turn) | Step-by-step reasoning before answering |
| **CritiqueLoop** | Answer → Review → Final (multi-turn) | Self-review and correction cycle |
| **BranchMerge** | Analyze → {Solve A, B, C} → Merge → Finalize | Parallel generation + best-parts integration |
| **SelfConsistency** | Analyze → {Solve 1, 2, 3} → Aggregate → Finalize | Parallel generation + majority consensus |
| **Verified** | Extract Constraints → CSP Solver → Explain | Deterministic solve for logic/math problems |

---

## Auto Mode — Query Classification

Auto mode uses a two-stage approach: fast heuristic rules first, then LLM classification as fallback.

### Stage 1: Heuristic Rules (Fast Path)

```
Source: PipelineClassifier.swift — heuristicClassify()
```

| Pattern | Keywords | Routes to |
|---------|----------|-----------|
| Short greetings (< 15 chars) | `hi`, `hello`, `hey`, `thanks`, `thank you`, `bye`, `konnichiwa`, `ohayou`, `arigatou`, `yoroshiku`, `otsukare` | **Direct** |
| Math / Logic / Puzzle | `solve`, `calculate`, `compute`, `equation`, `puzzle`, `riddle`, `logic`, `x + `, `x - `, `x * `, `x = `, `motomeyo`, `keisan`, `houteishiki`, `puzzle`, `nantoori`, etc. | **Verified** |
| Debate / Multi-perspective | `pros and cons`, `advantages and disadvantages`, `compare`, `vs `, ` or `, `meritto to demeritto`, `sanpi`, `hikaku`, `dochiraga`, `should we`, `is it better` | **BranchMerge** |

If no heuristic matches → proceed to LLM classification.

### Stage 2: LLM Classification (Fallback)

```
User Prompt:
  Pick ONE label for the following question. Reply with the label letter only.

  A: Simple greeting, single-fact lookup, translation, or definition.
  B: Needs careful verification. Factual explanation, technical topic, or anything where correctness matters.
  C: Multiple valid viewpoints. Comparison, trade-offs, or exploring different approaches.
  D: Has one correct answer that can be computed. Math, logic, or constraint-based problem.
  E: Step-by-step task. How-to, planning, coding, or creative writing.

  Question: {query (max 400 chars)}
```

### Label → Pipeline Mapping

| Label | Pipeline |
|-------|----------|
| A | Direct |
| B | CritiqueLoop |
| C | BranchMerge |
| D | Verified |
| E | Sequential |
| (parse failure) | CritiqueLoop (default) |

---

## 1. Rethink Pipeline (Primary)

```
Source: RethinkPipeline.swift
Flow:   [WebSearch] → Solve (independent session) → Verify (independent session)
Type:   Two independent sessions (no shared context)
```

### Stage 1 — Solve

```
System:
  You are a friendly, helpful assistant. For conversations, be natural and concise.
  Before solving any problem, first identify what approach, formula, or concept is needed.
  Solve using equations when possible. Write State: [values] after each reasoning step.
  If you are unsure, say so honestly instead of guessing.
  {Language Directive}

User:
  {query}{conversation context}{memory context}{web search context}
```

### Stage 2 — Verify

```
System:
  You are a reviewer who checks existing work.
  Read the draft answer and verify:
  Is the reasoning sound? Does each step follow from the previous?
  Are all calculations correct? Does the final answer match the calculations?
  If the draft is correct, clean up the formatting and output it.
  If you find a specific error, fix that error while keeping everything else unchanged.
  Do not rewrite the response from scratch. Do not remove steps.
  {Language Directive}

User:
  User's question: {query}

  Draft answer to check:
  {Solve output (max 800 chars)}

  Check this draft for errors. Verify the final answer directly addresses what the question asked.
  If correct, output it with clean formatting. If you find an error, fix only that error.
```

### Output Selection
- If Verify refused (safety filter) → use Solve output
- Otherwise → use Verify output (trust review-mode corrections)

---

## 2. Direct Pipeline

```
Source: DirectPipeline.swift
Flow:   [WebSearch] → Direct Response
Type:   Single inference (no session)
```

### System Prompt
```
Think carefully, then answer clearly and completely.
{Language Directive}
```

### User Prompt
```
{query}{memory context}{web search context}
```

---

## 3. Sequential Pipeline (Removed)

```
Source: SequentialPipeline.swift
Flow:   [WebSearch] → Think → Finalize
Type:   Multi-turn session (2 turns)
```

### Session Instructions
```
You are an assistant that thinks carefully before answering.
{Language Directive}
```

### Turn 1 — Think
```
User:
  {query}{memory context}{web search context}
```

### Turn 2 — Finalize
```
User:
  Based on your thinking above, write your final answer.
```

---

## 4. CritiqueLoop Pipeline (Removed)

```
Source: CritiqueLoopPipeline.swift
Flow:   [WebSearch] → Solve → Critique → Finalize
Type:   Multi-turn session (3 turns)
```

### Session Instructions
```
You are an assistant that answers carefully and reviews your own work.
{Language Directive}
```

### Turn 1 — Solve
```
User:
  Answer the following question.

  Question: {query}{memory context}{web search context}
```

### Turn 2 — Critique
```
User:
  Review your answer above.
  - Are there any factual errors?
  - Any logical gaps or oversights?
  - Could the explanation be improved?
  Point out specific issues if any. If the answer is correct, say "No issues found."
```

### Turn 3 — Finalize
```
User:
  Based on your review above, write your final answer. Fix any issues you identified, and keep the parts that were correct.
```

---

## 5. BranchMerge Pipeline (Removed)

```
Source: BranchMergePipeline.swift
Flow:   [WebSearch] → Analyze → {Solve-A, Solve-B, Solve-C} → Merge → Finalize
Type:   Independent stages (no session), parallel branches
```

### Stage 1 — Analyze

```
System: Decompose the question. List the core problem, assumptions, and hidden constraints. Do not answer.
        {Language Directive}
User:   {query (max 1000 chars) + web search context}
```

### Stage 2 — Solve (x3 in parallel)

Each branch (Solve-A, Solve-B, Solve-C) receives the same prompt:

```
System: Generate an answer following the analysis and plan below.
        {Language Directive}
User:   Question: {query (max 500 chars)}

        [Analysis]
        {Analyze stage output (max 800 chars)}

        [Plan]
        {Plan stage output if available (max 800 chars)}
```

### Stage 3 — Merge

```
System: Select the best parts from each answer and integrate into one.
        {Language Directive}
User:   Question: {query (max 300 chars)}

        [Answers]
        [Solve-A] {Solve-A output summary}

        [Solve-B] {Solve-B output summary}

        [Solve-C] {Solve-C output summary}
```

### Stage 4 — Finalize

No LLM call. Finds the best answer from previous outputs (priority: Revise > Solve > Merge > Aggregate), removes confidence scores and internal notes, outputs clean text.

---

## 6. SelfConsistency Pipeline (Removed)

```
Source: SelfConsistencyPipeline.swift
Flow:   [WebSearch] → Analyze → {Solve-1, Solve-2, Solve-3} → Aggregate → Finalize
Type:   Independent stages (no session), parallel branches
```

### Stage 1 — Analyze
Same as BranchMerge Analyze stage.

### Stage 2 — Solve (x3 in parallel)
Same as BranchMerge Solve stage, but branches are named Solve-1, Solve-2, Solve-3.

### Stage 3 — Aggregate

```
System: Compare the answers. Trust majority consensus and output the final answer.
        {Language Directive}
User:   Question: {query (max 300 chars)}

        [Answers]
        [1] {Solve-1 output summary}

        [2] {Solve-2 output summary}

        [3] {Solve-3 output summary}
```

### Stage 4 — Finalize
Same as BranchMerge Finalize stage.

---

## 7. Verified Pipeline

```
Source: VerifiedPipeline.swift
Flow:   [WebSearch] → Extract Constraints → Deterministic Solve → Explain
Type:   Independent stages, deterministic middle step
```

### Stage 1 — Extract Constraints (LLM with @Generable)

```
Instructions:
  Extract constraints from the problem. Use variable names, position domain, and constraint types: equal, notEqual, notAdjacent, lessThan, greaterThan, atBoundary.
  {Language Directive}

Input: {query (max 500 chars)}
Output: CSPProblem struct (structured generation via @Generable)
```

### Stage 2 — Deterministic Solve (No LLM)

No prompt. The CSP Solver enumerates all permutations and filters by constraints. Pure Swift code.

- If CSP parsing succeeds → outputs all valid solutions
- If CSP parsing fails → marks `solver_status: parse_failed`, Explain stage falls back to direct LLM answer

### Stage 3 — Explain

**Normal path** (solver succeeded):
```
System: Explain the verified solution clearly to answer the original problem.
        {Language Directive}
User:   Problem: {query (max 400 chars)}

        [Verified Solution]
        {solver output}
```

**Fallback path** (solver failed):
```
System: Answer the question directly.
        {Language Directive}
User:   {query (max 600 chars)}
```

---

## Shared Stage Prompts

These stages are used as building blocks across multiple pipelines.

### Plan Stage
```
Source: PlanStage.swift
System: Based on the analysis, design answer steps as bullet points. Do not write the answer itself.
        {Language Directive}
User:   Question: {query (max 400 chars)}

        [Analysis]
        {Analyze output summary}
```

### Critique Stage (standalone)
```
Source: CritiqueStage.swift
System: Point out errors or oversights in the answer. Provide counterexamples if any.
        {Language Directive}
User:   Question: {query (max 300 chars)}

        [Answer]
        {Solve/Revise output summary}
```

### Revise Stage
```
Source: ReviseStage.swift
System: Fix the issues raised in the critique and output the complete improved answer.
        {Language Directive}
User:   Question: {query (max 300 chars)}

        [Current Answer]
        {Solve/Revise output summary}

        [Critique]
        {Critique output summary}
```

---

## Web Search Stage

```
Source: WebSearchStage.swift
Enabled via: configuration.webSearchEnabled = true
```

### Step 1 — Keyword Extraction (LLM)
```
System: Extract 3-5 search keywords from the question for a web search.
        Output only the keywords on a single line. No explanation needed.
User:   {query (max 500 chars)}
```

### Step 2 — Web Search
Sends extracted keywords to DuckDuckGo, retrieves up to `maxSearchResults` (default: 5) results.

### Step 3 — Page Fetching
Fetches actual page content from top results (default: 2 pages) in parallel.

### Step 4 — Format Results
```
[Web Search Results]

[1] {title}
{snippet}
{page content excerpt}
URL: {url}

[2] ...
```

No extra LLM call for summarization. Raw results are injected into the answering stage's prompt.

---

## Memory Stages

### RetrieveMemory Stage
```
Source: RetrieveMemoryStage.swift
```
No LLM call. Searches long-term memory (JSON store) using keyword matching with configurable:
- `searchKinds`: fact, decision, constraint, summary, etc.
- `topK`: max entries to return
- `minPriority`: minimum priority threshold

### SummarizeMemory Stage
```
Source: SummarizeMemoryStage.swift
System: Summarize the memory concisely, keeping only information relevant to the current task. Use bullet points.
        {Language Directive}
User:   Task: {query (max 200 chars)}

        Memory:
        [{kind}] {content (max 100 chars per entry, up to 5 entries)}
```

### Memory Context Injection
When memory is available, it's appended to user prompts as:
```
[Reference Memory]
- [{kind}] {content (max 100 chars)}
- [{kind}] {content (max 100 chars)}
```
Limited to 2 entries per injection.

---

## Language Directives

All system prompts are suffixed with a language directive based on `AppLanguage`:

| Language | Directive |
|----------|-----------|
| English | `You must respond in English.` |
| Japanese | `日本語で回答してください。` |
| Chinese | `请用中文回答。` |
| Korean | `한국어로 답변해 주세요.` |
| Spanish | `Responde en español.` |
| French | `Réponds en français.` |
| German | `Antworte auf Deutsch.` |
| Portuguese | `Responda em português.` |
| Russian | `Отвечай на русском языке.` |
| Arabic | `أجب باللغة العربية.` |
| Italian | `Rispondi in italiano.` |
| Hindi | `हिंदी में उत्तर दें।` |

Language is auto-detected from user input via the NaturalLanguage framework.

---

## Configuration Parameters

```
Source: Pipeline.swift — PipelineConfiguration
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `maxStages` | 20 | Maximum stage count per pipeline run |
| `maxCritiqueReviseLoops` | 3 | Max critique-revise iterations |
| `maxRetries` | 2 | Retry count per stage on failure |
| `convergenceThreshold` | 0.1 | Confidence change threshold for convergence |
| `confidenceThreshold` | 0.7 | Minimum confidence to accept output |
| `branchCount` | 3 | Parallel branch count (BranchMerge / SelfConsistency) |
| `webSearchEnabled` | false | Enable web search stage |
| `maxSearchResults` | 5 | Max web search results |
| `webSearchContextBudget` | 2000 | Max characters for web search context injection |

### Context Size Limits (StageHelpers.swift)

| Limit | Value |
|-------|-------|
| Max context length | 1,200 chars |
| Max previous output length | 800 chars |
| Truncation boundaries | `\n`, `。`, `.` |

---

## Source File Index

| Category | File | Purpose |
|----------|------|---------|
| **Core** | `Core/Pipeline.swift` | PipelineKind enum, PipelineConfiguration, Pipeline protocol |
| | `Core/Stage.swift` | Stage protocol, retry logic |
| | `Core/PipelineContext.swift` | Shared context, AppLanguage enum |
| | `Core/StageTypes.swift` | StageKind, StageInput, StageOutput |
| **Pipelines** | `Pipeline/DirectPipeline.swift` | Direct (single-pass) |
| | `Pipeline/SequentialPipeline.swift` | Sequential (think → answer) |
| | `Pipeline/CritiqueLoopPipeline.swift` | CritiqueLoop (answer → review → final) |
| | `Pipeline/BranchMergePipeline.swift` | BranchMerge (parallel → merge) |
| | `Pipeline/SelfConsistencyPipeline.swift` | SelfConsistency (parallel → consensus) |
| | `Pipeline/VerifiedPipeline.swift` | Verified (CSP solver) |
| | `Pipeline/PipelineClassifier.swift` | Auto mode classification |
| | `Pipeline/PipelineFactory.swift` | Pipeline instantiation |
| **Stages** | `Stages/AnalyzeStage.swift` | Decompose question |
| | `Stages/PlanStage.swift` | Design answer steps |
| | `Stages/SolveStage.swift` | Generate answer |
| | `Stages/CritiqueStage.swift` | Point out errors |
| | `Stages/ReviseStage.swift` | Fix critique issues |
| | `Stages/MergeStage.swift` | Merge + Aggregate stages |
| | `Stages/FinalizeStage.swift` | Clean presentation output |
| | `Stages/ExtractConstraintsStage.swift` | CSP constraint extraction |
| | `Stages/DeterministicSolveStage.swift` | CSP solver (no LLM) |
| | `Stages/ExplainStage.swift` | Explain verified solution |
| | `Stages/WebSearchStage.swift` | Web search + keyword extraction |
| | `Stages/RetrieveMemoryStage.swift` | Memory retrieval |
| | `Stages/SummarizeMemoryStage.swift` | Memory summarization |
| | `Stages/StageHelpers.swift` | Shared helpers, truncation, parsing |

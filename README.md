# DeepThinkKit

**Apple Foundation Models で "deep thinking" する Swift ライブラリ**

Foundation Models (on-device LLM) に1回で答えさせるのではなく、**分析 → 計画 → 回答 → 批評 → 修正** と複数ステージで考えさせることで、回答の質を引き上げる実験フレームワークです。

ChatGPT 風の SwiftUI アプリ付き。iOS / macOS 対応。

```
Direct (単一推論):   質問 → 回答

DeepThink (多段推論): 質問 → 分析 → 計画 → 回答 → 批評 → 修正 → 最終回答
```

---

## Quick Start

### 1. Swift Package として使う

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

// CritiqueLoop: 分析 → 回答 → 批評 → 修正 → 整形
let pipeline = PipelineFactory.create(kind: .critiqueLoop)
let result = try await pipeline.execute(query: "量子コンピュータを小学生に説明して", context: context)

print(result.finalOutput.content)

// 各ステージの中間結果も見れる
for stage in result.stageOutputs {
    print("[\(stage.stageKind.rawValue)] \(stage.content.prefix(100))...")
}
```

### 2. アプリを動かす

```bash
git clone https://github.com/john-rocky/DeepThinkKit.git
cd DeepThinkKit
xcodegen generate   # Xcode プロジェクト生成 (要 xcodegen: brew install xcodegen)
open DeepThinkApp.xcodeproj
```

Xcode で Scheme `DeepThinkApp_macOS` or `DeepThinkApp_iOS` を選んで Run。

> **必要環境:** Xcode 26+, iOS 26+ / macOS 26+, Apple Silicon, Apple Intelligence 有効

---

## 5つのパイプライン

| パイプライン | 流れ | 特徴 |
|---|---|---|
| **Direct** | Query → Response | 単一推論。比較用ベースライン |
| **Sequential** | Analyze → Plan → Solve → Finalize | 分析・計画してから回答 |
| **CritiqueLoop** | Analyze → Solve → (Critique → Revise) x N → Finalize | 自己批評で繰り返し改善 |
| **BranchMerge** | Analyze → {Solve A, B, C} → Merge → Finalize | 並列で複数回答し統合 |
| **SelfConsistency** | Analyze → {Solve 1, 2, 3} → Aggregate → Finalize | 多数決で信頼性を高める |

### CritiqueLoop の動き

```
ユーザー: "AIの倫理的課題を整理して"

[Analyze] 核心的な問い、必要な知識領域、隠れた前提を分析 (回答はしない)
    ↓
[Solve]   分析に基づいて回答を生成
    ↓
[Critique] 事実の正確性・論理の一貫性・網羅性・明確さを検証し、問題点を指摘
    ↓
[Revise]  指摘された点だけを修正 (問題ない部分はそのまま維持)
    ↓
    ↑ (confidence が閾値未満なら繰り返し)
    ↓
[Finalize] 内部メモを除去して読みやすく整形 (内容は変えない)
```

---

## Direct vs DeepThink を比較する

```swift
let comparator = StrategyComparator()
let result = try await comparator.compare(
    query: "再生可能エネルギーの課題と解決策",
    pipelines: [
        PipelineFactory.create(kind: .direct),
        PipelineFactory.create(kind: .critiqueLoop),
    ],
    modelProvider: FoundationModelProvider()
)

// どちらが高い confidence を出したか
for (name, metrics) in result.results {
    print("\(name): confidence=\(metrics.averageConfidence), latency=\(metrics.totalLatency)s")
}
```

アプリの **Compare タブ** では GUI で比較できます。レイテンシのバーチャート、Thinking Overhead (何倍遅いか)、出力の横並び比較が表示されます。

---

## 3層メモリ

| レイヤー | 保持期間 | 用途 |
|---|---|---|
| **SessionMemory** | 実行中 | 直近の会話履歴 |
| **WorkingMemory** | パイプライン実行中 | 各ステージの中間結果 |
| **LongTermMemory** | 永続 (JSON ファイル) | fact, decision, constraint 等をセッションを跨いで保存・検索 |

```swift
// Long-term memory に保存
let memory = LongTermMemory()
try await memory.save(MemoryEntry(kind: .fact, content: "プロジェクトXの締切は3月末", tags: ["project-x"]))

// 次の推論で検索・再注入
let hits = try await memory.search(MemorySearchQuery(text: "プロジェクトX", limit: 3))
```

---

## Trace: どこで何が起きたか見える

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

アプリでは各メッセージの **Show Trace** ボタンで、ステージごとの入出力・所要時間・confidence をインラインで確認できます。

---

## アーキテクチャ

```
┌─────────────────────────────────────────────┐
│                  App Layer                   │
│   SwiftUI Chat / Compare / Memory Browser   │
├─────────────────────────────────────────────┤
│               DeepThinkKit                   │
│                                              │
│  Pipeline ──→ Stage ──→ ModelProvider        │
│  (Direct,      (Analyze,   (FoundationModel  │
│   Sequential,   Plan,       Provider)        │
│   CritiqueLoop, Solve,                       │
│   BranchMerge,  Critique,                    │
│   SelfConsis.)  Revise,                      │
│                 Finalize)                    │
│                                              │
│  Memory ◄──► Trace ◄──► Evaluation           │
│  (Session,     (Record,    (Metrics,          │
│   Working,      Collector)  Comparator)       │
│   LongTerm)                                  │
└─────────────────────────────────────────────┘
         │
         ▼
   Apple Foundation Models (on-device)
```

---

## Requirements

- Xcode 26+
- iOS 26.0+ / macOS 26.0+
- Apple Silicon (M1 以降 / A17 Pro 以降)
- Apple Intelligence を有効にすること (設定 → Apple Intelligence & Siri)
- XcodeGen (`brew install xcodegen`) - アプリのビルドに必要

---

## License

Apache License 2.0 - 詳細は [LICENSE](LICENSE) を参照。

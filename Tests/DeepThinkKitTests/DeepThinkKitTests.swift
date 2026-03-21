import Testing
@testable import DeepThinkKit

@Test func pipelineConfigurationDefaults() {
    let config = PipelineConfiguration.default
    #expect(config.maxStages == 20)
    #expect(config.maxCritiqueReviseLoops == 3)
    #expect(config.maxRetries == 2)
}

@Test func stageOutputCreation() {
    let output = StageOutput(
        stageKind: .analyze,
        content: "Test content",
        bulletPoints: ["Point 1", "Point 2"],
        confidence: 0.8
    )
    #expect(output.stageKind == .analyze)
    #expect(output.confidence == 0.8)
    #expect(output.bulletPoints.count == 2)
}

@Test func memoryEntryCreation() {
    let entry = MemoryEntry(
        kind: .fact,
        content: "Swift is a programming language",
        tags: ["swift", "language"]
    )
    #expect(entry.kind == .fact)
    #expect(entry.tags.count == 2)
}

@Test func convergenceChecker() {
    let policy = LoopPolicy(maxIterations: 3, convergenceThreshold: 0.1, confidenceTarget: 0.8)
    let checker = ConvergenceChecker(policy: policy)

    let decision1 = checker.shouldContinue(iteration: 1, previousConfidence: 0.3, currentConfidence: 0.5)
    if case .continue = decision1 {} else {
        Issue.record("Expected continue")
    }

    let decision2 = checker.shouldContinue(iteration: 1, previousConfidence: 0.5, currentConfidence: 0.9)
    if case .stop(let reason) = decision2 {
        #expect(reason == .confidenceReached)
    } else {
        Issue.record("Expected stop")
    }

    let decision3 = checker.shouldContinue(iteration: 3, previousConfidence: 0.5, currentConfidence: 0.6)
    if case .stop(let reason) = decision3 {
        #expect(reason == .maxIterationsReached)
    } else {
        Issue.record("Expected stop")
    }
}

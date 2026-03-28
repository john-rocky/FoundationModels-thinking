import Testing
@testable import DeepThinkKit

@Test func pipelineConfigurationDefaults() {
    let config = PipelineConfiguration.default
    #expect(config.maxStages == 20)
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

@Test func answerExtraction() {
    #expect(AnswerExtractor.extract(from: "The result is 42.\nAnswer: 42") == "42")
    #expect(AnswerExtractor.extract(from: "答え：10") == "10")
    #expect(AnswerExtractor.extract(from: "No explicit marker but 7 is the answer") == "7")
}

@Test func answerMatching() {
    #expect(AnswerMatcher.matches(actual: "42", expected: "42", acceptableAnswers: ["42"]))
    #expect(AnswerMatcher.matches(actual: "$80", expected: "80", acceptableAnswers: ["80", "$80"]))
    #expect(!AnswerMatcher.matches(actual: "9", expected: "7", acceptableAnswers: ["7"]))
}

@Test func pipelineKindCoverage() {
    let kinds = PipelineKind.allCases
    #expect(kinds.contains(.direct))
    #expect(kinds.contains(.rethink))
    #expect(kinds.contains(.verified))
    #expect(kinds.contains(.auto))
    #expect(kinds.count == 4)
}

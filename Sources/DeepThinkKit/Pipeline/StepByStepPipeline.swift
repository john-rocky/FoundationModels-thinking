import Foundation

// MARK: - StepByStep Pipeline
// 3 independent step-by-step solves → majority vote (deterministic)
//
// Each solve runs in a fresh session with explicit per-step state tracking.
// The final answer is chosen by majority vote, not LLM aggregation.

public struct StepByStepPipeline: Pipeline, Sendable {
    public let name = "StepByStep"
    public let description = "3x independent solve → majority vote"
    public let configuration: PipelineConfiguration

    public var stages: [any Stage] { [] }

    public init(configuration: PipelineConfiguration = .default) {
        self.configuration = configuration
    }

    public func execute(query: String, context: PipelineContext) async throws -> PipelineResult {
        let startTime = Date.now
        await context.traceCollector.setPipeline(name: name, executionId: context.executionId)
        await context.traceCollector.record(event: .pipelineStarted(name: name, query: query))
        await context.emit(.pipelineStarted(pipelineName: name, stageCount: 4))

        var allOutputs: [StageOutput] = []
        var stageIndex = 0
        var answers: [String] = []

        let solvePrompts = [
            // Variant A: explicit state tracking
            """
            Execute each step one at a time. After each step, write the current state.
            Never skip steps. Show all intermediate values.
            End with 'Answer: [value]'

            Problem: \(query)
            """,
            // Variant B: different phrasing to increase diversity
            """
            Solve carefully. For each step:
            1) State what operation you perform
            2) Show the calculation
            3) Write the result
            Do every step in order. End with 'Answer: [value]'

            Problem: \(query)
            """,
            // Variant C: even more explicit
            """
            Work through this problem one step at a time.
            IMPORTANT: After each step, write "After step N: [current values]"
            Do not skip any step. Do not compute ahead.
            End with 'Answer: [value]'

            Problem: \(query)
            """,
        ]

        let systems = [
            "You execute problems one step at a time, tracking all intermediate values precisely.",
            "You are a careful calculator. Show every intermediate result. Never skip steps.",
            "You solve step-by-step, writing the state after each operation. Be precise with numbers.",
        ]

        do {
            // --- 3 independent solves ---
            for i in 0..<3 {
                let stageName = "Solve-\(i + 1)"
                await context.emit(.stageStarted(stageName: stageName, stageKind: .solve, index: stageIndex))
                await context.traceCollector.record(event: .stageStarted(stage: stageName, kind: .solve, input: query))

                let system = localizedSystemPrompt(systems[i], language: context.language)

                let raw = try await streamingGenerate(
                    stageName: stageName,
                    systemPrompt: system,
                    userPrompt: solvePrompts[i],
                    context: context
                )

                let output = parseOutput(raw: raw, kind: .solve)
                allOutputs.append(output)
                await context.setOutput(output, for: stageName)
                await context.traceCollector.record(event: .stageCompleted(stage: stageName, output: output))
                await context.emit(.stageCompleted(stageName: stageName, stageKind: .solve, output: output, index: stageIndex))
                stageIndex += 1

                if let answer = AnswerExtractor.extract(from: raw) {
                    answers.append(answer)
                }
            }

            // --- Deterministic majority vote ---
            await context.emit(.stageStarted(stageName: "Finalize", stageKind: .finalize, index: stageIndex))

            let finalAnswer = majorityVote(answers)
            let voteDetail = answers.enumerated()
                .map { "Solve-\($0.offset + 1): \($0.element)" }
                .joined(separator: ", ")
            let finalContent = "Votes: \(voteDetail)\nMajority: \(finalAnswer)\nAnswer: \(finalAnswer)"

            let finalOutput = StageOutput(
                stageKind: .finalize,
                content: finalContent,
                confidence: finalAnswer == "no consensus" ? 0.2 : 0.8
            )
            allOutputs.append(finalOutput)
            await context.emit(.stageCompleted(stageName: "Finalize", stageKind: .finalize, output: finalOutput, index: stageIndex))

        } catch {
            await context.emit(.pipelineFailed(error: "\(error)"))
            await context.finishEventStream()
            throw error
        }

        let endTime = Date.now
        let trace = await context.traceCollector.allRecords()
        await context.traceCollector.record(
            event: .pipelineCompleted(name: name, duration: endTime.timeIntervalSince(startTime))
        )

        let result = PipelineResult(
            pipelineName: name,
            query: query,
            finalOutput: allOutputs.last ?? StageOutput(stageKind: .finalize, content: ""),
            stageOutputs: allOutputs,
            trace: trace,
            startTime: startTime,
            endTime: endTime
        )

        await context.emit(.pipelineCompleted(result: result))
        await context.finishEventStream()
        return result
    }

    /// Deterministic majority vote: return the most common answer.
    private func majorityVote(_ answers: [String]) -> String {
        guard !answers.isEmpty else { return "no consensus" }

        // Normalize for comparison
        let normalized = answers.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        var counts: [String: (count: Int, original: String)] = [:]
        for (i, norm) in normalized.enumerated() {
            if let existing = counts[norm] {
                counts[norm] = (existing.count + 1, existing.original)
            } else {
                counts[norm] = (1, answers[i])
            }
        }

        if let winner = counts.max(by: { $0.value.count < $1.value.count }), winner.value.count >= 2 {
            return winner.value.original
        }

        // No majority — return first answer as fallback
        return answers[0]
    }
}

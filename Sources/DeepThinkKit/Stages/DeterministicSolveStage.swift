import Foundation

// MARK: - Deterministic Solve Stage (No LLM)

@available(iOS 26.0, macOS 26.0, *)
public struct DeterministicSolveStage: Stage {
    public let kind: StageKind = .solve
    public let name = "Solve"
    public let purpose = "Enumerate all candidates and filter by constraints deterministically"

    public init() {}

    public func execute(input: StageInput, context: PipelineContext) async throws -> StageOutput {
        await context.traceCollector.record(
            event: .stageStarted(stage: name, kind: kind, input: input.query)
        )

        // Try equation solving first (pattern-matched from extracted values)
        if let extractOutput = input.previousOutputs["Extract"],
           extractOutput.metadata["eq_valid"] == "true",
           let jsonStr = extractOutput.metadata["eq_json"],
           let data = jsonStr.data(using: .utf8),
           let extraction = try? JSONDecoder().decode(WordProblemExtraction.self, from: data) {
            return await solveEquation(extraction, context: context)
        }

        // Fall back to CSP solving
        guard let extractOutput = input.previousOutputs["Extract"],
              extractOutput.metadata["csp_valid"] == "true",
              let jsonStr = extractOutput.metadata["csp_json"],
              let data = jsonStr.data(using: .utf8),
              let problem = try? JSONDecoder().decode(CSPProblem.self, from: data) else {
            let output = StageOutput(
                stageKind: .solve,
                content: "Failed to parse constraints. Falling back to LLM reasoning.",
                confidence: 0.0,
                metadata: ["solver_status": "parse_failed"]
            )
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        let solver = CSPSolver()
        let solutions = solver.solve(problem)

        let content: String
        var metadata: [String: String] = ["solver_status": "success"]

        if solutions.isEmpty {
            content = "No valid solutions found. The constraints may be contradictory."
            metadata["solution_count"] = "0"
        } else {
            let formatted = solutions.enumerated().map { i, sol in
                "Solution \(i + 1): \(sol.asPositionString())"
            }.joined(separator: "\n")
            content = "Found \(solutions.count) solution(s):\n\(formatted)"
            metadata["solution_count"] = "\(solutions.count)"

            if let json = try? JSONEncoder().encode(solutions.map { $0.assignment }) {
                metadata["solutions_json"] = String(data: json, encoding: .utf8) ?? ""
            }
        }

        await context.emit(.stageStreamingContent(stageName: name, content: content))

        let output = StageOutput(
            stageKind: .solve,
            content: content,
            bulletPoints: solutions.map { $0.asPositionString() },
            confidence: 1.0,
            metadata: metadata
        )

        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        return output
    }

    // MARK: - Rate/Chase Problem Solver

    private func solveEquation(_ extraction: WordProblemExtraction, context: PipelineContext) async -> StageOutput {
        let solver = EquationSolver()
        guard let solution = solver.solve(extraction) else {
            let output = StageOutput(
                stageKind: .solve,
                content: "Pattern not solvable deterministically. Falling back to LLM.",
                confidence: 0.0,
                metadata: ["solver_status": "parse_failed"]
            )
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        let content = """
            Equation: \(solution.equation)
            \(solution.steps)
            Answer: \(solution.answer) \(solution.unit)
            """

        await context.emit(.stageStreamingContent(stageName: name, content: content))

        let output = StageOutput(
            stageKind: .solve,
            content: content,
            confidence: 1.0,
            metadata: ["solver_status": "success"]
        )
        await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
        return output
    }
}

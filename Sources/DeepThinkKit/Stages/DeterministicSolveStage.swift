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

        // Try rate/equation solving first
        if let extractOutput = input.previousOutputs["Extract"],
           extractOutput.metadata["rate_valid"] == "true",
           let jsonStr = extractOutput.metadata["rate_json"],
           let data = jsonStr.data(using: .utf8),
           let problem = try? JSONDecoder().decode(RateProblem.self, from: data) {
            return await solveRate(problem, context: context)
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

    private func solveRate(_ problem: RateProblem, context: PipelineContext) async -> StageOutput {
        let solver = EquationSolver()
        guard let solution = solver.solve(problem) else {
            let output = StageOutput(
                stageKind: .solve,
                content: "Cannot solve: faster speed must be greater than slower speed.",
                confidence: 0.0,
                metadata: ["solver_status": "parse_failed"]
            )
            await context.traceCollector.record(event: .stageCompleted(stage: name, output: output))
            return output
        }

        let content = """
            Equation: \(solution.equation)
            \(solution.steps)
            Answer: \(fmtAnswer(solution.totalTime)) hours after the first person left.
            (The second person catches up \(fmtAnswer(solution.catchUpTime)) hours after starting.)
            Meeting distance: \(fmtAnswer(solution.meetingDistance)) km from start.
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

    private func fmtAnswer(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.2g", value)
    }
}

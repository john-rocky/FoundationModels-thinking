import Foundation

// MARK: - Equation Solver (Deterministic, Pattern-Matching)
// Detects solvable patterns from extracted tagged values and solves algebraically.
// Returns nil if the pattern is not recognized — caller falls through to LLM.

public struct EquationSolver: Sendable {

    public struct Solution: Sendable {
        public let answer: Double
        public let unit: String
        public let equation: String
        public let steps: String
    }

    public init() {}

    /// Try to solve from extracted values. Returns nil if pattern is unrecognized.
    public func solve(_ extraction: WordProblemExtraction) -> Solution? {
        let values = extraction.values

        let speeds = values.filter { $0.role == "speed" }
        let delays = values.filter { $0.role == "delay" || $0.role == "time" }

        // Pattern: 2 speeds + 1 delay → chase/pursuit problem
        if speeds.count == 2, let delay = delays.first {
            return solveChase(speeds: speeds, delay: delay)
        }

        return nil
    }

    // MARK: - Chase / Pursuit

    /// Two entities, one starts later at higher speed. When does the faster one catch up?
    /// Model: slow * t = fast * (t - delay)  →  t = fast * delay / (fast - slow)
    private func solveChase(speeds: [TaggedValue], delay: TaggedValue) -> Solution? {
        let sorted = speeds.sorted { $0.value < $1.value }
        let slow = sorted[0].value
        let fast = sorted[1].value

        let d = delay.value
        let diff = fast - slow
        guard diff > 0, d > 0 else { return nil }

        let totalTime = fast * d / diff
        let catchUpTime = totalTime - d
        let meetingDistance = slow * totalTime

        let equation = "\(fmt(slow))t = \(fmt(fast))(t - \(fmt(d)))"
        let steps = """
            \(fmt(slow))t = \(fmt(fast))t - \(fmt(fast * d))
            \(fmt(slow - fast))t = -\(fmt(fast * d))
            t = \(fmt(fast * d)) / \(fmt(diff)) = \(fmt(totalTime))

            Total time from first departure: \(fmt(totalTime)) hours
            Second person's travel time: \(fmt(catchUpTime)) hours
            Meeting distance: \(fmt(meetingDistance)) km
            """

        return Solution(
            answer: totalTime,
            unit: "hours",
            equation: equation,
            steps: steps
        )
    }

    private func fmt(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.2g", value)
    }
}

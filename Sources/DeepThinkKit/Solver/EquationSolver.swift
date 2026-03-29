import Foundation

// MARK: - Equation Solver (Deterministic)
// Solves chase/pursuit problems algebraically without LLM.
//
// Model:
//   Slow person: distance = speedSlow * t
//   Fast person: distance = speedFast * (t - delay)
//   Meet when: speedSlow * t = speedFast * (t - delay)
//   Solution:  t = speedFast * delay / (speedFast - speedSlow)

public struct EquationSolver: Sendable {

    public struct Solution: Sendable {
        public let totalTime: Double
        public let catchUpTime: Double
        public let meetingDistance: Double
        public let equation: String
        public let steps: String
    }

    public init() {}

    public func solve(_ problem: RateProblem) -> Solution? {
        let slow = problem.speedSlow
        let fast = problem.speedFast
        let delay = problem.delay

        let diff = fast - slow
        guard diff > 0, delay > 0 else { return nil }

        let totalTime = fast * delay / diff
        let catchUpTime = totalTime - delay
        let meetingDistance = slow * totalTime

        let equation = "\(fmt(slow))t = \(fmt(fast))(t - \(fmt(delay)))"
        let steps = """
            \(fmt(slow))t = \(fmt(fast))t - \(fmt(fast * delay))
            \(fmt(slow))t - \(fmt(fast))t = -\(fmt(fast * delay))
            \(fmt(-diff))t = -\(fmt(fast * delay))
            t = \(fmt(fast * delay)) / \(fmt(diff)) = \(fmt(totalTime))
            """

        return Solution(
            totalTime: totalTime,
            catchUpTime: catchUpTime,
            meetingDistance: meetingDistance,
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

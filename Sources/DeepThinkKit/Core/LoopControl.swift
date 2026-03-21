import Foundation

// MARK: - Loop Policy

public struct LoopPolicy: Sendable {
    public let maxIterations: Int
    public let convergenceThreshold: Double
    public let confidenceTarget: Double

    public init(
        maxIterations: Int = 3,
        convergenceThreshold: Double = 0.1,
        confidenceTarget: Double = 0.8
    ) {
        self.maxIterations = maxIterations
        self.convergenceThreshold = convergenceThreshold
        self.confidenceTarget = confidenceTarget
    }
}

// MARK: - Convergence Checker

public struct ConvergenceChecker: Sendable {
    private let policy: LoopPolicy

    public init(policy: LoopPolicy) {
        self.policy = policy
    }

    public func shouldContinue(
        iteration: Int,
        previousConfidence: Double,
        currentConfidence: Double
    ) -> LoopDecision {
        if iteration >= policy.maxIterations {
            return .stop(reason: .maxIterationsReached)
        }
        if currentConfidence >= policy.confidenceTarget {
            return .stop(reason: .confidenceReached)
        }
        let improvement = currentConfidence - previousConfidence
        if improvement < policy.convergenceThreshold && iteration > 1 {
            return .stop(reason: .convergenceReached)
        }
        if improvement < 0 {
            return .stop(reason: .degradation)
        }
        return .continue
    }
}

// MARK: - Loop Decision

public enum LoopDecision: Sendable {
    case `continue`
    case stop(reason: StopReason)

    public enum StopReason: String, Sendable, Codable {
        case maxIterationsReached
        case confidenceReached
        case convergenceReached
        case degradation
    }
}

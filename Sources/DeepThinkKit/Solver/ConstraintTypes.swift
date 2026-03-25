import Foundation
import FoundationModels

// MARK: - Constraint Satisfaction Problem Types (@Generable for structured LLM output)

@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct CSPProblem: Codable, Sendable {
    @Guide(description: "Variable names, e.g. A, B, C, D, E")
    public var variables: [String]
    @Guide(description: "Domain: position numbers as strings, e.g. 1, 2, 3, 4, 5")
    public var domain: [String]
    @Guide(description: "Constraints extracted from the problem")
    public var constraints: [CSPConstraint]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct CSPConstraint: Codable, Sendable {
    @Guide(description: "Type: equal, notEqual, notAdjacent, lessThan, greaterThan, atBoundary")
    public var type: String
    @Guide(description: "Arguments: variable names or position values")
    public var args: [String]
}

// MARK: - Internal Constraint Type (for solver)

public enum ConstraintType: String, Codable, Sendable {
    case equal
    case notEqual
    case notAdjacent
    case lessThan
    case greaterThan
    case atBoundary
}

// MARK: - Solution

public struct CSPSolution: Sendable {
    public let assignment: [String: String]

    public init(assignment: [String: String]) {
        self.assignment = assignment
    }

    public func ordered() -> [(variable: String, value: String)] {
        assignment.sorted { (Int($0.value) ?? 0) < (Int($1.value) ?? 0) }
            .map { (variable: $0.key, value: $0.value) }
    }

    public func asPositionString() -> String {
        ordered().map(\.variable).joined(separator: ", ")
    }
}

import Foundation

// MARK: - Constraint Satisfaction Problem Types

public struct CSPProblem: Codable, Sendable {
    public let variables: [String]
    public let domain: [String]
    public let constraints: [CSPConstraint]

    public init(variables: [String], domain: [String], constraints: [CSPConstraint]) {
        self.variables = variables
        self.domain = domain
        self.constraints = constraints
    }
}

public struct CSPConstraint: Codable, Sendable {
    public let type: ConstraintType
    public let args: [String]

    public init(type: ConstraintType, args: [String]) {
        self.type = type
        self.args = args
    }
}

public enum ConstraintType: String, Codable, Sendable {
    case equal          // args: [variable, value] — variable must equal value
    case notEqual       // args: [variable, value] — variable must not equal value
    case notAdjacent    // args: [varA, varB] — |pos(A) - pos(B)| != 1
    case lessThan       // args: [varA, varB] — pos(A) < pos(B)
    case greaterThan    // args: [varA, varB] — pos(A) > pos(B)
    case atBoundary     // args: [variable] — pos = 1 or pos = max
}

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

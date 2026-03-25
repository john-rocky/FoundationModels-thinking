import Foundation

// MARK: - Deterministic CSP Solver

public struct CSPSolver: Sendable {
    public static let maxPermutations = 40_320 // 8!

    public init() {}

    public func solve(_ problem: CSPProblem) -> [CSPSolution] {
        let vars = problem.variables
        let domain = problem.domain

        guard vars.count <= domain.count else { return [] }
        guard factorial(domain.count) <= Self.maxPermutations else { return [] }

        var solutions: [CSPSolution] = []

        for perm in permutations(of: domain, count: vars.count) {
            var assignment: [String: String] = [:]
            for (i, v) in vars.enumerated() {
                assignment[v] = perm[i]
            }
            if satisfiesAll(assignment: assignment, constraints: problem.constraints, domainSize: domain.count) {
                solutions.append(CSPSolution(assignment: assignment))
            }
        }

        return solutions
    }

    // MARK: - Constraint Checking

    private func satisfiesAll(
        assignment: [String: String],
        constraints: [CSPConstraint],
        domainSize: Int
    ) -> Bool {
        for c in constraints {
            if !satisfies(assignment: assignment, constraint: c, domainSize: domainSize) {
                return false
            }
        }
        return true
    }

    private func satisfies(
        assignment: [String: String],
        constraint: CSPConstraint,
        domainSize: Int
    ) -> Bool {
        switch constraint.type {
        case .equal:
            guard constraint.args.count >= 2,
                  let val = assignment[constraint.args[0]] else { return true }
            return val == constraint.args[1]

        case .notEqual:
            guard constraint.args.count >= 2,
                  let val = assignment[constraint.args[0]] else { return true }
            return val != constraint.args[1]

        case .notAdjacent:
            guard constraint.args.count >= 2,
                  let a = assignment[constraint.args[0]].flatMap({ Int($0) }),
                  let b = assignment[constraint.args[1]].flatMap({ Int($0) }) else { return true }
            return abs(a - b) != 1

        case .lessThan:
            guard constraint.args.count >= 2,
                  let a = assignment[constraint.args[0]].flatMap({ Int($0) }),
                  let b = assignment[constraint.args[1]].flatMap({ Int($0) }) else { return true }
            return a < b

        case .greaterThan:
            guard constraint.args.count >= 2,
                  let a = assignment[constraint.args[0]].flatMap({ Int($0) }),
                  let b = assignment[constraint.args[1]].flatMap({ Int($0) }) else { return true }
            return a > b

        case .atBoundary:
            guard constraint.args.count >= 1,
                  let val = assignment[constraint.args[0]].flatMap({ Int($0) }) else { return true }
            return val == 1 || val == domainSize
        }
    }

    // MARK: - Permutation Generator

    private func permutations(of array: [String], count: Int) -> [[String]] {
        var result: [[String]] = []
        var used = Array(repeating: false, count: array.count)
        var current: [String] = []

        func backtrack() {
            if current.count == count {
                result.append(current)
                return
            }
            for i in 0..<array.count {
                guard !used[i] else { continue }
                used[i] = true
                current.append(array[i])
                backtrack()
                current.removeLast()
                used[i] = false
            }
        }

        backtrack()
        return result
    }

    private func factorial(_ n: Int) -> Int {
        (1...max(1, n)).reduce(1, *)
    }
}

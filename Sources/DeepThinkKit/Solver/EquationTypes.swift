import Foundation
import FoundationModels

// MARK: - Word Problem Extraction (@Generable)
// The model extracts tagged numerical values from the problem text.
// The solver pattern-matches to determine if it can solve deterministically.

@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct WordProblemExtraction: Codable, Sendable {
    @Guide(description: "All numerical values from the problem with their roles")
    public var values: [TaggedValue]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct TaggedValue: Codable, Sendable {
    @Guide(description: "Role: speed, time, delay, distance, count, price, rate, age, or weight")
    public var role: String
    @Guide(description: "The numerical value")
    public var value: Double
}

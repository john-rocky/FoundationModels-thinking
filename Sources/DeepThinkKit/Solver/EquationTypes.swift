import Foundation
import FoundationModels

// MARK: - Rate/Chase Problem Types (@Generable for structured LLM extraction)
// The model only needs to extract numbers from the problem text.
// The equation setup and solving is done programmatically.

@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct RateProblem: Codable, Sendable {
    @Guide(description: "Speed of the slower person/object, e.g. 4")
    public var speedSlow: Double
    @Guide(description: "Speed of the faster person/object, e.g. 6")
    public var speedFast: Double
    @Guide(description: "Time delay before the faster one starts, e.g. 1")
    public var delay: Double
}

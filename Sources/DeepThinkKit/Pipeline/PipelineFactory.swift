import Foundation

// MARK: - Pipeline Factory

public enum PipelineFactory {
    public static func create(
        kind: PipelineKind,
        configuration: PipelineConfiguration = .default
    ) -> any Pipeline {
        switch kind {
        case .auto:
            RethinkPipeline(configuration: configuration)
        case .direct:
            DirectPipeline(configuration: configuration)
        case .rethink:
            RethinkPipeline(configuration: configuration)
        case .verified:
            VerifiedPipeline(configuration: configuration)
        }
    }
}

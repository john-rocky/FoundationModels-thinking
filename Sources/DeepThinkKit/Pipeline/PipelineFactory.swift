import Foundation

// MARK: - Pipeline Factory

public enum PipelineFactory {
    public static func create(
        kind: PipelineKind,
        configuration: PipelineConfiguration = .default
    ) -> any Pipeline {
        switch kind {
        case .auto:
            SequentialPipeline(configuration: configuration)
        case .direct:
            DirectPipeline(configuration: configuration)
        case .sequential:
            SequentialPipeline(configuration: configuration)
        case .critiqueLoop:
            CritiqueLoopPipeline(configuration: configuration)
        case .branchMerge:
            BranchMergePipeline(configuration: configuration)
        case .selfConsistency:
            SelfConsistencyPipeline(configuration: configuration)
        case .verified:
            VerifiedPipeline(configuration: configuration)
        }
    }
}

import SwiftUI

// MARK: - Cross-Platform Colors

enum AppColors {
    static var secondaryBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    static var tertiaryBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.tertiarySystemBackground)
        #endif
    }
}

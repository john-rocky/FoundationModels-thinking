// DeepThinkApp - ChatGPT風 Multi-Pass Reasoning アプリ
//
// セットアップ手順:
// 1. Xcode で新規プロジェクト作成 (iOS/macOS App, SwiftUI)
// 2. プロジェクト設定 > Package Dependencies > Add Local で deepthinkkit/ を追加
// 3. App/DeepThinkApp/ 内のファイルをプロジェクトに追加
// 4. Deployment Target を iOS 26.0 / macOS 26.0 に設定

import SwiftUI
import DeepThinkKit

@main
struct DeepThinkApp: App {
    @State private var chatViewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(chatViewModel)
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 700)
        #endif
    }
}

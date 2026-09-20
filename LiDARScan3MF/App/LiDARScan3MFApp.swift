import SwiftUI

@main
struct LiDARScan3MFApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            switch app.screen {
            case .home: HomeView()
            case .scan: ScanView()
            case .edit: EditView()
            case .export: ExportView()
            case .detail: DetailSettingsView()
            case .settings: SettingsView()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: app.screen)
        .toast(message: $app.toast)
    }
}

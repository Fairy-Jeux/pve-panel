import SwiftUI

@main
public struct PVECenterApp: App {
    @State private var viewModel = AppViewModel()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}

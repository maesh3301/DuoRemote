import SwiftUI

/// Hosts list ↔ session screen, cross-faded.
public struct RemoteRootView: View {
    @State var coordinator: SessionCoordinator
    @Environment(\.scenePhase) private var scenePhase

    public init(coordinator: SessionCoordinator) {
        _coordinator = State(initialValue: coordinator)
    }

    public var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-layoutLab") {
            LayoutLab()
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        ZStack {
            if let session = coordinator.active {
                SessionScreen(session: session, coordinator: coordinator)
                    .transition(.opacity)
            } else {
                HostsListView(coordinator: coordinator)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.active == nil)
        .sheet(item: $coordinator.credentialPrompt) { host in
            CredentialSheet(host: host, coordinator: coordinator)
        }
        .onChange(of: scenePhase) { _, phase in
            coordinator.scenePhaseChanged(phase)
            if phase == .active { SkyTheme.shared.refresh() }
        }
        .onAppear { SkyTheme.shared.start() }
    }
}

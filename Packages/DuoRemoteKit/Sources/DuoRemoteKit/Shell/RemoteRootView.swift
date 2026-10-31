import SwiftUI

/// Hosts list ↔ session screen, cross-faded.
public struct RemoteRootView: View {
    @State var coordinator: SessionCoordinator
    /// Set when Remote runs inside another app, whose navigation it then sits in.
    let exit: RemoteExit?
    @Environment(\.scenePhase) private var scenePhase

    public init(coordinator: SessionCoordinator, exit: RemoteExit? = nil) {
        _coordinator = State(initialValue: coordinator)
        self.exit = exit
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
            // A host app reports this itself: it has to arrive while Remote is off screen too.
            if exit == nil { coordinator.scenePhaseChanged(phase) }
        }
        .onAppear { SkyTheme.shared.start() }
        // In a session the screen's edges belong to the Mac, so the host's bar and back swipe go.
        .toolbarVisibility(coordinator.active == nil ? .automatic : .hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(coordinator.active != nil)
        .environment(\.remoteExit, exit)
    }
}

import SwiftUI

/// Hosts list ↔ session screen, cross-faded: all of an app that is only DuoRemote.
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
        }
        .onAppear { SkyTheme.shared.start() }
    }
}

/// The saved Macs, for a host app's navigation.
public struct RemoteHostsView: View {
    @State var coordinator: SessionCoordinator

    public init(coordinator: SessionCoordinator) {
        _coordinator = State(initialValue: coordinator)
    }

    public var body: some View {
        HostsListView(coordinator: coordinator, ownsNavigation: false)
            .sheet(item: $coordinator.credentialPrompt) { host in
                CredentialSheet(host: host, coordinator: coordinator)
            }
            .onAppear { SkyTheme.shared.start() }
    }
}

/// The open session, for a host app to show at the root of its window, above its navigation. That
/// gives it the same place in the view hierarchy as in an app of its own, which hiding the bars,
/// deferring edge gestures and keyboard avoidance all rely on.
public struct RemoteSessionView: View {
    let coordinator: SessionCoordinator
    let exit: RemoteExit

    public init(coordinator: SessionCoordinator, exit: RemoteExit) {
        self.coordinator = coordinator
        self.exit = exit
    }

    public var body: some View {
        if let session = coordinator.active {
            SessionScreen(session: session, coordinator: coordinator)
                .environment(\.remoteExit, exit)
        }
    }
}

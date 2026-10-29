import SwiftUI
import UIKit

@main
struct DuoRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator = SessionCoordinator(store: HostStore())

    init() {
        Diagnostics.shared.start()
        PrivacyShield.shared.start()
        EmbeddedTailscale.shared.startIfEnabled()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-layoutLab") {
                    LayoutLab()
                } else {
                    RootView(coordinator: coordinator)
                }
                #else
                RootView(coordinator: coordinator)
                #endif
            }
            .task {
                await coordinator.store.tidyKeychain()
                applyLaunchArguments()
                coordinator.warmUpBuiltInTailscale()
            }
        }
    }

    private func applyLaunchArguments() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoSession") { coordinator.openDemo() }
        if let i = args.firstIndex(of: "-vncSmoke"), i + 1 < args.count {
            VNCSmokeTest.run(host: args[i + 1])
        }
        // `-inputTrace`: log touch intents and mouse buttons as `[trace]` lines, without connecting.
        if args.contains("-inputTrace") {
            ConnectTrace.isEnabled = true
            ConnectTrace.begin("input trace")
        }
        if let i = args.firstIndex(of: "-vncTrace"), i + 1 < args.count {
            let wanted = args[i + 1].lowercased()
            if let j = args.firstIndex(of: "-vncTraceRoute"), j + 1 < args.count {
                SessionCoordinator.traceRoute = HostRoute(rawValue: args[j + 1])
            }
            ConnectTrace.isEnabled = true
            EmbeddedTailscale.warmUpDisabled = args.contains("-noWarmUp")
            ConnectTrace.begin("launch")
            if let host = coordinator.store.hosts.first(where: { $0.hostname.lowercased() == wanted || $0.name.lowercased() == wanted }) {
                // `-vncTraceDelay <s>`: connect a few seconds after launch, like a person would.
                let delay = args.firstIndex(of: "-vncTraceDelay").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 0
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    coordinator.connect(host)
                }
                // `-vncTraceRepeat`: disconnect after a while and connect again, to time a warm connect.
                if args.contains("-vncTraceRepeat") {
                    Task {
                        try? await Task.sleep(for: .seconds(30))
                        coordinator.disconnect()
                        try? await Task.sleep(for: .seconds(3))
                        coordinator.connect(host)
                    }
                }
            } else {
                ConnectTrace.begin("no saved Mac called \(wanted)")
            }
        }
        if let i = args.firstIndex(of: "-tailscaleSmoke"), i + 1 < args.count {
            VNCSmokeTest.runEmbedded(host: args[i + 1])
        }
        #endif
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Only the system keyboard: a third-party one could see what's typed into the Mac,
    /// passwords included.
    func application(_ application: UIApplication,
                     shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}

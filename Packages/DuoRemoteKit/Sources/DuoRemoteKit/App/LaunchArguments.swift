#if DEBUG
import Foundation

extension SessionCoordinator {
    func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoSession") { openDemo() }
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
            if let host = store.hosts.first(where: { $0.hostname.lowercased() == wanted || $0.name.lowercased() == wanted }) {
                // `-vncTraceDelay <s>`: connect a few seconds after launch, like a person would.
                let delay = args.firstIndex(of: "-vncTraceDelay").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 0
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    connect(host)
                }
                // `-vncTraceRepeat`: disconnect after a while and connect again, to time a warm connect.
                if args.contains("-vncTraceRepeat") {
                    Task {
                        try? await Task.sleep(for: .seconds(30))
                        disconnect()
                        try? await Task.sleep(for: .seconds(3))
                        connect(host)
                    }
                }
            } else {
                ConnectTrace.begin("no saved Mac called \(wanted)")
            }
        }
        if let i = args.firstIndex(of: "-tailscaleSmoke"), i + 1 < args.count {
            VNCSmokeTest.runEmbedded(host: args[i + 1])
        }
    }
}
#endif

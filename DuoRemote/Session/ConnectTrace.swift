import Foundation

/// `-vncTrace <host>`: timestamps every step of a connect, from the tap to the first full frame,
/// as `[trace] +ms` lines on stdout. A no-op unless that launch argument is given (and in release).
nonisolated enum ConnectTrace {
    #if DEBUG
    private static let lock = NSLock()
    nonisolated(unsafe) private static var start: ContinuousClock.Instant?
    nonisolated(unsafe) private static var last: ContinuousClock.Instant?
    nonisolated(unsafe) private static var rects = 0
    nonisolated(unsafe) private static var seen: Set<String> = []
    nonisolated(unsafe) static var isEnabled = false
    #endif

    /// Starts the clock (each connect attempt restarts it).
    static func begin(_ label: String) {
        #if DEBUG
        guard isEnabled else { return }
        lock.withLock {
            start = .now
            last = start
            rects = 0
            seen = []
        }
        mark(label)
        #endif
    }

    static func mark(_ label: @autoclosure () -> String) {
        #if DEBUG
        guard isEnabled else { return }
        let now = ContinuousClock.now
        let (total, step) = lock.withLock { () -> (Duration, Duration) in
            defer { last = now }
            return (now - (start ?? now), now - (last ?? now))
        }
        print(String(format: "[trace] %+8.1f ms  (%+7.1f)  %@", ms(total), ms(step), label()))
        fflush(stdout)
        #endif
    }

    /// Marks only the first occurrence of `label` per attempt (e.g. the first frame drawn).
    static func once(_ label: String) {
        #if DEBUG
        guard isEnabled, lock.withLock({ seen.insert(label).inserted }) else { return }
        mark(label)
        #endif
    }

    /// RoyalVNCKit's debug log. Per-rectangle lines are counted, not printed.
    static func library(_ message: String) {
        #if DEBUG
        guard isEnabled else { return }
        if message.contains("rectangle") {
            lock.withLock { rects += 1 }
            return
        }
        if message.hasPrefix("Received Framebuffer Update") {
            let n = lock.withLock { () -> Int in defer { rects = 0 }; return rects }
            mark("lib: Received Framebuffer Update (\(n) rect log lines)")
            return
        }
        mark("lib: \(message.prefix(160))")
        #endif
    }

    #if DEBUG
    private static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
    #endif
}

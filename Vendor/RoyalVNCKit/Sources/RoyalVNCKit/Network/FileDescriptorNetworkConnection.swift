// LOCAL PATCH: a connection over a socket the app opens itself (an in-app Tailscale tunnel hands
// back a connected file descriptor). NWConnection can't adopt an existing descriptor.

#if canImport(Darwin)
import Darwin
import Dispatch
import Foundation

/// Opens a connected stream socket and returns its descriptor. May block; called off the main thread.
public typealias VNCSocketProvider = @Sendable () throws -> Int32

final class FileDescriptorNetworkConnection: NetworkConnection, @unchecked Sendable {
    private let settings: NetworkConnectionSettings
    private let provider: VNCSocketProvider

    private let lock = NSLock()
    private var fd: Int32 = -1
    private var cancelled = false
    private var handler: NetworkConnectionStatusUpdateHandler?
    private var handlerQueue: DispatchQueue?
    private var _status: NetworkConnectionStatus = .setup

    // Reads and writes run on their own queues so a blocking read never holds up a write.
    private let dialQueue = DispatchQueue(label: "duoremote.fdconnection.dial")
    private let readQueue = DispatchQueue(label: "duoremote.fdconnection.read")
    private let writeQueue = DispatchQueue(label: "duoremote.fdconnection.write")

    init(settings: NetworkConnectionSettings, provider: @escaping VNCSocketProvider) {
        self.settings = settings
        self.provider = provider
    }

    convenience init(settings: NetworkConnectionSettings) {
        self.init(settings: settings, provider: { throw POSIXError(.ENOTCONN) })
    }

    deinit {
        if fd >= 0 { Darwin.close(fd) }
    }

    var status: NetworkConnectionStatus { lock.withLock { _status } }

    var isReady: Bool {
        if case .ready = status { true } else { false }
    }

    func setStatusUpdateHandler(_ statusUpdateHandler: NetworkConnectionStatusUpdateHandler?) {
        lock.withLock { handler = statusUpdateHandler }
    }

    func start(queue: DispatchQueue) {
        // Serial, so status changes arrive in order even though the library's queue is concurrent.
        lock.withLock { handlerQueue = DispatchQueue(label: "duoremote.fdconnection.status", target: queue) }
        update(.preparing)

        let timeout = DispatchTime.now() + .seconds(settings.connectionTimeout)
        queue.asyncAfter(deadline: timeout) { [weak self] in
            guard let self else { return }
            if case .preparing = self.status {
                self.lock.withLock { self.cancelled = true }
                self.update(.failed(POSIXError(.ETIMEDOUT)))
            }
        }

        let provider = provider
        dialQueue.async { [weak self] in
            let result = Result { try provider() }
            guard let self else {
                if case .success(let fd) = result { Darwin.close(fd) }
                return
            }
            switch result {
            case .success(let newFD):
                var on: Int32 = 1
                setsockopt(newFD, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                let keep = self.lock.withLock { () -> Bool in
                    guard !self.cancelled else { return false }
                    self.fd = newFD
                    return true
                }
                if keep { self.update(.ready) } else { Darwin.close(newFD) }
            case .failure(let error):
                if !self.lock.withLock({ self.cancelled }) { self.update(.failed(error)) }
            }
        }
    }

    func cancel() {
        let wasCancelled = lock.withLock { () -> Bool in
            defer { cancelled = true }
            // Wakes any blocked read or write; the descriptor is closed in deinit.
            if fd >= 0 { shutdown(fd, SHUT_RDWR) }
            return cancelled
        }
        if !wasCancelled { update(.cancelled) }
    }

    private func update(_ newStatus: NetworkConnectionStatus) {
        let (handler, queue) = lock.withLock { () -> (NetworkConnectionStatusUpdateHandler?, DispatchQueue?) in
            _status = newStatus
            return (self.handler, handlerQueue)
        }
        guard let handler else { return }
        if let queue { queue.async { handler(newStatus) } } else { handler(newStatus) }
    }

    private func descriptor() throws -> Int32 {
        let fd = lock.withLock { cancelled ? -1 : self.fd }
        guard fd >= 0 else { throw VNCError.connection(.closed) }
        return fd
    }
}

extension FileDescriptorNetworkConnection: NetworkConnectionReading {
    func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
        let fd = try descriptor()
        return try await withCheckedThrowingContinuation { continuation in
            readQueue.async {
                var buffer = [UInt8](repeating: 0, count: maximumLength)
                var count = 0
                while count < max(minimumLength, 1) {
                    let n = buffer.withUnsafeMutableBytes { raw in
                        Darwin.read(fd, raw.baseAddress! + count, maximumLength - count)
                    }
                    if n > 0 {
                        count += n
                    } else if n == 0 {
                        continuation.resume(throwing: VNCError.connection(.closed))
                        return
                    } else if errno != EINTR {
                        continuation.resume(throwing: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
                        return
                    }
                }
                continuation.resume(returning: Data(buffer.prefix(count)))
            }
        }
    }
}

extension FileDescriptorNetworkConnection: NetworkConnectionWriting {
    func write(data: Data) async throws {
        let fd = try descriptor()
        return try await withCheckedThrowingContinuation { continuation in
            writeQueue.async {
                var sent = 0
                while sent < data.count {
                    let n = data.withUnsafeBytes { raw in
                        Darwin.write(fd, raw.baseAddress! + sent, data.count - sent)
                    }
                    if n >= 0 {
                        sent += n
                    } else if errno != EINTR {
                        continuation.resume(throwing: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
                        return
                    }
                }
                continuation.resume()
            }
        }
    }
}
#endif

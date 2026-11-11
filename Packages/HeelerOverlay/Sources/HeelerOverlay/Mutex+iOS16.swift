import Foundation

// iOS 16: stand-in for Synchronization.Mutex (iOS 18+), backed by NSLock.
final class Mutex<Value: ~Copyable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: consuming Value) { self.value = value }
    func withLock<R: ~Copyable>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

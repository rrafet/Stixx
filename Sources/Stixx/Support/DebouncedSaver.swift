import Foundation

/// Coalesces rapid-fire change notifications (typing, dragging, resizing)
/// into a single save after a short quiet period, so we don't hit disk on
/// every keystroke. `flushNow()` guarantees a pending save lands immediately,
/// e.g. right before the app terminates.
@MainActor
final class DebouncedSaver {
    private let delay: TimeInterval
    private var timer: Timer?
    private var pendingWork: (() -> Void)?

    init(delay: TimeInterval = 0.6) {
        self.delay = delay
    }

    func schedule(_ work: @escaping () -> Void) {
        pendingWork = work
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.flushNow()
            }
        }
    }

    func flushNow() {
        timer?.invalidate()
        timer = nil
        let work = pendingWork
        pendingWork = nil
        work?()
    }
}

import Foundation

extension Notification.Name {
    static let keepAwakeStateChanged = Notification.Name("Aetherium.NoDoze.keepAwakeStateChanged")
}

public final class KeepAwakeCoordinator {
    private var model: Model
    public let assertion: PowerAssertion
    public var deadline: Date? { model.deadline }
    public var isSmartModeEnabled: Bool { model.smartEnabled }
    private let screens: ScreenObserver
    private let clock: Clock
    private let store: Store
    private var timerToken: Cancellable?
    private var task: Task<Void, Never>?

    public init(assertion: PowerAssertion,
                screens: ScreenObserver,
                clock: Clock,
                store: Store)
    {
        self.assertion = assertion
        self.screens = screens
        self.clock = clock
        self.store = store
        let smart = store[Preferences.smartMode]
        self.model = Model(mode: .off,
                           smartEnabled: smart,
                           deadline: nil)
    }

    public func start() {
        task = Task.detached { [weak self] in
            guard let self = self else { return }
            async let _ = self.process(stream: self.screens.screensDidSleep, as: Event.screensSlept)
            async let _  = self.process(stream: self.screens.screensDidWake,  as: Event.screensWoke)
        }
    }

    private func process(stream: AsyncStream<Void>, as event: @autoclosure @escaping () -> Event) async {
        for await _ in stream {
            send(event())
        }
    }

    public func send(_ event: Event) {
        DispatchQueue.main.async {
            let commands = self.model.step(event: event,
                                           displaysAllAsleep: self.screens.allDisplaysAsleep(),
                                           now: self.clock.now)
            self.execute(commands)
        }
    }

    private func execute(_ commands: [Command]) {
        for cmd in commands {
            switch cmd {
            case .acquireAssertion(let until):
                do {
                    try assertion.acquire(reason: "NoDoze KeepAwake", until: until)
                } catch {
                    print("Failed to acquire assertion: \(error)")
                }
            case .releaseAssertion:
                assertion.release()
            case .scheduleTimer(let date):
                let interval = max(0, date.timeIntervalSince(clock.now))
                timerToken?.cancel()
                timerToken = clock.schedule(after: interval) { [weak self] in
                    self?.send(.timerFired)
                }
            case .cancelTimer:
                timerToken?.cancel()
                timerToken = nil
            }
        }
        NotificationCenter.default.post(name: .keepAwakeStateChanged, object: self)
    }
}

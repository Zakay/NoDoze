import Foundation

enum Event {
    case userSelected(KeepMode)
    case smartModeToggled(Bool)
    case screensSlept
    case screensWoke
    case timerFired
} 
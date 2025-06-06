import Foundation

public enum KeepMode: Equatable {
    case off
    case until(Date)
    case indefinitely
}

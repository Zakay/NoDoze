import Foundation
import ServiceManagement

struct LoginItemManager {
    static func toggle(as newStatus: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if newStatus {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update login item status: \(error)")
            }
        }
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
} 
import SwiftUI

@main
struct JiraWeeklyTimeTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No window group — your UI is now hosted in the popover
        Settings {
            EmptyView()
        }
    }
}

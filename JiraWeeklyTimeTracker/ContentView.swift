import SwiftUI

struct ContentView: View {
    @State private var isLoggedIn = false
    @State private var client: JiraClient? = nil

    var body: some View {
        if isLoggedIn, let client {
            MainView(jiraClient: client) {
                // Logout action
                self.client = nil
                self.isLoggedIn = false
            }
        } else {
            LoginView(isLoggedIn: $isLoggedIn, client: $client)
        }
    }
}

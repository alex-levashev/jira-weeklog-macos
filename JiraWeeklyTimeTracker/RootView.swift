import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: SessionManager

    var body: some View {
        if session.isLoggedIn, let client = session.client {
            MainView(jiraClient: client) {
                session.logout()
            }
        } else {
            LoginView(isLoggedIn: $session.isLoggedIn, client: $session.client)
        }
    }
}

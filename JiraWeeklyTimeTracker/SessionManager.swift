import Foundation

class SessionManager: ObservableObject {
    @Published var isLoggedIn = false
    @Published var client: JiraClient?

    func tryAutoLogin() {
        let defaults = UserDefaults.standard
        guard
            let url = defaults.string(forKey: "jiraURL"),
            let username = defaults.string(forKey: "jiraUsername"),
            let password = LoginView.KeychainHelper.shared.read(service: "JiraWorklogApp", account: username)
        else {
            return
        }

        let apiClient = JiraClient(baseURL: url, username: username, password: password)
        apiClient.testConnection { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.client = apiClient
                    self.isLoggedIn = true
                case .failure:
                    break
                }
            }
        }
    }

    func logout() {
        self.client = nil
        self.isLoggedIn = false
    }
}

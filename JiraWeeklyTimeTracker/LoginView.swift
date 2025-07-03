import SwiftUI
import Security

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @Binding var client: JiraClient?
    
    @State private var jiraURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var statusMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Log in to Jira")
                .font(.title)
            
            TextField("Jira URL", text: $jiraURL)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disableAutocorrection(true)
                .textContentType(.URL)
            
            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(.username)
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(.password)
            
            if isLoading {
                ProgressView()
            } else {
                HStack(spacing: 16) {
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: [.command])
                    
                    Button("Log In") {
                        login()
                    }
                    .disabled(jiraURL.isEmpty || username.isEmpty || password.isEmpty)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
            
            Text(statusMessage)
                .foregroundColor(.gray)
                .font(.footnote)
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            loadSavedCredentials()
            
            if !jiraURL.isEmpty && !username.isEmpty && !password.isEmpty {
                login()
            }
        }
    }
    
    private func loadSavedCredentials() {
        let defaults = UserDefaults.standard
        if let savedURL = defaults.string(forKey: "jiraURL") {
            self.jiraURL = savedURL
        }
        if let savedUsername = defaults.string(forKey: "jiraUsername") {
            self.username = savedUsername
            if let savedPassword = KeychainHelper.shared.read(service: "JiraWorklogApp", account: savedUsername) {
                self.password = savedPassword
            }
        }
    }
    
    class KeychainHelper {
        static let shared = KeychainHelper()
        
        func save(service: String, account: String, password: String) {
            let data = password.data(using: .utf8)!
            
            let query: [CFString: Any] = [
                kSecClass: kSecClassInternetPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]
            SecItemDelete(query as CFDictionary)
            
            let attributes: [CFString: Any] = [
                kSecClass: kSecClassInternetPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecValueData: data
            ]
            SecItemAdd(attributes as CFDictionary, nil)
        }
        
        func read(service: String, account: String) -> String? {
            let query: [CFString: Any] = [
                kSecClass: kSecClassInternetPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne
            ]
            
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            
            guard status == errSecSuccess,
                  let data = result as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            return password
        }
        
        func delete(service: String, account: String) {
            let query: [CFString: Any] = [
                kSecClass: kSecClassInternetPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
    
    private func login() {
        statusMessage = "Connecting..."
        isLoading = true
        
        let trimmedURL = jiraURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiClient = JiraClient(baseURL: trimmedURL, username: username, password: password)
        
        apiClient.testConnection { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success:
                    self.statusMessage = "Login successful!"
                    
                    // 🔐 Save credentials
                    UserDefaults.standard.set(self.jiraURL, forKey: "jiraURL")
                    UserDefaults.standard.set(self.username, forKey: "jiraUsername")
                    KeychainHelper.shared.save(service: "JiraWorklogApp", account: self.username, password: self.password)
                    
                    self.client = apiClient
                    self.isLoggedIn = true
                case .failure(let error):
                    self.statusMessage = "Login failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

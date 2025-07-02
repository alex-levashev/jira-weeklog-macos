import Foundation

class JiraClient {
    private let baseURL: URL
    private let username: String
    private let password: String
    private let session: URLSession
    private(set) var displayName: String?

    init(baseURL: String, username: String, password: String, session: URLSession = .shared) {
        self.baseURL = URL(string: baseURL)!
        self.username = username
        self.password = password
        self.session = session
    }

    private var authHeader: String {
        let credentials = "\(username):\(password)"
        let data = credentials.data(using: .utf8)!
        let encoded = data.base64EncodedString()
        return "Basic \(encoded)"
    }
    
    struct WorklogEntry: Identifiable {
        let id: String
        let issueKey: String
        let issueSummary: String
        let authorName: String
        let started: Date
        let timeSpentSeconds: Int
    }
    
    func fetchFilteredWorklogs(for issues: [(key: String, summary: String)], from startDate: Date, to endDate: Date, completion: @escaping (Result<[WorklogEntry], Error>) -> Void) {
        let group = DispatchGroup()
        var allEntries: [WorklogEntry] = []
        var firstError: Error?

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for issue in issues {
            group.enter()

            let url = baseURL.appendingPathComponent("/rest/api/2/issue/\(issue.key)/worklog")
            var request = URLRequest(url: url)
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            session.dataTask(with: request) { data, response, error in
                defer { group.leave() }

                if let error = error {
                    firstError = error
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let worklogs = json["worklogs"] as? [[String: Any]] else {
                    return
                }

                for log in worklogs {
                    guard
                        let author = log["author"] as? [String: Any],
                        let authorName = author["displayName"] as? String,
                        let startedStr = log["started"] as? String,
                        let startedDate = dateFormatter.date(from: startedStr),
                        let timeSpentSeconds = log["timeSpentSeconds"] as? Int,
                        let id = log["id"] as? String
                    else {
                        continue
                    }

                    if authorName != self.displayName {
                        continue
                    }

                    if startedDate >= startDate && startedDate <= endDate {
                        allEntries.append(WorklogEntry(
                            id: id,
                            issueKey: issue.key,
                            issueSummary: issue.summary,
                            authorName: authorName,
                            started: startedDate,
                            timeSpentSeconds: timeSpentSeconds
                        ))
                    }
                }
            }.resume()
        }

        group.notify(queue: .main) {
            if let error = firstError {
                completion(.failure(error))
            } else {
                completion(.success(allEntries))
            }
        }
    }
    
    func fetchIssues(jql: String, completion: @escaping (Result<[(key: String, summary: String)], Error>) -> Void) {
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/api/2/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "fields", value: "key,summary")
        ]

        guard let url = components.url else {
            completion(.failure(NSError(domain: "JiraClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                return completion(.failure(error))
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let data = data else {
                return completion(.failure(NSError(domain: "JiraClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let issues = json["issues"] as? [[String: Any]] {
                    let results: [(String, String)] = issues.compactMap { issue in
                        guard let key = issue["key"] as? String,
                              let fields = issue["fields"] as? [String: Any],
                              let summary = fields["summary"] as? String else {
                            return nil
                        }
                        return (key, summary)
                    }
                    completion(.success(results))
                } else {
                    completion(.failure(NSError(domain: "JiraClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing issue data in response"])))
                }
            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }
    
    func createWorklog(
        for issueKey: String,
        hours: Double,
        startedAt started: Date = Date(),
        comment: String? = nil,
        visibilityIdentifier: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let url = baseURL.appendingPathComponent("/rest/api/2/issue/\(issueKey)/worklog")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let seconds = Int(hours * 3600)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let startedString = formatter.string(from: started)

        var payload: [String: Any] = [
            "timeSpentSeconds": seconds,
            "started": startedString,
        ]
        
        if let comment = comment, !comment.isEmpty {
            payload = [
                "timeSpentSeconds": seconds,
                "started": startedString,
                "comment": comment
            ]
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            return completion(.failure(error))
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                return completion(.failure(error))
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                return completion(.failure(NSError(domain: "JiraClient", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "No HTTP response"
                ])))
            }

            if (200...299).contains(httpResponse.statusCode) {
                completion(.success(()))
            } else {
                var serverMessage = "Failed to create worklog (HTTP \(httpResponse.statusCode))"
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let errorMessages = json["errorMessages"] as? [String], !errorMessages.isEmpty {
                        serverMessage = errorMessages.joined(separator: "; ")
                    } else if let errors = json["errors"] as? [String: Any] {
                        let errorsJoined = errors.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
                        serverMessage = errorsJoined
                    }
                }
                completion(.failure(NSError(domain: "JiraClient", code: httpResponse.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: serverMessage
                ])))
            }
        }.resume()
    }

    func testConnection(completion: @escaping (Result<String, Error>) -> Void) {
            let url = baseURL.appendingPathComponent("/rest/api/2/myself")
            var request = URLRequest(url: url)
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    return completion(.failure(error))
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data = data else {
                    return completion(.failure(NSError(domain: "JiraClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let name = json["displayName"] as? String {
                        self.displayName = name
                    }
                    let jsonString = String(data: data, encoding: .utf8) ?? "No JSON"
                    completion(.success(jsonString))
                } catch {
                    completion(.failure(error))
                }
            }

            task.resume()
        }
}

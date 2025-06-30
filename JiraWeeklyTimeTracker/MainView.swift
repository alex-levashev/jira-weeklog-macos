import SwiftUI
import WidgetKit

struct MainView: View {
    let jiraClient: JiraClient
    var onLogout: () -> Void
    var onRefresh: (() -> Void)? = nil
    
    @State private var timer: Timer?
    @State private var issueKeys: [String] = []
    @State private var worklogsCurrentWeek: [JiraClient.WorklogEntry] = []
    @State private var worklogsPreviousWeek: [JiraClient.WorklogEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var errorMessageLogTime: String?
    @State private var lastRefresh: Date? = nil
    
    @State private var showLogTimeSheet = false
    @State private var logTimeIssueKey = ""
    @State private var logTimeHours = ""
    @State private var isPostingWorklog = false
    @State private var postErrorMessage: String?
    
    @State private var issueKey = ""
    @State private var hours = ""
    @State private var comment = ""
    @State private var started: Date = Date()  // New date state
    @State private var isPosting = false

    var body: some View {
        VStack(spacing: 0) {
            // 🔼 Top bar
            HStack {
                if let name = jiraClient.displayName {
                    Text("Logged in as \(name)")
                        .font(.headline)
                } else {
                    Text("Logged in")
                        .font(.headline)
                }
                if let lastRefresh {
                    Text(" Last refresh: \(formattedDate(lastRefresh))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
                
                Button(action: {
                    loadData()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)

                Button("Logout") {
                    clearStoredPassword()
                    onLogout()
                }
                .keyboardShortcut("q", modifiers: [.command])
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color.gray.opacity(0.4), width: 0.5)

            
            Divider()
            
            HStack(spacing: 0) {
                Text("Log Work Time ")
                    .font(.headline)

                TextField("Issue Key", text: $issueKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 2)
                    .frame(width: 100)

                TextField("Hours", text: $hours)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 2)
                    .frame(width: 70)
                
                TextField("Comment", text: $comment)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 2)
                    .frame(width: 100)

                // Date/Time picker
                DatePicker("",selection: $started)
                    .datePickerStyle(FieldDatePickerStyle()) // macOS style, or .graphical
                    .padding(.horizontal, 2)

                if let error = errorMessageLogTime {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding(.horizontal, 2)
                }

                HStack {
                    Spacer()
        
                    Button("Log Time", systemImage: "plus") {
                        guard let hoursVal = Double(hours.trimmingCharacters(in: .whitespaces)) else {
                            errorMessageLogTime = "Invalid hours"
                            return
                        }

                        isPosting = true
                        errorMessageLogTime = nil

                        jiraClient.createWorklog(
                            for: issueKey.trimmingCharacters(in: .whitespaces),
                            hours: hoursVal,
                            startedAt: started,
                            comment: comment
                        ) { result in
                            DispatchQueue.main.async {
                                isPosting = false
                                switch result {
                                case .success:
                                    loadData()
                                    issueKey = ""
                                    hours = ""
                                    comment = ""
                                    started = Date()
                                case .failure(let err):
                                    errorMessageLogTime = err.localizedDescription
                                }
                            }
                        }
                    }
                    .disabled(isPosting)
        
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color.gray.opacity(0.4), width: 0.5)
            .disabled(isLoading)
            

            // 🔽 Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isLoading {
                        ProgressView("Loading worklogs…")
                    } else if let error = errorMessage {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("This Week")
                                .font(.title2)
                                .frame(maxWidth: .infinity, alignment: .center)

                            if worklogsCurrentWeek.isEmpty {
                                Text("No worklogs for this week.")
                            } else {
                                timesheetTable(logs: worklogsCurrentWeek)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Previous Week")
                                .font(.title2)
                                .frame(maxWidth: .infinity, alignment: .center)

                            if worklogsPreviousWeek.isEmpty {
                                Text("No worklogs for previous week.")
                            } else {
                                timesheetTable(logs: worklogsPreviousWeek)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 800, height: 500, alignment: .center)
        .onAppear {
            loadData()
            startAutoRefresh()
        }
    }
    
    private func resetLogTimeForm() {
        logTimeIssueKey = ""
        logTimeHours = ""
        postErrorMessage = nil
        isPostingWorklog = false
    }

    private func loadData() {
        isLoading = true
        errorMessage = nil

        let calendar = Calendar.current
        let now = Date()

        let startOfCurrentWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let endOfCurrentWeek = calendar.date(byAdding: .day, value: 7, to: startOfCurrentWeek)!

        let startOfPreviousWeek = calendar.date(byAdding: .day, value: -7, to: startOfCurrentWeek)!
        let endOfPreviousWeek = startOfCurrentWeek

        jiraClient.fetchIssueKeys(jql: "worklogAuthor = currentUser() AND worklogDate >= startOfWeek(-1) AND worklogDate <= endOfWeek()") { result in
            switch result {
            case .success(let keys):
                self.issueKeys = keys

                let group = DispatchGroup()
                var currentWeekLogs: [JiraClient.WorklogEntry] = []
                var previousWeekLogs: [JiraClient.WorklogEntry] = []
                var fetchError: Error?

                group.enter()
                jiraClient.fetchFilteredWorklogs(for: keys, from: startOfCurrentWeek, to: endOfCurrentWeek) { result in
                    if case .success(let logs) = result {
                        currentWeekLogs = logs
                    } else if case .failure(let error) = result {
                        fetchError = error
                    }
                    group.leave()
                }

                group.enter()
                jiraClient.fetchFilteredWorklogs(for: keys, from: startOfPreviousWeek, to: endOfPreviousWeek) { result in
                    if case .success(let logs) = result {
                        previousWeekLogs = logs
                    } else if case .failure(let error) = result {
                        fetchError = error
                    }
                    group.leave()
                }

                group.notify(queue: .main) {
                    self.isLoading = false
                    if let error = fetchError {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.worklogsCurrentWeek = currentWeekLogs
                        self.worklogsPreviousWeek = previousWeekLogs
                        self.lastRefresh = Date()

                        WidgetCenter.shared.reloadTimelines(ofKind: "WorklogWeekWidget")
                    }
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func startAutoRefresh() {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            loadData()
        }
    }
    
    private func clearStoredPassword() {
        let defaults = UserDefaults.standard
        if let savedUsername = defaults.string(forKey: "jiraUsername") {
            LoginView.KeychainHelper.shared.delete(service: "JiraWorklogApp", account: savedUsername)
        }
    }

    private func timesheetTable(logs: [JiraClient.WorklogEntry]) -> some View {
        let grouped = groupedWorklogsMatrix(logs: logs)
        let days = grouped.days
        let issues = grouped.issues
        let matrix = grouped.matrix

        let columnTotals: [Date: Int] = days.reduce(into: [:]) { result, day in
            result[day] = issues.reduce(0) { acc, issue in
                acc + (matrix[issue]?[day] ?? 0)
            }
        }

        let grandTotal = columnTotals.values.reduce(0, +)

        return ScrollView([.horizontal]) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    contentCell("Issue", width: 160)
                    ForEach(days, id: \.self) { day in
                        contentCell(weekdayFormatter.string(from: day), width: 70)
                    }
                    contentCell("Total", width: 70)
                }

                ForEach(issues, id: \.self) { issue in
                    HStack(spacing: 0) {
                        contentCell(issue, width: 160, alignment: .leading)

                        let dayEntries = matrix[issue] ?? [:]
                        let total = days.reduce(0) { $0 + (dayEntries[$1] ?? 0) }

                        ForEach(days, id: \.self) { day in
                            let value = dayEntries[day] ?? 0
                            contentCell(formatShortDuration(seconds: value), width: 70)
                        }

                        contentCell(formatShortDuration(seconds: total), width: 70, isBold: true)
                    }
                }

                HStack(spacing: 0) {
                    contentCell("Total", width: 160, alignment: .leading, isBold: true)
                    ForEach(days, id: \.self) { day in
                        let value = columnTotals[day] ?? 0
                        contentCell(formatShortDuration(seconds: value), width: 70, isBold: true)
                    }
                    contentCell(formatShortDuration(seconds: grandTotal), width: 70, isBold: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(6)
        }
    }

    private func contentCell(_ text: String, width: CGFloat, alignment: Alignment = .center, isBold: Bool = false) -> some View {
        Text(text)
            .font(.system(.body, design: .monospaced).weight(isBold ? .bold : .regular))
            .frame(width: width, height: 28, alignment: alignment)
            .background(Color(NSColor.textBackgroundColor))
            .border(Color.gray.opacity(0.4), width: 0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 2)
    }

    private func groupedWorklogsMatrix(logs: [JiraClient.WorklogEntry]) -> (issues: [String], days: [Date], matrix: [String: [Date: Int]]) {
        let calendar = Calendar.current
        guard let firstLogDate = logs.first?.started else {
            return ([], [], [:])
        }
        let firstDay = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: firstLogDate))!
        let days: [Date] = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstDay)
        }

        var matrix: [String: [Date: Int]] = [:]

        for log in logs {
            let issue = log.issueKey
            let day = calendar.startOfDay(for: log.started)
            guard days.contains(day) else { continue }

            matrix[issue, default: [:]][day, default: 0] += log.timeSpentSeconds
        }

        let issues = matrix.keys.sorted()
        return (issues, days, matrix)
    }

    private let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E"
        return f
    }()
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatShortDuration(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 && m > 0 {
            return "\(h): \(m)"
        } else if h > 0 {
            return "\(h)"
        } else if m > 0 {
            return "0:\(m)"
        } else {
            return "-"
        }
    }
}

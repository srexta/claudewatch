import SwiftUI
import ServiceManagement
import Security

struct Step: Identifiable { let id: String; let tool: String; let text: String; let path: String?; let start: Date?; var done: Bool; var msgId = ""; var tokens = 0; var end: Date? = nil }
struct TaskItem { let subject: String; let status: String }

// Everything we pull out of one transcript (main session or helper agent)
struct Log {
    var steps: [Step] = [], prompt = "", title = "", cwd: String?, lastStop = ""
    var out = 0, turns = 0, first: Date?, last: Date?, turnStart: Date?, todos: [TaskItem] = []
    var turnDurations: [TimeInterval] = [], turnCounted = false  // how long each finished prompt took
    var running: Step? { steps.last(where: { !$0.done }) }
    var finished: Bool { lastStop == "end_turn" && running == nil }
}

struct Agent: Identifiable { let id: String; let name: String; let finished: Bool; let log: Log }

struct Session: Identifiable {
    let id: String, sessionId: String, modified: Date, log: Log, tasks: [TaskItem], agents: [Agent]
    var output: [String] = []
    var expectedTurn: (TimeInterval, Int)? = nil   // typical prompt time, number of past prompts it is based on
    var expectedStep: (TimeInterval, Int)? = nil   // typical time of the running command
    var project: String { log.cwd.map { ($0 as NSString).lastPathComponent } ?? "?" }
    var title: String { log.title.isEmpty ? log.prompt : log.title }
    var working: Bool { agents.contains { !$0.finished } || (!log.finished && Date().timeIntervalSince(modified) < 300) }
    var progress: (done: Int, total: Int, label: String)? {
        if !tasks.isEmpty { return (tasks.filter { $0.status == "completed" }.count, tasks.count, "tasks") }
        if !agents.isEmpty { return (agents.filter(\.finished).count, agents.count, "agents") }
        return nil
    }
    var currentTask: String? { tasks.first { $0.status == "in_progress" }?.subject }
    func matches(_ q: String) -> Bool {
        q.isEmpty || ([project, title, log.prompt] + log.steps.map(\.text) + agents.map(\.name))
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser

func mtime(_ u: URL) -> Date? { try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
func name(_ path: String) -> String { (path as NSString).lastPathComponent }

// Turn a raw tool call into a short plain-English line; keep the file path separately for a link
func describe(_ tool: String, _ input: [String: Any]) -> (String, String?) {
    let s = { (k: String) in input[k] as? String ?? "" }
    switch tool {
    case "Bash":
        if !s("description").isEmpty { return (s("description"), nil) }
        // drop setup noise like `source nvm; nvm use; cd /path &&` and shorten paths
        let parts = s("command").components(separatedBy: CharacterSet(charactersIn: ";&|\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { p in !p.isEmpty && !["source ", "nvm ", "cd ", "export ", ". "].contains { p.hasPrefix($0) } }
        let cmd = (parts.first ?? s("command")).split(separator: " ").map { $0.hasPrefix("/") ? name(String($0)) : String($0) }.joined(separator: " ")
        return ("Running \(cmd)", nil)
    case "Read": return ("Reading", s("file_path"))
    case "Edit", "MultiEdit": return ("Editing", s("file_path"))
    case "Write": return ("Writing", s("file_path"))
    case "Grep", "Glob": return ("Searching for “\(s("pattern"))”", nil)
    case "Agent", "Task": return ("Started helper agent: \(s("description"))", nil)
    case "Skill": return ("Using skill \(s("skill"))", nil)
    case "WebSearch": return ("Searching the web: \(s("query"))", nil)
    case "WebFetch": return ("Opening \(s("url"))", nil)
    case "TodoWrite", "TaskCreate", "TaskUpdate": return ("Updating task list", nil)
    default: return (tool, nil)
    }
}

func parse(_ url: URL) -> Log {
    var log = Log(), msgTokens: [String: Int] = [:], stepIds = Set<String>()
    // ponytail: whole-file parse, cached per mtime in Store; fine up to tens of MB
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    for line in text.split(separator: "\n") {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
        if let t = obj["aiTitle"] as? String { log.title = t }
        if let c = obj["cwd"] as? String { log.cwd = c }
        guard let msg = obj["message"] as? [String: Any] else { continue }
        let ts = (obj["timestamp"] as? String).flatMap { iso.date(from: $0) }
        if let ts { log.first = log.first ?? ts; log.last = ts }
        let msgId = msg["id"] as? String ?? ""
        if !msgId.isEmpty, let t = (msg["usage"] as? [String: Any])?["output_tokens"] as? Int {
            msgTokens[msgId] = max(msgTokens[msgId] ?? 0, t)  // a reply is logged in chunks; keep the final count
        }
        if let s = msg["stop_reason"] as? String {
            log.lastStop = s
            if s == "end_turn", !log.turnCounted, let start = log.turnStart, let ts {
                log.turnDurations.append(ts.timeIntervalSince(start)); log.turnCounted = true
            }
        }
        let newPrompt = { (t: String) in
            guard !t.hasPrefix("<") else { return }
            log.prompt = t; log.turns += 1; log.lastStop = ""; log.turnStart = ts; log.turnCounted = false
        }
        if let t = msg["content"] as? String { newPrompt(t); continue }
        for item in msg["content"] as? [[String: Any]] ?? [] {
            switch item["type"] as? String {
            case "tool_use":
                guard let id = item["id"] as? String, stepIds.insert(id).inserted else { continue }
                let tool = item["name"] as? String ?? "?", input = item["input"] as? [String: Any] ?? [:]
                if tool == "TodoWrite", let todos = input["todos"] as? [[String: Any]] {
                    log.todos = todos.map { TaskItem(subject: $0["content"] as? String ?? "", status: $0["status"] as? String ?? "") }
                }
                let (text, path) = describe(tool, input)
                log.steps.append(Step(id: id, tool: tool, text: text, path: path, start: ts, done: false, msgId: msgId))
            case "tool_result":
                if let i = log.steps.firstIndex(where: { $0.id == item["tool_use_id"] as? String }) { log.steps[i].done = true; log.steps[i].end = ts }
            case "text" where obj["type"] as? String == "user":
                newPrompt(item["text"] as? String ?? "")
            default: break
            }
        }
    }
    // ponytail: a reply that made several tool calls credits its tokens to the first one
    var credited = Set<String>()
    for i in log.steps.indices where credited.insert(log.steps[i].msgId).inserted { log.steps[i].tokens = msgTokens[log.steps[i].msgId] ?? 0 }
    log.out = msgTokens.values.reduce(0, +)
    return log
}

func taskList(_ sessionId: String) -> [TaskItem] {
    let dir = home.appendingPathComponent(".claude/tasks/\(sessionId)")
    return ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "json" }
        .sorted { (Int($0.deletingPathExtension().lastPathComponent) ?? 0) < (Int($1.deletingPathExtension().lastPathComponent) ?? 0) }
        .compactMap { u in
            guard let d = try? Data(contentsOf: u), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
            return TaskItem(subject: o["subject"] as? String ?? "", status: o["status"] as? String ?? "")
        }
}

func tailText(_ url: URL, bytes: UInt64) -> String {
    guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
    defer { try? h.close() }
    let size = (try? h.seekToEnd()) ?? 0
    try? h.seek(toOffset: size > bytes ? size - bytes : 0)
    return String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
}

// Last lines of the newest command output Claude is writing for this session
func liveOutput(projectDir: String, sessionId: String) -> [String] {
    let dir = URL(fileURLWithPath: "/private/tmp/claude-\(getuid())/\(projectDir)/\(sessionId)/tasks")
    let newest = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
        .compactMap { u in mtime(u).map { (u, $0) } }.max { $0.1 < $1.1 }
    guard let (url, date) = newest, Date().timeIntervalSince(date) < 120 else { return [] }
    return tailText(url, bytes: 4000).split(separator: "\n").suffix(6).map(String.init)
}

func notify(_ title: String, _ body: String) {
    let esc = { (s: String) in s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "display notification \"\(esc(String(body.prefix(150))))\" with title \"\(esc(title))\" sound name \"Glass\""]
    try? p.run()
}

// MARK: - Plan usage limits + service status

struct Limit: Identifiable { let id: String; let title: String; let badge: String?; let subtitle: String?; let pct: Double; let resets: Date?; let window: TimeInterval }

// The app (not anyone else) reads Claude Code's login from the Keychain; macOS asks the user once
func debugLog(_ msg: String) {
    let url = home.appendingPathComponent("Library/Logs/ClaudeWatch.log")
    let line = "\(Date()) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

func readToken() -> String? {
    // Claude Code writes this item via /usr/bin/security, so that tool is already trusted to read it.
    // There can be several items with this name (one per account); use the first that holds the claude.ai login.
    for args in [["-a", NSUserName()], []] {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials"] + args + ["-w"]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { continue }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 0, let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let token = (o["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String { return token }
    }
    debugLog("no claudeAiOauth token found in Keychain")
    return nil
}

let isoPlain = ISO8601DateFormatter()
// API sends microseconds ("…00.499942+00:00"); drop the fraction so the formatter can read it
func parseDate(_ s: Any?) -> Date? {
    (s as? String).flatMap { isoPlain.date(from: $0.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)) }
}

func getJSON(_ req: URLRequest, _ done: @escaping ([String: Any]?, String?) -> Void) {
    URLSession.shared.dataTask(with: req) { data, resp, err in
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        debugLog("GET \(req.url?.host ?? "") -> \(code) \(err?.localizedDescription ?? "") \(String(decoding: (data ?? Data()).prefix(400), as: UTF8.self))")
        guard let data, code == 200, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return done(nil, err?.localizedDescription ?? "HTTP \(code)")
        }
        done(o, nil)
    }.resume()
}

final class Store: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var limits: [Limit] = []
    @Published var usageError: String?
    @Published var status = "Checking status…"
    @Published var statusOK = true
    private var timer: Timer?
    private var usageTimer: Timer?

    func loadUsage() {
        getJSON(URLRequest(url: URL(string: "https://status.claude.com/api/v2/status.json")!)) { o, _ in
            let st = o?["status"] as? [String: Any]
            DispatchQueue.main.async {
                self.status = st?["description"] as? String ?? "Status unavailable"
                self.statusOK = (st?["indicator"] as? String ?? "none") == "none"
            }
        }
        DispatchQueue.global().async {
            guard let token = readToken() else {
                return DispatchQueue.main.async { self.usageError = "No Claude Code login found in Keychain (or access was denied)" }
            }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            getJSON(req) { o, err in
                let specs: [(String, String, String?, String?, TimeInterval)] = [
                    ("five_hour", "Session Usage", nil, "5-hour rolling window", 5 * 3600),
                    ("seven_day", "All models", "Weekly", nil, 7 * 86_400),
                    ("seven_day_opus", "Opus", "Weekly", nil, 7 * 86_400),
                    ("seven_day_sonnet", "Sonnet", "Weekly", nil, 7 * 86_400),
                ]
                let limits = specs.compactMap { key, title, badge, sub, window -> Limit? in
                    guard let v = o?[key] as? [String: Any], let pct = (v["utilization"] as? NSNumber)?.doubleValue else { return nil }
                    return Limit(id: key, title: title, badge: badge, subtitle: sub, pct: pct, resets: parseDate(v["resets_at"]), window: window)
                }
                DispatchQueue.main.async {
                    self.limits = limits
                    self.usageError = o == nil ? "Couldn't load usage (\(err ?? "unknown"))" : nil
                }
            }
        }
    }
    private var cache: [String: (Date, Log)] = [:]
    private var wasFinished: [String: Bool] = [:]
    private var stuckNotified = Set<String>()
    private let queue = DispatchQueue(label: "store")

    init() {
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.load() }
        loadUsage()
        usageTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.loadUsage() }
    }

    private func cachedLog(_ url: URL, _ date: Date) -> Log {
        if let (d, l) = cache[url.path], d == date { return l }
        let l = parse(url)
        cache[url.path] = (date, l)
        return l
    }

    private func agents(_ sessionDir: URL) -> [Agent] {
        let dir = sessionDir.appendingPathComponent("subagents")
        return ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasSuffix(".meta.json") }
            .compactMap { meta in
                let jsonl = URL(fileURLWithPath: meta.path.replacingOccurrences(of: ".meta.json", with: ".jsonl"))
                guard let d = try? Data(contentsOf: meta), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                      let date = mtime(jsonl) else { return nil }
                return Agent(id: jsonl.path, name: o["description"] as? String ?? o["agentType"] as? String ?? "Agent",
                             finished: o["finished"] as? Bool ?? false, log: cachedLog(jsonl, date))
            }
            .sorted { ($0.log.first ?? .distantPast) < ($1.log.first ?? .distantPast) }
    }

    func load() {
        let stuckMinutes = max(1, UserDefaults.standard.object(forKey: "stuckMinutes") as? Int ?? 10)
        queue.async {
            let root = home.appendingPathComponent(".claude/projects")
            let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            var found: [(URL, Date)] = []
            for dir in dirs {
                for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                    if u.pathExtension == "jsonl", let d = mtime(u), Date().timeIntervalSince(d) < 7 * 86_400 { found.append((u, d)) }
                }
            }
            let files = found.sorted { $0.1 > $1.1 }.prefix { Date().timeIntervalSince($0.1) < 86_400 }.prefix(20)

            // History from the last 7 days: how long prompts (per project) and commands usually take
            var turnsByProject: [String: [TimeInterval]] = [:], cmdTimes: [String: [TimeInterval]] = [:]
            for (u, d) in found {
                let l = self.cachedLog(u, d)
                turnsByProject[l.cwd ?? "", default: []] += l.turnDurations
                for st in l.steps where st.tool == "Bash" {
                    if let a = st.start, let b = st.end { cmdTimes[st.text, default: []].append(b.timeIntervalSince(a)) }
                }
            }
            let allTurns = turnsByProject.values.flatMap { $0 }

            var result: [Session] = []
            for (url, date) in files {
                let sid = url.deletingPathExtension().lastPathComponent
                let log = self.cachedLog(url, date)
                let tasks = taskList(sid)
                var s = Session(id: url.path, sessionId: sid, modified: date, log: log,
                                tasks: tasks.isEmpty ? log.todos : tasks, agents: self.agents(url.deletingPathExtension()))
                let projectTurns = turnsByProject[log.cwd ?? ""] ?? []
                let samples = projectTurns.count >= 3 ? projectTurns : allTurns
                if samples.count >= 3 { s.expectedTurn = (median(samples), samples.count) }
                if let r = log.running, let past = cmdTimes[r.text], !past.isEmpty { s.expectedStep = (median(past), past.count) }
                if s.working { s.output = liveOutput(projectDir: url.deletingLastPathComponent().lastPathComponent, sessionId: sid) }

                if self.wasFinished[s.id] == false && log.finished { notify("✅ Done: \(s.title)", s.project) }
                self.wasFinished[s.id] = log.finished
                if let r = log.running, let start = r.start, Date().timeIntervalSince(start) > Double(stuckMinutes * 60),
                   self.stuckNotified.insert(r.id).inserted {
                    notify("⏳ Running \(stuckMinutes)+ min: \(s.title)", r.text + (r.path.map { " " + name($0) } ?? ""))
                }
                result.append(s)
            }
            DispatchQueue.main.async { self.sessions = result }
        }
    }
}

// ponytail: median of past runs is a rough guess; prompts vary a lot, so the UI labels it as an estimate
func median(_ xs: [TimeInterval]) -> TimeInterval { let s = xs.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }

func duration(_ from: Date?, _ to: Date? = nil) -> String {
    guard let from else { return "" }
    return fmt((to ?? Date()).timeIntervalSince(from))
}

func fmt(_ t: TimeInterval) -> String {
    let s = max(0, Int(t))
    return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m \(s % 60)s" : "\(s / 3600)h \(s / 60 % 60)m"
}

func tok(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk tok", Double(n) / 1000) : "\(n) tok" }

func openInVSCode(_ path: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-a", "Visual Studio Code", path]
    try? p.run()
}

// A step line: plain text, plus the file name as a clickable link
struct StepLine: View {
    let step: Step
    var body: some View {
        HStack(spacing: 4) {
            Text(step.text).lineLimit(1)
            if let p = step.path, !p.isEmpty {
                Button(name(p)) { openInVSCode(p) }.buttonStyle(.link).help(p)
            }
            if step.tokens > 0 { Text("· " + tok(step.tokens)).foregroundStyle(.tertiary).monospacedDigit() }
        }
    }
}

// Elapsed time as a % of how long this usually takes, with time left
struct TimeEstimate: View {
    let label: String, start: Date, typical: TimeInterval, basis: String
    var body: some View {
        let elapsed = Date().timeIntervalSince(start)
        let over = elapsed > typical
        let pct = over ? 100 : min(99, Int(elapsed / max(typical, 1) * 100))
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption.bold())
                ProgressView(value: Double(pct), total: 100).tint(over ? .orange : .blue)
                Text(over ? "over" : "~\(pct)%").font(.caption.monospacedDigit()).bold()
            }
            Text(over ? "Estimated time to finish: overdue · usually \(fmt(typical)), running \(fmt(elapsed))"
                      : "Estimated time to finish: \(fmt(typical - elapsed)) · usually takes \(fmt(typical)) (from \(basis))")
                .font(.caption2).foregroundStyle(over ? .orange : .secondary)
        }
    }
}

// One step with a done/running icon and how long it took (or has been running)
struct StepRow: View {
    let step: Step
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: step.done ? "checkmark" : "arrow.triangle.2.circlepath")
                .frame(width: 12).foregroundStyle(step.done ? Color.secondary : Color.orange)
            StepLine(step: step)
            Spacer()
            Text(duration(step.start, step.done ? step.end : nil)).monospacedDigit().foregroundStyle(.tertiary)
        }.font(.caption)
    }
}

// A helper agent: name, totals, its task, and an expandable list of what it did
struct AgentRow: View {
    let a: Agent
    @State private var open: Bool?
    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { open ?? !a.finished }, set: { open = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                if !a.log.prompt.isEmpty {
                    Text("Task: " + a.log.prompt).foregroundStyle(.secondary).lineLimit(3).padding(.bottom, 2)
                }
                if a.log.steps.isEmpty { Text("Starting…").foregroundStyle(.tertiary) }
                ForEach(a.log.steps.suffix(20).reversed()) { StepRow(step: $0) }
            }.font(.caption).padding(.leading, 4)
        } label: {
            HStack {
                Image(systemName: a.finished ? "checkmark.circle.fill" : "circle.dotted")
                    .foregroundStyle(a.finished ? .green : .orange)
                Text(a.name).lineLimit(1)
                Spacer()
                Text("\(a.log.steps.count) steps · " + tok(a.log.out) + " · " + duration(a.log.first, a.finished ? a.log.last : nil))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }.font(.caption)
    }
}

struct SessionCard: View {
    let s: Session
    @State private var showSteps = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(s.working ? .green : .gray).frame(width: 8, height: 8)
                Text(s.title).bold().lineLimit(2)
                Spacer()
                Text(s.working ? duration(s.log.turnStart) : "took " + duration(s.log.turnStart, s.log.last))
                    .font(.caption.monospacedDigit()).foregroundStyle(s.working ? .green : .secondary)
            }
            HStack(spacing: 6) {
                if let cwd = s.log.cwd { Button(s.project) { openInVSCode(cwd) }.buttonStyle(.link).help(cwd) }
                Text("· \(s.working ? "Working" : "Finished") · \(s.log.out.formatted()) tokens written")
                    .foregroundStyle(.secondary)
            }.font(.caption)

            if s.working, let start = s.log.turnStart, let (typical, n) = s.expectedTurn {
                TimeEstimate(label: "This prompt", start: start, typical: typical, basis: "\(n) past prompts")
            }

            if let p = s.progress {
                HStack {
                    ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                    Text("\(p.done * 100 / max(p.total, 1))%").font(.caption.monospacedDigit()).bold()
                }
                Text("\(p.done) of \(p.total) \(p.label) done" + (s.currentTask.map { " · now: \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else if s.working {
            }

            if let r = s.log.running {
                HStack(spacing: 4) {
                    Text("Now:").bold()
                    StepLine(step: r)
                    Spacer()
                    Text(duration(r.start)).monospacedDigit()
                }.font(.caption).foregroundStyle(.orange)
                if let start = r.start, let (typical, n) = s.expectedStep {
                    TimeEstimate(label: "This command", start: start, typical: typical, basis: "\(n) past run\(n == 1 ? "" : "s")")
                }
            }

            if !s.output.isEmpty {
                Text(s.output.joined(separator: "\n")).font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.white)
            }

            if !s.agents.isEmpty {
                Text("Helper agents").font(.caption.bold()).padding(.top, 2)
                ForEach(s.agents) { AgentRow(a: $0) }
            }

            DisclosureGroup("Recent steps", isExpanded: $showSteps) {
                ForEach(s.log.steps.suffix(15).reversed()) { StepRow(step: $0) }
            }.font(.caption)
        }
        .padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

func barColor(_ pct: Double) -> Color { pct < 50 ? .green : pct < 80 ? .orange : .red }

// Filled bar = how much of the limit is used; white tick = how far through the time window we are
struct UsageBar: View {
    let pct: Double
    var elapsed: Double? = nil
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(barColor(pct)).frame(width: g.size.width * min(max(pct, 0), 100) / 100)
                if let e = elapsed {
                    RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 3, height: height + 6)
                        .offset(x: g.size.width * min(max(e, 0), 1) - 1.5)
                }
            }
        }.frame(height: height + 6)
    }
}

func resetText(_ d: Date?) -> String {
    guard let d else { return "" }
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDateInToday(d) ? "'Today' HH:mm" : "MMM d, HH:mm"
    return "Resets " + f.string(from: d)
}

struct LimitCard: View {
    let l: Limit
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(l.title).font(.headline)
                if let b = l.badge {
                    Text(b).font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                Spacer()
                Text("\(Int(l.pct.rounded()))%").font(.headline.monospacedDigit()).foregroundStyle(barColor(l.pct))
            }
            if let s = l.subtitle { Text(s).font(.caption).foregroundStyle(.secondary) }
            UsageBar(pct: l.pct, elapsed: l.resets.map { 1 - $0.timeIntervalSinceNow / l.window })
            Text(resetText(l.resets)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct UsageHeader: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(store.statusOK ? .green : .orange).frame(width: 8, height: 8)
                Text(store.status).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button { store.loadUsage() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
            if let e = store.usageError { Text(e).font(.caption).foregroundStyle(.orange) }
            HStack(spacing: 8) { ForEach(store.limits.prefix(2)) { LimitCard(l: $0) } }
            if store.limits.count > 2 { HStack(spacing: 8) { ForEach(store.limits.dropFirst(2)) { LimitCard(l: $0) } } }
        }
    }
}

// Menu bar icon: ✳︎ + active-session count + a small session-usage bar, drawn to an image
struct MenuBarLabel: View {
    let active: Int
    let session: Limit?
    let dark: Bool
    var body: some View {
        HStack(spacing: 6) {
            Text(active > 0 ? "✳︎ \(active)" : "✳︎").font(.system(size: 13))
            if let s = session {
                VStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).stroke(.primary.opacity(0.6), lineWidth: 1)
                        RoundedRectangle(cornerRadius: 2).fill(barColor(s.pct))
                            .frame(width: max(2, 34 * s.pct / 100)).padding(1.5)
                        if let r = s.resets {
                            Rectangle().fill(.primary).frame(width: 1.5, height: 9)
                                .offset(x: 37 * min(max(1 - r.timeIntervalSinceNow / s.window, 0), 1))
                        }
                    }.frame(width: 37, height: 10)
                    Text("Session").font(.system(size: 8, weight: .semibold))
                }
            }
        }
        .foregroundStyle(.primary)
        .environment(\.colorScheme, dark ? .dark : .light)
        .padding(.horizontal, 1)
    }
}

struct Panel: View {
    @ObservedObject var store: Store
    @State private var query = ""
    @AppStorage("stuckMinutes") private var stuckMinutes = 10
    @State private var atLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading) {
            UsageHeader(store: store)
            Divider()
            TextField("Search sessions, tasks, commands, agents…", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing: 8) { ForEach(store.sessions.filter { $0.matches(query) }) { SessionCard(s: $0) } }
            }
            Divider()
            Stepper("Alert if a command runs over \(stuckMinutes) min", value: $stuckMinutes, in: 1...120).font(.caption)
            HStack {
                Toggle("Start at login", isOn: $atLogin).font(.caption)
                    .onChange(of: atLogin) { on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        atLogin = SMAppService.mainApp.status == .enabled
                    }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(10).frame(width: 500, height: 760)
    }
}

@main
struct ClaudeWatchApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let r = ImageRenderer(content: MenuBarLabel(active: store.sessions.filter(\.working).count,
                                                        session: store.limits.first { $0.id == "five_hour" }, dark: dark))
            let _ = (r.scale = NSScreen.main?.backingScaleFactor ?? 2)
            if let img = r.nsImage { Image(nsImage: img) } else { Text("✳︎") }
        }
        .menuBarExtraStyle(.window)
    }
}

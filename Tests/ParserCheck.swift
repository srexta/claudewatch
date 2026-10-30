import Foundation

// Self-check for the transcript parser: run with ./check.sh
let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
let tmp = URL(fileURLWithPath: CommandLine.arguments[2])

let whole = Parser()
whole.advance(fixture)
let l = whole.log

assert(l.title == "Fix flaky tests")
assert(l.cwd == "/Users/demo/app")
assert(l.prompt == "now add a changelog" && l.turns == 2)
assert(l.steps.count == 3, "duplicate tool_use lines must be merged")
assert(l.steps[0].text == "Running pnpm test", "setup noise (source/cd) must be stripped")
assert(l.steps[0].done && l.steps[1].done && !l.steps[2].done)
assert(l.running?.id == "t3")
assert(l.steps[0].tokens == 120, "chunked usage must keep the final count")
assert(l.out == 120 + 40 + 30 + 5)
assert(l.turnDurations == [180], "first prompt took 3 minutes")
assert(!l.finished)

// Same file fed in pieces, cut mid-line, must give the same result as one read
let data = try Data(contentsOf: fixture)
let inc = Parser()
for cut in [data.count / 3 + 7, data.count * 2 / 3 + 13, data.count] {
    try data.prefix(cut).write(to: tmp)
    inc.advance(tmp)
}
let b = inc.log
assert(b.steps.map(\.id) == l.steps.map(\.id) && b.steps.map(\.done) == l.steps.map(\.done))
assert(b.steps.map(\.tokens) == l.steps.map(\.tokens) && b.out == l.out && b.turnDurations == l.turnDurations)

// Microsecond timestamps from the usage API
assert(parseDate("2026-10-30T10:10:00.499942+00:00") != nil)

print("ParserCheck OK")

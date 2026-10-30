#!/bin/sh
# Lint + parser self-check. Builds a throwaway binary from the app code minus its @main entry point.
set -e
cd "$(dirname "$0")"
swift format lint --strict ClaudeWatch.swift Tests/ParserCheck.swift
tmp=$(mktemp -d)
sed '/^@main/,$d' ClaudeWatch.swift > "$tmp/lib.swift"
cp Tests/ParserCheck.swift "$tmp/main.swift"
swiftc -swift-version 5 "$tmp/lib.swift" "$tmp/main.swift" -o "$tmp/check"
"$tmp/check" Tests/fixture.jsonl "$tmp/partial.jsonl"
rm -rf "$tmp"

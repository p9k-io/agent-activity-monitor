import AAMCore
import Darwin
import Foundation

/// What a Codex rollout file says about the Session right now.
///
/// A rollout is a file of JSON lines that only grows. A turn starts with a `task_started` event
/// and ends with `task_complete` or `turn_aborted`; whichever comes last decides the state. A
/// long turn writes hundreds of megabytes after its start event, so the file is searched
/// backwards for the event text and only the few matching lines are parsed.
struct RolloutTail {
  let state: SessionState
  let lastActivityAt: Date?

  private static let chunkSize = 4 * 1024 * 1024
  /// A turn event is a few hundred bytes. A match inside a longer line is quoted tool output.
  private static let eventLineLimit = 4096
  private static let turnEvents: [(text: [UInt8], state: SessionState)] = [
    (Array("\"type\":\"task_started\"".utf8), .working),
    (Array("\"type\":\"task_complete\"".utf8), .idle),
    (Array("\"type\":\"turn_aborted\"".utf8), .idle),
  ]
  /// Every line starts this way. A raw newline cannot occur inside a JSON string, so the text
  /// marks the start of a line wherever it is found.
  private static let lineStart = Array("\n{\"timestamp\":\"".utf8)
  private static let timeWindows = [64 * 1024, 4 * 1024 * 1024, 64 * 1024 * 1024]

  init(path: String) {
    guard let handle = FileHandle(forReadingAtPath: path),
      let size = try? handle.seekToEnd()
    else {
      state = .unknown
      lastActivityAt = nil
      return
    }
    defer { try? handle.close() }
    lastActivityAt = Self.lastLineTime(in: handle, size: size)
    state = Self.lastTurnState(in: handle, size: size) ?? .unknown
  }

  // MARK: Last activity

  private static func lastLineTime(in handle: FileHandle, size: UInt64) -> Date? {
    for window in timeWindows {
      let start = size > UInt64(window) ? size - UInt64(window) : 0
      guard let bytes = read(handle, from: start, to: size) else { return nil }
      let line: ArraySlice<UInt8>?
      if let found = offsets(of: lineStart, in: bytes).last {
        line = bytes[(found + 1)...]
      } else if start == 0, bytes.starts(with: lineStart.dropFirst()) {
        line = bytes[...]
      } else {
        line = nil
      }
      if let line {
        return time(at: line.dropFirst(lineStart.count - 1))
      }
      if start == 0 { break }
    }
    return nil
  }

  /// The time written at the start of `text`, which begins right after `"timestamp":"`.
  private static func time(at text: ArraySlice<UInt8>) -> Date? {
    let stamp = String(decoding: text.prefix(64).prefix { $0 != UInt8(ascii: "\"") }, as: UTF8.self)
    return (try? Date(stamp, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
      ?? (try? Date(stamp, strategy: .iso8601))
  }

  // MARK: Turn state

  private static func lastTurnState(in handle: FileHandle, size: UInt64) -> SessionState? {
    let overlap = UInt64(turnEvents.map(\.text.count).max() ?? 0)
    var end = size
    while end > 0 {
      let start = end > UInt64(chunkSize) ? end - UInt64(chunkSize) : 0
      // Reading a little past `end` catches an event text split between two chunks.
      guard let bytes = read(handle, from: start, to: min(size, end + overlap)) else { return nil }
      let matches = turnEvents.flatMap { event in
        offsets(of: event.text, in: bytes).map { (offset: start + UInt64($0), state: event.state) }
      }
      for match in matches.sorted(by: { $0.offset > $1.offset })
      where isTurnEvent(at: match.offset, in: handle, size: size) {
        return match.state
      }
      end = start
    }
    return nil
  }

  /// Whether the event text at `offset` sits in a real turn event line, not in quoted output.
  private static func isTurnEvent(at offset: UInt64, in handle: FileHandle, size: UInt64) -> Bool {
    let limit = UInt64(eventLineLimit)
    let start = offset > limit ? offset - limit : 0
    let end = min(size, offset + limit)
    guard let window = read(handle, from: start, to: end) else { return false }
    let position = Int(offset - start)
    let newline = UInt8(ascii: "\n")

    let lineStart: Int
    if let before = window[..<position].lastIndex(of: newline) {
      lineStart = before + 1
    } else if start == 0 {
      lineStart = 0
    } else {
      return false
    }
    let lineEnd: Int
    if let after = window[position...].firstIndex(of: newline) {
      lineEnd = after
    } else if end == size {
      lineEnd = window.count
    } else {
      return false
    }

    guard
      let entry = try? JSONSerialization.jsonObject(with: Data(window[lineStart..<lineEnd]))
        as? [String: Any],
      entry["type"] as? String == "event_msg",
      let payload = entry["payload"] as? [String: Any],
      let type = payload["type"] as? String
    else { return false }
    return ["task_started", "task_complete", "turn_aborted"].contains(type)
  }

  // MARK: Bytes

  private static func read(_ handle: FileHandle, from start: UInt64, to end: UInt64) -> [UInt8]? {
    guard end > start, (try? handle.seek(toOffset: start)) != nil,
      let data = try? handle.read(upToCount: Int(end - start))
    else { return nil }
    return [UInt8](data)
  }

  /// Every position at which `needle` occurs in `haystack`, in ascending order.
  private static func offsets(of needle: [UInt8], in haystack: [UInt8]) -> [Int] {
    var found: [Int] = []
    haystack.withUnsafeBytes { hay in
      guard let base = hay.baseAddress else { return }
      var position = 0
      while position <= hay.count - needle.count,
        let match = memmem(base + position, hay.count - position, needle, needle.count)
      {
        let offset = UnsafeRawPointer(match) - base
        found.append(offset)
        position = offset + 1
      }
    }
    return found
  }
}

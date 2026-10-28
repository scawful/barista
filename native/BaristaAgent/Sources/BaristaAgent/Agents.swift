import Foundation
import SwiftUI

struct AgentSession: Equatable, Identifiable {
  let id: String
  /// The bundle ID of the app whose tile shows this session.
  let app: String
  let title: String
  let detail: String
  /// Still producing output; a session that stops working needs a look.
  let working: Bool
  /// What the session waits on you for, such as a question or a permission
  /// dialog; empty while it does not.
  var needs = ""
  let color: Color?
  /// Shell command that brings this session's window or chat forward.
  let focus: String
}

struct AgentSnapshot: Equatable {
  /// By app bundle ID, how many sessions wait on you; only these badge tiles.
  var needs: [String: Int] = [:]
  var sessions: [AgentSession] = []
  /// Plan usage by app bundle ID, such as Codex's `88% wk`.
  var usage: [String: String] = [:]
}

/// Agent sessions written by `scripts/agent_sessions.py apply` each time the
/// bar's agents widget refreshes (every 30 s).
enum AgentFeed {
  /// An older file means the widget stopped refreshing, so it is ignored.
  static let staleAfter: TimeInterval = 600

  static let url: URL = {
    if let path = ProcessInfo.processInfo.environment["BARISTA_AGENT_BADGES_FILE"], !path.isEmpty {
      return URL(fileURLWithPath: path)
    }
    return BaristaAppearance.stateURL.deletingLastPathComponent()
      .appendingPathComponent("cache/agent_sessions.json")
  }()

  static func load(now: Date = Date()) -> AgentSnapshot {
    (try? Data(contentsOf: url)).map { decode($0, now: now) } ?? AgentSnapshot()
  }

  static func decode(_ data: Data, now: Date) -> AgentSnapshot {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let updated = object["updated"] as? Double,
          now.timeIntervalSince1970 - updated < staleAfter
    else { return AgentSnapshot() }
    let needs = (object["needs"] as? [String: Any] ?? [:])
      .compactMapValues { ($0 as? Int).flatMap { $0 > 0 ? $0 : nil } }
    let sessions = (object["sessions"] as? [[String: Any]] ?? []).compactMap { record -> AgentSession? in
      guard let id = record["id"] as? String, let app = record["app"] as? String, !app.isEmpty else { return nil }
      return AgentSession(id: id, app: app,
                          title: record["title"] as? String ?? "",
                          detail: record["detail"] as? String ?? "",
                          working: record["working"] as? Bool ?? false,
                          needs: record["needs"] as? String ?? "",
                          color: DockTheme.color(record["color"], opaque: true),
                          focus: record["focus"] as? String ?? "")
    }
    let usage = (object["usage"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
    return AgentSnapshot(needs: needs, sessions: sessions, usage: usage)
  }
}

/// Sessions that finished since you last looked. A session is finished when
/// one snapshot saw it working and a later one sees it idle without waiting
/// on you (that shows as needing you instead); closing it or starting it
/// again clears it.
struct AgentAttention: Equatable {
  private var working: Set<String> = []
  /// Session ID to app bundle ID.
  private(set) var finished: [String: String] = [:]

  var apps: Set<String> { Set(finished.values) }

  /// `frontmost` is the active app's bundle ID; you are already looking at it.
  mutating func update(_ sessions: [AgentSession], frontmost: String?) {
    let idle = Dictionary(sessions.filter { !$0.working && $0.needs.isEmpty }.map { ($0.id, $0.app) },
                          uniquingKeysWith: { first, _ in first })
    finished = finished.filter { idle[$0.key] != nil }
    for id in working {
      if let app = idle[id], app != frontmost { finished[id] = app }
    }
    working = Set(sessions.filter(\.working).map(\.id))
  }

  mutating func clear(app: String) {
    finished = finished.filter { $0.value != app }
  }

  mutating func clear(session: String) {
    finished[session] = nil
  }
}

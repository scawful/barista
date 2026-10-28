import AppKit
import SwiftUI
import XCTest
@testable import barista_agent

final class DockConfigTests: XCTestCase {
  func testRasterizedIconsFillTheirBitmap() throws {
    let source = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
      NSColor.red.setFill()
      rect.fill()
      return true
    }
    guard case .image(let image) = TileImage.image(source).rasterized(pixels: 100),
          let rep = image.representations.first as? NSBitmapImageRep
    else { return XCTFail("expected a bitmap") }
    XCTAssertEqual(image.size, NSSize(width: 50, height: 50))
    XCTAssertEqual(rep.pixelsWide, 100)
    for (x, y) in [(2, 2), (97, 2), (2, 97), (97, 97), (50, 50)] {
      XCTAssertEqual(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0, 1, accuracy: 0.01, "pixel \(x),\(y)")
    }
  }

  func testNativeDockTilesBecomeItems() {
    let tiles: [[String: Any]] = [
      ["tile-type": "file-tile", "tile-data": [
        "bundle-identifier": "com.apple.Safari",
        "file-data": ["_CFURLString": "file:///Applications/Safari.app/"],
      ]],
      ["tile-type": "directory-tile", "tile-data": [
        "file-data": ["_CFURLString": "file:///Users/me/Downloads/"],
      ]],
      ["tile-type": "url-tile", "tile-data": [
        "label": "Docs",
        "url": ["_CFURLString": "https://example.com"],
      ]],
      ["tile-type": "spacer-tile", "tile-data": [:]],
    ]
    let items = DockConfigFile.items(fromNativeTiles: tiles)
    XCTAssertEqual(items, [
      DockItem(kind: .app, path: "/Applications/Safari.app", bundleID: "com.apple.Safari"),
      DockItem(kind: .folder, path: "/Users/me/Downloads"),
      DockItem(kind: .url, title: "Docs", url: "https://example.com"),
    ])
  }

  func testPartialConfigGetsDefaultsAndClamps() throws {
    let json = #"{"settings": {"icon_size": 400, "magnification": 0.5}, "pinned": [{"kind": "action", "title": "Hi", "command": "echo hi"}]}"#
    let config = try DockConfigFile.decode(Data(json.utf8))
    XCTAssertEqual(config.settings.iconSize, 96)
    XCTAssertEqual(config.settings.magnification, 1)
    XCTAssertEqual(config.settings.hideDelay, DockSettings().hideDelay)
    XCTAssertEqual(config.settings.filesBrowser, "barista", "the Finder tile opens Barista Files by default")
    XCTAssertEqual(config.pinned.first?.command, "echo hi")
    XCTAssertEqual(config.others, [])
    let finder = try DockConfigFile.decode(Data(#"{"settings": {"files_browser": "finder"}}"#.utf8))
    XCTAssertEqual(finder.settings.filesBrowser, "finder")
  }

  func testRoundTripKeepsSnakeCaseKeys() throws {
    var config = DockConfig()
    config.pinned = [DockItem(kind: .app, path: "/Applications/Safari.app", bundleID: "com.apple.Safari")]
    let data = try DockConfigFile.encode(config)
    let text = String(decoding: data, as: UTF8.self)
    XCTAssertTrue(text.contains("\"bundle_id\" : \"com.apple.Safari\""))
    XCTAssertTrue(text.contains("\"icon_size\""))
    XCTAssertEqual(try DockConfigFile.decode(data), config)
  }

  func testEditsKeepItemsUniqueAndOrdered() {
    let a = DockItem(kind: .app, bundleID: "a")
    let b = DockItem(kind: .app, bundleID: "b")
    let c = DockItem(kind: .app, bundleID: "c")
    var config = DockConfig(pinned: [a, b])
    config.insert([b, c], at: 0, in: .pinned)
    XCTAssertEqual(config.pinned.map(\.key), ["c", "a", "b"])
    config.move(key: "c", to: 2, in: .pinned)
    XCTAssertEqual(config.pinned.map(\.key), ["a", "b", "c"])
    config.remove(key: "b")
    XCTAssertEqual(config.pinned.map(\.key), ["a", "c"])

    config.others = [a]
    config.dedupe()
    XCTAssertEqual(config.others, [])
  }

  func testDedupeKeepsSameTitledActionsWithDifferentCommands() {
    let oracle = DockItem(kind: .action, title: "Build", command: "make oracle")
    let yaze = DockItem(kind: .action, title: "Build", command: "make yaze")
    var config = DockConfig(pinned: [
      DockItem(kind: .group, title: "Oracle", items: [oracle]),
      DockItem(kind: .group, title: "Yaze", items: [yaze, oracle]),
    ])
    config.dedupe()
    XCTAssertEqual(config.pinned[0].items, [oracle])
    XCTAssertEqual(config.pinned[1].items, [yaze])
    let logs = [oracle.key, yaze.key, yaze.key + "/Clean"].map(ActionRunner.slug)
    XCTAssertTrue(logs.allSatisfy { $0.hasPrefix("Build-") && $0.count == 14 }, "\(logs)")
    XCTAssertEqual(Set(logs).count, 3, "each action, and each menu entry on one, has its own log")
    XCTAssertEqual(ActionRunner.slug(yaze.key), logs[1], "the same in every run")
  }

  func testGroupsWrapMoveAndUnwrapMembers() {
    let a = DockItem(kind: .app, bundleID: "a")
    let b = DockItem(kind: .app, bundleID: "b")
    let c = DockItem(kind: .app, bundleID: "c")
    var config = DockConfig(pinned: [a, b, c])

    XCTAssertTrue(config.makeGroup(title: "AI", with: b))
    XCTAssertFalse(config.makeGroup(title: "AI", with: c))
    XCTAssertEqual(config.pinned.map(\.key), ["a", "group:AI", "c"])

    config.add(c, toGroup: "group:AI")
    config.add(a, toGroup: "group:Missing")
    XCTAssertEqual(config.pinned.map(\.key), ["a", "group:AI"])
    XCTAssertEqual(config.groups.first?.items?.map(\.key), ["b", "c"])

    config.insert([c], at: nil, in: .others)
    XCTAssertEqual(config.others, [], "group members count as already in the dock")

    config.takeOut("b", fromGroup: "group:AI")
    XCTAssertEqual(config.pinned.map(\.key), ["a", "group:AI", "b"])

    XCTAssertTrue(config.renameGroup("group:AI", to: "Agents"))
    config.ungroup("group:Agents")
    XCTAssertEqual(config.pinned.map(\.key), ["a", "c", "b"])
  }

  func testRemovingAMemberAndDedupeInsideGroups() throws {
    let json = #"""
    {"pinned": [
      {"kind": "app", "bundle_id": "a"},
      {"kind": "group", "title": "G", "items": [
        {"kind": "app", "bundle_id": "a"},
        {"kind": "app", "bundle_id": "b"},
        {"kind": "group", "title": "Nested", "items": []}
      ]}
    ]}
    """#
    var config = try DockConfigFile.decode(Data(json.utf8))
    XCTAssertEqual(config.groups.first?.items?.map(\.key), ["b", "group:Nested"], "subgroups stay")
    config.remove(key: "b")
    XCTAssertEqual(config.groups.first?.items?.map(\.key), ["group:Nested"])
  }

  func testSubgroupsNestMoveAndHideMembers() throws {
    let json = #"""
    {"pinned": [
      {"kind": "group", "title": "Oracle", "items": [
        {"kind": "app", "bundle_id": "mesen"},
        {"kind": "group", "title": "Tools", "items": [
          {"kind": "action", "title": "z3dk", "command": "z3dk"},
          {"kind": "group", "title": "Oracle", "items": []}
        ]}
      ]},
      {"kind": "group", "title": "Studio", "items": [{"kind": "app", "bundle_id": "logic"}]},
      {"kind": "app", "bundle_id": "z3dk-app"}
    ]}
    """#
    var config = try DockConfigFile.decode(Data(json.utf8))
    XCTAssertEqual(config.groups.map(\.key), ["group:Oracle", "group:Tools", "group:Studio"],
                   "a subgroup reusing a group's title is dropped")
    XCTAssertFalse(config.renameGroup("group:Studio", to: "Tools"), "titles are unique across subgroups")

    config.add(DockItem(kind: .app, bundleID: "z3dk-app"), toGroup: "group:Tools")
    XCTAssertEqual(config.pinned.map(\.key), ["group:Oracle", "group:Studio"])
    XCTAssertEqual(config.groups[1].items?.map(\.key), ["action:z3dk\tz3dk", "z3dk-app"])
    config.insert([DockItem(kind: .app, bundleID: "z3dk-app")], at: nil, in: .others)
    XCTAssertEqual(config.others, [], "subgroup members count as already in the dock")

    let tools = config.groups[1]
    config.add(tools, toGroup: "group:Tools")
    XCTAssertEqual(config.groups.map(\.key), ["group:Oracle", "group:Tools", "group:Studio"],
                   "a group can't move into itself")
    config.add(config.groups[0], toGroup: "group:Tools")
    XCTAssertEqual(config.pinned.map(\.key), ["group:Oracle", "group:Studio"], "nor into its own subgroup")

    XCTAssertTrue(config.makeGroup(title: "Emulators", with: DockItem(kind: .app, bundleID: "mesen")))
    XCTAssertEqual(config.pinned[0].items?.map(\.key), ["group:Emulators", "group:Tools"],
                   "grouping a member makes a subgroup in its place")

    config.setHidden("z3dk-app", true)
    XCTAssertEqual(config.groups.first { $0.key == "group:Tools" }?.items?.last?.hidden, true)
    let again = try DockConfigFile.decode(DockConfigFile.encode(config))
    XCTAssertEqual(again, config)
    config.setHidden("z3dk-app", false)
    XCTAssertNil(config.groups.first { $0.key == "group:Tools" }?.items?.last?.hidden)

    config.takeOut("z3dk-app", fromGroup: "group:Tools")
    XCTAssertEqual(config.pinned[0].items?.map(\.key), ["group:Emulators", "group:Tools", "z3dk-app"],
                   "taking out of a subgroup lands in its parent")
    config.ungroup("group:Emulators")
    XCTAssertEqual(config.pinned[0].items?.map(\.key), ["mesen", "group:Tools", "z3dk-app"])
    config.remove(key: "group:Tools")
    XCTAssertEqual(config.pinned[0].items?.map(\.key), ["mesen", "z3dk-app"])
  }

  func testGroupTilesReachMembersAtAnyDepth() {
    func tile(_ item: DockItem, pid: pid_t? = nil, children: [DockTile] = []) -> DockTile {
      DockTile(id: item.key, item: item, url: nil, section: .pinned, pid: pid, isActive: false, isHidden: false,
               children: children)
    }
    var hidden = DockItem(kind: .app, bundleID: "logic")
    hidden.hidden = true
    let tools = tile(DockItem(kind: .group, title: "Tools"), children: [tile(hidden, pid: 42)])
    let group = tile(DockItem(kind: .group, title: "Studio"),
                     children: [tile(DockItem(kind: .app, bundleID: "spotify")), tools])
    XCTAssertEqual(group.descendants.map(\.id), ["spotify", "group:Tools", "logic"])
    XCTAssertEqual(tools.visibleChildren, [])
    XCTAssertEqual(group.visibleChildren.map(\.id), ["spotify", "group:Tools"])
    XCTAssertTrue(group.isRunning, "a running app two levels down counts")
    XCTAssertTrue(group.contains(app: "logic"))
    XCTAssertFalse(group.contains(app: "music"))
  }

  func testDroppedWebLinksBecomeURLTiles() {
    let link = DockItem(droppedURL: URL(string: "https://github.com/scawful/barista")!)
    XCTAssertEqual(link.kind, .url)
    XCTAssertEqual(link.title, "github.com")
    XCTAssertEqual(DockItem(droppedURL: URL(fileURLWithPath: "/Applications/Safari.app")).kind, .app)
  }

  func testFoldersAndFilesWearingAnAppIconGetAKindMark() {
    func item(_ kind: DockItem.Kind, icon: String?) -> DockItem {
      var item = DockItem(kind: kind, path: "/tmp/x")
      item.icon = icon
      return item
    }
    XCTAssertEqual(item(.folder, icon: "/Applications/yaze.app").borrowedIconBadge, "folder.fill")
    XCTAssertEqual(item(.file, icon: "/Applications/yaze.app").borrowedIconBadge, "doc.fill")
    XCTAssertNil(item(.folder, icon: "sf:folder").borrowedIconBadge, "symbols already read as icons")
    XCTAssertNil(item(.folder, icon: nil).borrowedIconBadge)
    XCTAssertNil(item(.app, icon: "/Applications/yaze.app").borrowedIconBadge)
  }

  func testAgentFeedIgnoresStaleAndEmptyCounts() {
    let now = Date(timeIntervalSince1970: 10_000)
    let fresh = #"""
    {"updated": 9900, "needs": {"com.openai.codex": 1, "com.anthropic.claudefordesktop": 0},
     "sessions": [
       {"id": "codex:a", "app": "com.openai.codex", "title": "Oracle", "detail": "now", "working": false,
        "needs": "Which ROM should I test?",
        "color": "0xffa6e3a1", "focus": "agent_sessions.py focus app:com.openai.codex"},
       {"id": "codex:b", "app": "com.openai.codex", "title": "Docs", "detail": "now", "working": true},
       {"id": "gemini:1", "app": "", "title": "gemini 1"}
     ],
     "usage": {"com.openai.codex": "88% wk"}}
    """#
    let snapshot = AgentFeed.decode(Data(fresh.utf8), now: now)
    XCTAssertEqual(snapshot.needs, ["com.openai.codex": 1])
    XCTAssertEqual(snapshot.sessions.map(\.id), ["codex:a", "codex:b"], "sessions without an app have no tile")
    XCTAssertEqual(snapshot.sessions.map(\.needs), ["Which ROM should I test?", ""])
    XCTAssertEqual(snapshot.sessions.last?.working, true)
    XCTAssertEqual(snapshot.usage, ["com.openai.codex": "88% wk"])
    let stale = #"{"updated": 1000, "needs": {"com.openai.codex": 2}}"#
    XCTAssertEqual(AgentFeed.decode(Data(stale.utf8), now: now), AgentSnapshot())
    XCTAssertEqual(AgentFeed.decode(Data("not json".utf8), now: now), AgentSnapshot())
  }

  func testAgentAttentionMarksSessionsThatStopWorking() {
    func session(_ id: String, app: String = "codex", working: Bool, needs: String = "") -> AgentSession {
      AgentSession(id: id, app: app, title: id, detail: "", working: working, needs: needs, color: nil, focus: "")
    }
    var attention = AgentAttention()
    attention.update([session("q", working: true)], frontmost: nil)
    attention.update([session("q", working: false, needs: "Approve the plan?")], frontmost: nil)
    XCTAssertTrue(attention.finished.isEmpty, "a session that stopped to ask needs you; it did not finish")
    attention.update([session("a", working: false)], frontmost: nil)
    XCTAssertTrue(attention.finished.isEmpty, "a session first seen idle did not just finish")

    attention.update([session("a", working: true), session("b", app: "claude", working: true)], frontmost: nil)
    attention.update([session("a", working: false), session("b", app: "claude", working: false)], frontmost: "claude")
    XCTAssertEqual(attention.finished, ["a": "codex"], "the frontmost app's sessions are already in view")
    XCTAssertEqual(attention.apps, ["codex"])

    attention.update([session("a", working: true)], frontmost: nil)
    XCTAssertTrue(attention.finished.isEmpty, "working again clears it")
    attention.update([session("a", working: false)], frontmost: nil)
    attention.clear(app: "codex")
    XCTAssertTrue(attention.finished.isEmpty)
    attention.update([session("a", working: true)], frontmost: nil)
    attention.update([], frontmost: nil)
    XCTAssertTrue(attention.finished.isEmpty, "a closed session needs no look")
  }

  func testNewItemFieldsRoundTrip() throws {
    let json = #"""
    {"settings": {"shelf_days": 0, "expand_active_group": false},
     "pinned": [
      {"kind": "group", "title": "Oracle", "spaces": ["4", "rom"], "expand": false,
       "info_command": "oracle-status", "items": [
        {"kind": "action", "title": "Build", "command": "make", "notify": true, "badge_command": "echo 3"},
        {"kind": "action", "title": "Shell", "command": "z3dk paths", "terminal": true,
         "menu": [
          {"kind": "action", "title": "Verify", "command": "verify", "notify": true},
          {"kind": "group", "title": "Sessions", "items": [
            {"kind": "action", "title": "Maku", "command": "session maku"},
            {"kind": "action", "title": "D6", "command": "session d6"}
          ]}
         ]}
      ]}
     ],
     "others": [{"kind": "folder", "path": "~/src", "sort": "name"}, {"kind": "shelf"}]}
    """#
    let config = try DockConfigFile.decode(Data(json.utf8))
    XCTAssertEqual(config.settings.shelfDays, 0.1, "shelf_days is clamped")
    XCTAssertFalse(config.settings.expandActiveGroup)
    XCTAssertEqual(config.pinned.first?.spaces, ["4", "rom"])
    XCTAssertEqual(config.pinned.first?.expand, false)
    XCTAssertEqual(config.pinned.first?.items?.first?.badgeCommand, "echo 3")
    XCTAssertEqual(config.pinned.first?.items?.first?.notify, true)
    XCTAssertEqual(config.pinned.first?.infoCommand, "oracle-status")
    XCTAssertNil(config.pinned.first?.items?.first?.terminal)
    XCTAssertEqual(config.pinned.first?.items?.last?.terminal, true)
    let menu = config.pinned.first?.items?.last?.menu ?? []
    XCTAssertEqual(DockStore.menuActions(menu).map(\.title), ["Verify", "Maku", "D6"],
                   "submenus flatten so the tile's ring covers every entry")
    XCTAssertEqual(menu.first?.notify, true)
    XCTAssertEqual(config.others.map(\.key), ["folder:\(NSHomeDirectory())/src", "shelf"])
    XCTAssertEqual(config.others.first?.sort, .name)
    let again = try DockConfigFile.decode(DockConfigFile.encode(config))
    XCTAssertEqual(again, config)
  }

  func testBadgeTextTakesTheFirstLine() {
    XCTAssertEqual(ActionRunner.badgeText("\n  12 \nmore"), "12")
    XCTAssertNil(ActionRunner.badgeText("0\n"))
    XCTAssertNil(ActionRunner.badgeText("   \n"))
    XCTAssertNil(ActionRunner.badgeText(nil))
    XCTAssertEqual(ActionRunner.badgeText("a very long badge"), "a very l")
    XCTAssertEqual(ActionRunner.slug("action:Build ROM"), "Build-ROM")
    XCTAssertEqual(ActionRunner.slug("ca.mesen.oos/Maku (3 crystals)"), "ca-mesen-oos-Maku-3-crystals")
    XCTAssertEqual(ActionRunner.slug(String(repeating: "a b ", count: 60)).count, 80)
  }

  func testInfoRowsDecodeFromARowsObject() {
    let rows = InfoRow.decode(#"""
    {"rows": [
      {"title": "ROM 169", "detail": "missing", "tone": "warn", "open": "~/Roms", "action": "Build ROM"},
      {"title": "Prune", "run": "prune"},
      {"title": "master"},
      {"title": ""}
    ]}
    """#)
    XCTAssertEqual(rows.map(\.title), ["ROM 169", "Prune", "master"], "rows without a title are dropped")
    XCTAssertEqual(rows.first?.tone, .warn)
    XCTAssertEqual(rows.first?.open, "~/Roms")
    XCTAssertEqual(rows.first?.action, "Build ROM")
    XCTAssertEqual(rows.map(\.isClickable), [true, true, false])
    XCTAssertEqual(rows[1].run, "prune")
    XCTAssertNil(rows.last?.tone)
    XCTAssertEqual(InfoRow.decode("not json"), [])
    XCTAssertEqual(InfoRow.decode(#"{"rows": [{"title": "x", "tone": "loud"}, {"detail": "y"}]}"#),
                   [InfoRow(title: "x")], "an unknown tone reads as none; a missing title drops the row")
    XCTAssertEqual(InfoRow.decode(nil), [])
  }

  func testShelfPrunesOldAndMissingEntriesNewestFirst() {
    let now = Date(timeIntervalSince1970: 100_000)
    let entries = [
      Shelf.Entry(path: "/old", added: now.addingTimeInterval(-90_000)),
      Shelf.Entry(path: "/gone", added: now.addingTimeInterval(-10)),
      Shelf.Entry(path: "/a", added: now.addingTimeInterval(-500)),
      Shelf.Entry(path: "/b", added: now.addingTimeInterval(-5)),
    ]
    let kept = Shelf.pruned(entries, now: now, maxAge: 86_400) { $0 != "/gone" }
    XCTAssertEqual(kept.map(\.path), ["/b", "/a"])
  }

  func testYabaiSpacesMatchByIndexOrLabel() {
    let space = YabaiSpace(index: 4, label: "rom", display: 1, hasFocus: true)
    XCTAssertTrue(space.matches(["4"]))
    XCTAssertTrue(space.matches(["rom"]))
    XCTAssertFalse(space.matches(["2", ""]))
    XCTAssertFalse(YabaiSpace(index: 2, label: "", display: 1, hasFocus: false).matches([""]))
  }

  func testBaristaColorsParse() {
    let color = DockTheme.color("0xC021162F").map(NSColor.init)
    XCTAssertEqual(Double(color?.alphaComponent ?? 0), 192.0 / 255, accuracy: 0.001)
    XCTAssertEqual(Double(color?.redComponent ?? 0), 0x21 / 255.0, accuracy: 0.001)
    XCTAssertNil(DockTheme.color("purple"))
    XCTAssertNil(DockTheme.color(nil))
  }
}

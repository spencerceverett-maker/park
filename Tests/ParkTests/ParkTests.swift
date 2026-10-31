import CoreGraphics
import Foundation
import Testing
@testable import Park

@Suite struct Naming {
    private func window(_ content: ParkedWindow.Content, app: String = "App", bundle: String = "com.example.app") -> ParkedWindow {
        ParkedWindow(bundleID: bundle, appName: app, content: content)
    }

    @Test func prefersTheActiveFigmaFile() {
        let windows = [
            window(.browser(tabs: [BrowserTab(url: "https://a.com", title: "Docs")], activeIndex: 0, incognito: false)),
            window(.figma(files: [FigmaFile(url: "figma://file/a", title: "One"), FigmaFile(url: "figma://file/b", title: "Two")], activeIndex: 1)),
        ]
        #expect(Engine.name(for: windows) == "Two")
    }

    @Test func usesTheProjectFolderOverBrowserTitles() {
        let windows = [
            window(.browser(tabs: [BrowserTab(url: "https://a.com", title: "Docs")], activeIndex: 0, incognito: false)),
            window(.terminal(tabs: [TerminalTab(title: nil, layout: .pane(directory: "/Users/x/Developer/api-server", command: nil, focused: true))], activeIndex: 0)),
        ]
        #expect(Engine.name(for: windows) == "api-server")
    }

    @Test func ignoresTheHomeFolder() {
        let windows = [
            window(.terminal(tabs: [TerminalTab(title: nil, layout: .pane(directory: NSHomeDirectory(), command: nil, focused: true))], activeIndex: 0)),
            window(.browser(tabs: [BrowserTab(url: "https://a.com", title: "Inbox (3) - me@example.com - Gmail")], activeIndex: 0, incognito: false)),
        ]
        #expect(Engine.name(for: windows) == "Inbox (3)")
    }

    @Test func fallsBackToAppNames() {
        let windows = [window(.app, app: "Slack"), window(.app, app: "Notion"), window(.app, app: "Slack")]
        #expect(Engine.name(for: windows) == "Slack and Notion")
    }

    @Test func shortensPageTitles() {
        #expect(Engine.shortTitle("Pricing | Acme") == "Pricing")
        #expect(Engine.shortTitle("A — B – C") == "A")
        #expect(Engine.shortTitle("Plain") == "Plain")
    }

    @Test func joinsNamesLikePeopleDo() {
        #expect(NameList.string([]) == "")
        #expect(NameList.string(["Chrome"]) == "Chrome")
        #expect(NameList.string(["Chrome", "Figma"]) == "Chrome and Figma")
        #expect(NameList.string(["Chrome", "Figma", "Warp"]) == "Chrome, Figma and Warp")
        #expect(NameList.string(["A", "B", "C", "D", "E"]) == "A, B and 3 more")
    }
}

@Suite struct Persistence {
    private let sample = Spot(name: "Work", createdAt: Date(timeIntervalSince1970: 1_800_000_000), windows: [
        ParkedWindow(bundleID: "com.google.Chrome", appName: "Chrome", title: "t", frame: CGRect(x: 1, y: 2, width: 3, height: 4),
                     content: .browser(tabs: [BrowserTab(url: "https://a.com/x?y=1", title: "A")], activeIndex: 0, incognito: false)),
        ParkedWindow(bundleID: "dev.warp.Warp-Stable", appName: "Warp",
                     content: .terminal(tabs: [TerminalTab(title: "srv", layout: .split(horizontal: true, panes: [
                        .pane(directory: "/a", command: "npm run dev", focused: false),
                        .pane(directory: "/b", command: nil, focused: true),
                     ]))], activeIndex: 0)),
        ParkedWindow(bundleID: "com.figma.Desktop", appName: "Figma", content: .figma(files: [FigmaFile(url: "figma://file/k", title: "F")], activeIndex: 0)),
        ParkedWindow(bundleID: "com.apple.finder", appName: "Finder", content: .folder(path: "/tmp")),
        ParkedWindow(bundleID: "com.apple.Preview", appName: "Preview", content: .document(path: "/tmp/a.pdf")),
        ParkedWindow(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", content: .app),
    ])

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("park-test-\(UUID()).json")
    }

    @Test @MainActor func roundTripsEveryKindOfWindow() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SpotStore(fileURL: url)
        store.insert(sample)
        let reloaded = SpotStore(fileURL: url)
        #expect(reloaded.spots == [sample])
    }

    @Test @MainActor func keepsReadableSpotsWhenOneIsCorrupt() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SpotStore(fileURL: url)
        store.insert(sample)
        // Append an entry from some hypothetical future version.
        var json = try #require(String(data: Data(contentsOf: url), encoding: .utf8))
        json = json.replacingOccurrences(of: "\n]", with: ",\n{\"id\": \"not-a-uuid\", \"future\": true}\n]")
        try json.write(to: url, atomically: true, encoding: .utf8)

        let reloaded = SpotStore(fileURL: url)
        #expect(reloaded.spots == [sample])
        let backups = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(url.deletingPathExtension().lastPathComponent + ".unreadable-") }
        #expect(!backups.isEmpty)
        backups.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    @Test @MainActor func renameIgnoresBlankNames() {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SpotStore(fileURL: url)
        store.insert(sample)
        store.rename(sample.id, to: "   ")
        #expect(store.spots.first?.name == "Work")
        store.rename(sample.id, to: "  Launch  ")
        #expect(store.spots.first?.name == "Launch")
    }
}

@Suite struct AppSpecifics {
    @Test func figmaLinksKeepThePageButDropSessionTokens() {
        let tab = FigmaAdapter.Tab(path: "/file/ABC123", title: "My File", params: "?node-id=1-2&p=f&viewport=1%2C2%2C0.5&t=secret&fuid=42")
        let link = FigmaAdapter.deepLink(tab)
        #expect(link.hasPrefix("figma://file/ABC123/My-File?"))
        #expect(link.contains("node-id=1-2"))
        #expect(link.contains("viewport=1%2C2%2C0.5"))
        #expect(!link.contains("t=secret"))
        #expect(!link.contains("fuid"))
    }

    @Test func warpLaunchConfigIsValidAndUnescaped() throws {
        let tabs = [TerminalTab(title: "a \"quoted\" title", layout: .split(horizontal: false, panes: [
            .pane(directory: "/Users/me/My Project", command: "rm -rf /", focused: true),
            .pane(directory: "/tmp", command: nil, focused: false),
        ]))]
        let yaml = try WarpAdapter.launchConfig(name: "park-x", tabs: tabs, activeIndex: 5)
        #expect(!yaml.contains("\\/"), "Warp ignores configs with escaped slashes")
        #expect(!yaml.contains("rm -rf"), "commands must never be re-run")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(yaml.utf8)) as? [String: Any])
        let window = try #require((object["windows"] as? [[String: Any]])?.first)
        #expect(window["active_tab_index"] as? Int == 0, "clamped to the last tab")
        let tab = try #require((window["tabs"] as? [[String: Any]])?.first)
        #expect(tab["title"] as? String == "a \"quoted\" title")
        let layout = try #require(tab["layout"] as? [String: Any])
        #expect(layout["split_direction"] as? String == "vertical")
        #expect(((layout["panes"] as? [[String: Any]])?.first?["cwd"]) as? String == "/Users/me/My Project")
    }

    @Test func commandsReadNaturally() {
        #expect(Processes.displayCommand(["node", "/usr/local/bin/claude", "--resume"]) == "claude --resume")
        #expect(Processes.displayCommand(["/opt/homebrew/bin/npm", "run", "dev"]) == "npm run dev")
        #expect(Processes.displayCommand(["python3"]) == "python3")
    }

    @Test func savedCommandsNeverIncludeSecrets() {
        #expect(Processes.safeCommandName(["/opt/homebrew/bin/npm", "run", "dev"]) == "npm run dev")
        #expect(Processes.safeCommandName(["mysql", "-uroot", "-pHunter2"]) == "mysql")
        #expect(Processes.safeCommandName(["curl", "-H", "Authorization: Bearer abc"]) == "curl")
        #expect(Processes.safeCommandName(["psql", "postgres://user:pass@host/db"]) == "psql")
        #expect(Processes.safeCommandName(["node", "/usr/local/bin/claude", "--resume", "abc"]) == "claude")
    }

    @Test func onlyOrdinaryTabURLsReopen() {
        #expect(Engine.safeTabURL("https://example.com/a?b=1") == "https://example.com/a?b=1")
        #expect(Engine.safeTabURL("chrome://settings") == "chrome://settings")
        #expect(Engine.safeTabURL("javascript:alert(1)") == "about:blank")
        #expect(Engine.safeTabURL("not a url") == "about:blank")
    }

    @Test func offscreenFramesMoveOntoTheMainDisplay() {
        let main = CGDisplayBounds(CGMainDisplayID())
        let onScreen = CGRect(x: main.minX + 50, y: main.minY + 60, width: 400, height: 300)
        #expect(Screens.fit(onScreen) == onScreen)
        let farAway = CGRect(x: main.maxX + 10_000, y: 0, width: 1200, height: 800)
        let fitted = Screens.fit(farAway)
        #expect(main.contains(fitted))
    }

    @Test func framesMatchWithinTolerance() {
        let a = CGRect(x: 10, y: 10, width: 100, height: 100)
        #expect(a.isClose(to: CGRect(x: 11.5, y: 9, width: 101, height: 99)))
        #expect(!a.isClose(to: CGRect(x: 14, y: 10, width: 100, height: 100)))
    }

    @Test func relativeTimesAreShort() {
        let now = Date()
        #expect(RelativeTime.string(for: now.addingTimeInterval(-20), now: now) == "Just now")
        #expect(RelativeTime.string(for: now.addingTimeInterval(-5 * 60), now: now) == "5m ago")
    }
}

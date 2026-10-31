// Window layer: which windows are on the current Space, and how to close, match and restore them.
//
// Verified on macOS 26.6.2, Apple Silicon.
//
// Permissions used:
//   - Accessibility (AXIsProcessTrusted)          -> AX window list, AX close button, AX frame, AXDocument
//   - Automation / Apple Events per target app    -> Chrome and Finder scripting
//       Info.plist: NSAppleEventsUsageDescription
//       Hardened runtime entitlement: com.apple.security.automation.apple-events = true
//   - Screen Recording is NOT required: we never rely on kCGWindowName (nil without it since 10.15).
//
// Private APIs used (all long-lived and used by AltTab / yabai / Hammerspoon / Rectangle; not App Store-safe):
//   - _AXUIElementGetWindow            (HIServices)  AXUIElement -> CGWindowID
//   - CGSMainConnectionID, CGSCopySpacesForWindows, CGSCopyManagedDisplaySpaces, CGSGetActiveSpace
//   - SLSWindowIsOrderedIn             (SkyLight; link with -F /System/Library/PrivateFrameworks -framework SkyLight)
// Each is wrapped so it can be swapped for a public-only fallback (see `CurrentSpace.publicOnlyWindowIDs()`).

import AppKit
import ApplicationServices
import Carbon // AEDeterminePermissionToAutomateTarget, kAE* constants

// MARK: - Private API shims ---------------------------------------------------------------

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

/// Undocumented system calls, looked up at runtime rather than linked. If a future macOS drops one,
/// Park keeps working in a conservative mode (see `Private.hasSpaces`) instead of failing to launch.
enum Private {
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(skyLight ?? UnsafeMutableRawPointer(bitPattern: -2), name) ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
        else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias MainConnection = @convention(c) () -> CGSConnectionID
    typealias ActiveSpace = @convention(c) (CGSConnectionID) -> CGSSpaceID
    typealias SpacesForWindows = @convention(c) (CGSConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias ManagedDisplaySpaces = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
    typealias IsOrderedIn = @convention(c) (CGSConnectionID, CGWindowID, UnsafeMutablePointer<Bool>) -> Int32

    static let getWindow = symbol("_AXUIElementGetWindow", as: GetWindow.self)
    static let mainConnection = symbol("CGSMainConnectionID", as: MainConnection.self)
    static let activeSpace = symbol("CGSGetActiveSpace", as: ActiveSpace.self)
    /// mask 0x7 = all spaces (current | other | user). Returns [] for windows that are on no Space
    /// (ordered-out helper windows, windows that were just closed, offscreen 500x500 Electron stubs...).
    static let spacesForWindows = symbol("CGSCopySpacesForWindows", as: SpacesForWindows.self)
    static let managedDisplaySpaces = symbol("CGSCopyManagedDisplaySpaces", as: ManagedDisplaySpaces.self)
    /// true for windows that are ordered in on *some* Space (including other Spaces);
    /// false for minimized windows and for hidden/ordered-out windows (e.g. Electron "close to tray").
    static let isOrderedIn = symbol("SLSWindowIsOrderedIn", as: IsOrderedIn.self)

    /// Whether Park can tell which desktop each window is on. Without it, Park never quits apps.
    static var hasSpaces: Bool { mainConnection != nil && activeSpace != nil && spacesForWindows != nil }
}

private func _AXUIElementGetWindow(_ el: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError {
    Private.getWindow?(el, wid) ?? .failure
}
private func CGSMainConnectionID() -> CGSConnectionID { Private.mainConnection?() ?? 0 }
private func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID { Private.activeSpace?(cid) ?? 0 }
private func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ wids: CFArray) -> Unmanaged<CFArray>? {
    Private.spacesForWindows?(cid, mask, wids)
}
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>? { Private.managedDisplaySpaces?(cid) }
private func SLSWindowIsOrderedIn(_ cid: CGSConnectionID, _ wid: CGWindowID, _ out: UnsafeMutablePointer<Bool>) -> Int32 {
    Private.isOrderedIn?(cid, wid, out) ?? -1
}

// MARK: - Permissions ----------------------------------------------------------------------

enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() } // informational only

    enum AutomationStatus: String { case granted, denied, notDetermined, targetNotRunning, unknown }

    /// Checks Apple Events permission for `bundleID` WITHOUT prompting (askUserIfNeeded = false).
    /// Call again with `prompt: true` from a user-initiated action to trigger the system prompt.
    /// Target app must be running, otherwise procNotFound (-600).
    static func automation(for bundleID: String, prompt: Bool = false) -> AutomationStatus {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        guard AECreateDesc(DescType(typeApplicationBundleID), bytes, bytes.count, &target) == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }
        let st = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), prompt)
        switch st {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied              // -1743
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined // -1744
        case OSStatus(procNotFound): return .targetNotRunning           // -600
        default: return .unknown
        }
    }
}

// MARK: - Spaces ---------------------------------------------------------------------------

enum Spaces {
    private static let cid = CGSMainConnectionID()

    /// The Space the user is looking at on the active display.
    static var activeSpace: CGSSpaceID { CGSGetActiveSpace(cid) }

    /// Current Space of every display (differs from `activeSpace` only with multiple displays
    /// and "Displays have separate Spaces" on). Space type 0 = desktop, 4 = fullscreen app Space.
    static func currentSpacesAllDisplays() -> [(id: CGSSpaceID, type: Int)] {
        guard let displays = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return displays.compactMap { d in
            guard let cur = d["Current Space"] as? [String: Any],
                  let id = (cur["ManagedSpaceID"] as? NSNumber)?.uint64Value else { return nil }
            return (id, (cur["type"] as? NSNumber)?.intValue ?? 0)
        }
    }

    static func spaces(for wid: CGWindowID) -> [CGSSpaceID] {
        let arr = CGSCopySpacesForWindows(cid, 0x7, [NSNumber(value: wid)] as CFArray)?.takeRetainedValue()
        return (arr as? [NSNumber])?.map(\.uint64Value) ?? []
    }

    static func isOrderedIn(_ wid: CGWindowID) -> Bool {
        var b = false
        return SLSWindowIsOrderedIn(cid, wid, &b) == 0 && b
    }
}

// MARK: - Window model + enumeration ------------------------------------------------------

/// One user-facing window on the current Space. Frame is in global "top-left origin" coordinates,
/// the same space used by CGWindowList, AX (kAXPosition/kAXSize) and Chrome/Finder AppleScript `bounds`.
struct ParkableWindow: CustomStringConvertible {
    let windowID: CGWindowID
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let frame: CGRect
    let title: String?          // from AX (works without Screen Recording)
    let isMinimized: Bool
    let isFullScreen: Bool
    let documentURL: URL?       // kAXDocumentAttribute when the app provides it
    let ax: AXUIElement?        // nil if AX is not trusted

    var description: String {
        "\(appName)#\(windowID) \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
            + (isMinimized ? " [min]" : "") + (isFullScreen ? " [fs]" : "")
            + " \"\(title ?? "")\"" + (documentURL.map { " doc=\($0.absoluteString)" } ?? "")
    }
}

enum AX {
    static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }
    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    static func frame(_ el: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?, sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success,
              let pv, let sv else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }
    static func setFrame(_ el: AXUIElement, _ r: CGRect) {
        // size -> position -> size: avoids the window being clamped when moving to a smaller area.
        var s = r.size, p = r.origin
        if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv) }
        if let pv = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, pv) }
        if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, sv) }
    }
    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(el, &wid) == .success && wid != 0 ? wid : nil
    }
    /// AX windows of an app. VERIFIED: on macOS 26 kAXWindowsAttribute only returns windows on the
    /// CURRENT Space (+ minimized windows of the current Space); windows on other Spaces are absent.
    /// Finder also returns its desktop window (no CGWindowID, _AXUIElementGetWindow fails) -> skipped.
    static func windows(pid: pid_t) -> [(AXUIElement, CGWindowID)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 3.0) // a hung app must not hang the whole park operation
        let wins: [AXUIElement] = attr(app, kAXWindowsAttribute) ?? []
        return wins.compactMap { w in windowID(w).map { (w, $0) } }
    }
}

enum CurrentSpace {
    /// Minimum size for a "real" window; filters 2x2 Loom-style overlays, 1px trackers, etc.
    static let minSide: CGFloat = 60

    /// All parkable windows on the Space the user is looking at.
    ///
    /// Algorithm (verified):
    ///  1. CGWindowListCopyWindowInfo(.optionOnScreenOnly + .excludeDesktopElements): windows visible on
    ///     the current Space(s), front-to-back. Excludes minimized windows and other Spaces' windows.
    ///     pid / bounds / layer / alpha / window number are available WITHOUT Screen Recording.
    ///  2. Keep layer 0, alpha > 0, size >= minSide, owner is a .regular app (drops menubar extras,
    ///     Dock, Control Center, Window Server, AutoFill helpers, etc.).
    ///  3. Drop "sticky" windows assigned to every Space (CGSCopySpacesForWindows returns >1 Space) —
    ///     parking them would remove them from all desktops.
    ///  4. Add minimized windows: AX windows with kAXMinimized == true whose CGS Space list contains
    ///     the current Space (verified: a minimized window keeps its Space id, is not onscreen and
    ///     SLSWindowIsOrderedIn == false).
    ///  5. Attach AX element/title/document/fullscreen via _AXUIElementGetWindow.
    /// `allDisplays: false` restricts to the active display's Space (what "the desktop I'm looking at"
    /// usually means on a multi-monitor setup).
    static func windows(allDisplays: Bool = false, includeMinimized: Bool = true) -> [ParkableWindow] {
        let current: Set<CGSSpaceID> = allDisplays
            ? Set(Spaces.currentSpacesAllDisplays().map(\.id)) : [Spaces.activeSpace]
        let myPID = ProcessInfo.processInfo.processIdentifier
        let regularApps = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != myPID }
            .map { ($0.processIdentifier, $0) })

        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        var onscreen: [(wid: CGWindowID, pid: pid_t, frame: CGRect)] = []
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, regularApps[pid] != nil,
                  let wid = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bd),
                  frame.width >= minSide, frame.height >= minSide else { continue }
            if Private.hasSpaces {
                let sp = Set(Spaces.spaces(for: wid))
                guard sp.count == 1, !sp.isDisjoint(with: current) else { continue } // sticky or other display
            }
            onscreen.append((wid, pid, frame))
        }

        var result: [ParkableWindow] = []
        var seen = Set<CGWindowID>()
        let axTrusted = AXIsProcessTrusted()
        let pids = Set(onscreen.map(\.pid)).union(includeMinimized && axTrusted ? Set(regularApps.keys) : [])
        var axByWID: [CGWindowID: AXUIElement] = [:], pidByWID: [CGWindowID: pid_t] = [:]
        if axTrusted { for pid in pids { for (el, wid) in AX.windows(pid: pid) { axByWID[wid] = el; pidByWID[wid] = pid } } }

        func make(_ wid: CGWindowID, _ pid: pid_t, _ frame: CGRect, minimized: Bool) -> ParkableWindow {
            let app = regularApps[pid]
            let el = axByWID[wid]
            let doc: String? = el.flatMap { AX.attr($0, kAXDocumentAttribute) }
            return ParkableWindow(windowID: wid, pid: pid, bundleID: app?.bundleIdentifier,
                                  appName: app?.localizedName ?? "?", frame: frame,
                                  title: el.flatMap { AX.attr($0, kAXTitleAttribute) },
                                  isMinimized: minimized,
                                  isFullScreen: el.flatMap { AX.attr($0, "AXFullScreen") } ?? false,
                                  documentURL: doc.flatMap { URL(string: $0) }, ax: el)
        }
        for w in onscreen where seen.insert(w.wid).inserted {
            // Only keep standard windows when AX can tell us (drops sheets/panels/popovers).
            if let el = axByWID[w.wid], let sub: String = AX.attr(el, kAXSubroleAttribute),
               sub != (kAXStandardWindowSubrole as String) { continue }
            result.append(make(w.wid, w.pid, w.frame, minimized: false))
        }
        if includeMinimized && axTrusted && Private.hasSpaces {
            for (wid, el) in axByWID where !seen.contains(wid) {
                guard (AX.attr(el, kAXMinimizedAttribute) as Bool?) == true,
                      !Set(Spaces.spaces(for: wid)).isDisjoint(with: current),
                      let pid = pidByWID[wid],
                      let f = AX.frame(el) else { continue }
                seen.insert(wid)
                result.append(make(wid, pid, f, minimized: true))
            }
        }
        return result
    }

    /// Public-API-only fallback (no CGS/SkyLight): onscreen CG windows ∪ AX windows (AX only lists the
    /// current Space). Cannot drop sticky windows and cannot tell an Electron hidden window from a
    /// minimized one, but needs no private symbols.
    static func publicOnlyWindowIDs() -> Set<CGWindowID> {
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        var ids = Set(info.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            for (el, wid) in AX.windows(pid: app.processIdentifier)
            where (AX.attr(el, kAXMinimizedAttribute) as Bool?) == true { ids.insert(wid) }
        }
        return ids
    }
}

// MARK: - Quit vs close decision ---------------------------------------------------------

enum QuitPolicy {
    /// Windows of `pid` that live on Spaces OTHER than `current` (incl. fullscreen Spaces and windows
    /// on other displays). Conservative on purpose: any layer-0 window >= minSide that is assigned to a
    /// non-current Space counts, even if it's an ordered-out (hidden) window — a false positive only
    /// means we close windows instead of quitting, which is safe. Windows with no Space at all
    /// (closed/stale/offscreen stubs) are ignored — verified those return [] from CGSCopySpacesForWindows.
    static func windowsElsewhere(pid: pid_t, current: Set<CGSSpaceID> = [Spaces.activeSpace]) -> [CGWindowID] {
        // Without Space information, assume the app is in use elsewhere: closing beats wrongly quitting.
        guard Private.hasSpaces else { return [kCGNullWindowID] }
        let info = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        return info.compactMap { w -> CGWindowID? in
            guard (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let wid = (w[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let f = CGRect(dictionaryRepresentation: bd),
                  f.width >= CurrentSpace.minSide, f.height >= CurrentSpace.minSide else { return nil }
            let sp = Set(Spaces.spaces(for: wid))
            guard !sp.isEmpty else { return nil }
            // Sticky (all-Spaces) windows also count as "elsewhere".
            return (sp.isDisjoint(with: current) || sp.count > 1) ? wid : nil
        }
    }

    enum Action { case quitApp, closeWindowsOnly }

    /// Apps we never quit even if all their windows are here (background value: music, messaging, mail,
    /// the user's terminal, ourselves). Tune per product decision.
    static let neverQuit: Set<String> = ["com.apple.finder", "com.spotify.client", "com.tinyspeck.slackmacgap",
                                         "com.apple.MobileSMS", "com.apple.mail"]

    static func action(for app: NSRunningApplication) -> Action {
        if let b = app.bundleIdentifier, neverQuit.contains(b) { return .closeWindowsOnly }
        return windowsElsewhere(pid: app.processIdentifier).isEmpty ? .quitApp : .closeWindowsOnly
    }
}

// MARK: - Generic AX close -----------------------------------------------------------------

enum AXClose {
    enum Result { case closed, stillOpen, noCloseButton, notTrusted }

    /// Presses the window's close button and waits for the CGWindowID to disappear.
    /// Pitfalls (see report): unsaved-document sheets keep the window open (-> .stillOpen);
    /// some apps hide instead of close (Electron "close to tray": window survives but is ordered out);
    /// minimized windows must be un-minimized first or AXPress is ignored by some apps;
    /// Finder tabs: the close button closes the whole window (all tabs).
    @discardableResult
    static func close(_ w: ParkableWindow, timeout: TimeInterval = 2) -> Result {
        guard AXIsProcessTrusted() else { return .notTrusted }
        guard let el = w.ax else { return .noCloseButton }
        if w.isMinimized { AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        guard let btn = AX.element(el, kAXCloseButtonAttribute) else { return .noCloseButton }
        AXUIElementPerformAction(btn, kAXPressAction as CFString)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !windowExists(w.windowID, pid: w.pid) { return .closed }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return windowExists(w.windowID, pid: w.pid) ? .stillOpen : .closed
    }

    /// A window is "gone" when it is no longer ordered in AND the app's AX window list no longer has it.
    /// VERIFIED pitfalls that rule out simpler checks:
    ///  - CGWindowList keeps closed windows for a while (Chrome) or indefinitely (Preview caches the
    ///    NSWindow): the window number stays in .optionAll.
    ///  - Preview's closed window even KEEPS its Space assignment (CGSCopySpacesForWindows == [space]),
    ///    so "spaces is empty" is not a valid closed test; SLSWindowIsOrderedIn == false is.
    ///  - Minimized windows are also not ordered in, hence the AX list check.
    static func windowExists(_ wid: CGWindowID, pid: pid_t? = nil) -> Bool {
        if Spaces.isOrderedIn(wid) { return true }
        guard let pid, AXIsProcessTrusted() else { return false }
        return AX.windows(pid: pid).contains { $0.1 == wid }
    }
}

// MARK: - AppleScript runner ---------------------------------------------------------------

enum AppleScript {
    struct Failure: Error, CustomStringConvertible { let description: String; init(info: NSDictionary) { description = "\(info)" } }

    /// Compiles `source` once and calls handler `name` with typed args — no string interpolation of
    /// user data (URLs, paths) into source code, so no quoting/injection issues.
    static func call(_ source: String, handler name: String, _ args: [NSAppleEventDescriptor]) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: withTimeout(source)) else { throw Failure(info: ["msg": "compile"]) }
        var err: NSDictionary?
        let params = NSAppleEventDescriptor.list()
        for (i, a) in args.enumerated() { params.insert(a, at: i + 1) }
        let ev = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite),
                                        eventID: AEEventID(kASSubroutineEvent),
                                        targetDescriptor: .currentProcess(),
                                        returnID: AEReturnID(kAutoGenerateReturnID),
                                        transactionID: AETransactionID(kAnyTransactionID))
        ev.setDescriptor(.init(string: name.lowercased()), forKeyword: AEKeyword(keyASSubroutineName))
        ev.setDescriptor(params, forKeyword: AEKeyword(keyDirectObject))
        let r = script.executeAppleEvent(ev, error: &err)
        if let err { throw Failure(info: err) }
        return r
    }
    /// Wraps every `tell` block in a 10-second timeout, so a frozen app can't stall Park for minutes.
    private static func withTimeout(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("on "), trimmed.hasSuffix(")") { return "\(line)\nwith timeout of 10 seconds" }
            if trimmed.hasPrefix("end "), !trimmed.hasPrefix("end tell"), !trimmed.hasPrefix("end if"),
               !trimmed.hasPrefix("end repeat"), !trimmed.hasPrefix("end try") { return "end timeout\n\(line)" }
            return String(line)
        }.joined(separator: "\n")
    }

    static func run(_ source: String) throws -> NSAppleEventDescriptor {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { throw Failure(info: err) }
        return r ?? .null()
    }
    static func list(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let l = NSAppleEventDescriptor.list()
        for (i, x) in items.enumerated() { l.insert(x, at: i + 1) }
        return l
    }
    static func ints(_ xs: [Int]) -> NSAppleEventDescriptor { list(xs.map { .init(int32: Int32($0)) }) }
    static func items(_ d: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        d.numberOfItems == 0 ? [] : (1...d.numberOfItems).compactMap { d.atIndex($0) }
    }
}

// MARK: - Chrome ---------------------------------------------------------------------------

struct ChromeTab: Codable, Equatable { var url: String; var title: String }
struct ChromeWindowSnapshot: Codable {
    var chromeWindowID: Int           // Chrome's scripting id (NOT a CGWindowID)
    var mode: String                  // "normal" | "incognito"
    var bounds: CGRect                // top-left global coords, same as CG/AX
    var activeTabIndex: Int           // 1-based
    var tabs: [ChromeTab]
    var givenName: String             // user-assigned window name ("Name Window…"), usually ""
    var minimized: Bool
    var title: String                 // = active tab title (AppleScript `name`)
}

/// Chromium browsers share Chrome's AppleScript dictionary, so one implementation covers them all.
/// Scripts are written against Chrome's bundle ID and retargeted by substituting a known, constant bundle ID.
enum Chrome {
    static let bundleID = "com.google.Chrome"
    static let family: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
    ]

    private static func retarget(_ source: String, _ bundleID: String) -> String {
        source.replacingOccurrences(of: "com.google.Chrome", with: bundleID)
    }

    // Returns ALL Chrome windows across all Spaces (AppleScript does not know about Spaces).
    // Tabs are fetched with bulk `URL of tabs` / `title of tabs` (one Apple Event each) for speed.
    private static let listSource = """
    on listWindows()
      set out to {}
      tell application id "com.google.Chrome"
        repeat with w in windows
          set b to bounds of w
          set end of out to {id of w, mode of w, b, active tab index of w, URL of tabs of w, title of tabs of w, given name of w, minimized of w, name of w}
        end repeat
      end tell
      return out
    end listWindows
    """

    static func listWindows(bundleID: String = bundleID) throws -> [ChromeWindowSnapshot] {
        let r = try AppleScript.call(retarget(listSource, bundleID), handler: "listWindows", [])
        return AppleScript.items(r).compactMap { w in
            let f = AppleScript.items(w)
            guard f.count == 9 else { return nil }
            let b = AppleScript.items(f[2]).map { Int($0.int32Value) }
            guard b.count == 4 else { return nil }
            let urls = AppleScript.items(f[4]).map { $0.stringValue ?? "" }
            let titles = AppleScript.items(f[5]).map { $0.stringValue ?? "" }
            return ChromeWindowSnapshot(
                chromeWindowID: Int(f[0].int32Value), mode: f[1].stringValue ?? "normal",
                bounds: CGRect(x: b[0], y: b[1], width: b[2] - b[0], height: b[3] - b[1]),
                activeTabIndex: Int(f[3].int32Value),
                tabs: zip(urls, titles).map { ChromeTab(url: $0, title: $1) },
                givenName: f[6].stringValue ?? "", minimized: f[7].booleanValue, title: f[8].stringValue ?? "")
        }
    }

    /// Match current-Space CG/AX Chrome windows to Chrome scripting windows.
    /// Keys, in order: bounds (±2pt) + minimized, then title (AX title == name or "name - Google Chrome"),
    /// then active-tab URL (AXDocument == URL of active tab — verified Chrome exposes AXDocument).
    /// Remaining ambiguity (e.g. two identical maximized windows on different Spaces with same tab) is
    /// resolved by temporarily setting a unique `given name`, which Chrome propagates to the NSWindow
    /// title (verified: AX title becomes "<token> - Google Chrome", CG name "<token>"), then restoring it.
    static func match(_ cgWindows: [ParkableWindow], _ chrome: [ChromeWindowSnapshot], bundleID: String = bundleID) throws -> [CGWindowID: ChromeWindowSnapshot] {
        var out: [CGWindowID: ChromeWindowSnapshot] = [:]
        var used = Set<Int>()
        var ambiguous: [(ParkableWindow, [ChromeWindowSnapshot])] = []
        func close(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
        }
        for w in cgWindows {
            var c = chrome.filter { close($0.bounds, w.frame) && $0.minimized == w.isMinimized }
            if c.count > 1, let t = w.title {
                let byTitle = c.filter { t == $0.title || t.hasPrefix($0.title + " - ") || (!$0.givenName.isEmpty && t.hasPrefix($0.givenName)) }
                if !byTitle.isEmpty { c = byTitle }
            }
            if c.count > 1, let doc = w.documentURL?.absoluteString {
                let byURL = c.filter { $0.tabs.indices.contains($0.activeTabIndex - 1) && $0.tabs[$0.activeTabIndex - 1].url == doc }
                if !byURL.isEmpty { c = byURL }
            }
            if c.count == 1 { out[w.windowID] = c[0]; used.insert(c[0].chromeWindowID) } else if c.count > 1 { ambiguous.append((w, c)) }
        }
        guard !ambiguous.isEmpty else { return out }
        // Tagging fallback.
        let candidates = Set(ambiguous.flatMap { $0.1.map(\.chromeWindowID) }).subtracting(used)
        let originals = Dictionary(uniqueKeysWithValues: chrome.filter { candidates.contains($0.chromeWindowID) }.map { ($0.chromeWindowID, $0.givenName) })
        let token = "parking-\(UUID().uuidString.prefix(8))-"
        // Restore names even if tagging fails partway, or windows would keep the temporary name.
        defer { for (id, name) in originals { try? setGivenName(id, name, bundleID: bundleID) } }
        for id in candidates { try setGivenName(id, token + String(id), bundleID: bundleID) }
        Thread.sleep(forTimeInterval: 0.15) // title propagation to AX
        for (w, _) in ambiguous {
            guard let el = w.ax, let t: String = AX.attr(el, kAXTitleAttribute), t.hasPrefix(token),
                  let id = Int(t.dropFirst(token.count).prefix { $0.isNumber }),
                  let snap = chrome.first(where: { $0.chromeWindowID == id }) else { continue }
            out[w.windowID] = snap
        }
        return out
    }

    static func setGivenName(_ chromeWindowID: Int, _ name: String, bundleID: String = bundleID) throws {
        _ = try AppleScript.call(retarget("""
        on setName(wid, n)
          tell application id "com.google.Chrome" to set given name of window id wid to n
        end setName
        """, bundleID), handler: "setName", [.init(int32: Int32(chromeWindowID)), .init(string: name)])
    }

    /// Closes exactly one Chrome window by its scripting id. Verified (incl. a minimized window).
    /// Verified: a 2-tab window closed with no confirmation prompt. The CGWindowID may linger briefly in CGWindowList with spaces == [].
    static func close(chromeWindowID: Int, bundleID: String = bundleID) throws {
        _ = try AppleScript.call(retarget("""
        on closeWin(wid)
          tell application id "com.google.Chrome" to close window id wid
        end closeWin
        """, bundleID), handler: "closeWin", [.init(int32: Int32(chromeWindowID))])
    }

    /// Recreates a window on the CURRENT Space (new windows always open on the active Space) with tabs in
    /// order, active tab, bounds, mode and given name. Returns the new Chrome scripting id.
    /// Caveats: all tabs load immediately (no lazy restore); tab groups, pinned state, history/back stack,
    /// scroll position and form state are lost; window opens in Chrome's last-used profile.
    @discardableResult
    static func restore(_ s: ChromeWindowSnapshot, bundleID: String = bundleID) throws -> Int {
        let src = """
        on restoreWin(urls, activeIdx, b, md, gname, mini)
          tell application id "com.google.Chrome"
            if md is "incognito" then
              set w to make new window with properties {mode:"incognito"}
            else
              set w to make new window
            end if
            set URL of active tab of w to item 1 of urls
            repeat with i from 2 to count of urls
              tell w to make new tab at end of tabs with properties {URL:item i of urls}
            end repeat
            set active tab index of w to activeIdx
            set bounds of w to b
            if gname is not "" then set given name of w to gname
            if mini then set minimized of w to true
            return id of w
          end tell
        end restoreWin
        """
        let urls = s.tabs.isEmpty ? ["chrome://newtab/"] : s.tabs.map(\.url)
        let b = [Int(s.bounds.minX), Int(s.bounds.minY), Int(s.bounds.maxX), Int(s.bounds.maxY)]
        let r = try AppleScript.call(retarget(src, bundleID), handler: "restoreWin", [
            AppleScript.list(urls.map { .init(string: $0) }),
            .init(int32: Int32(max(1, min(s.activeTabIndex, urls.count)))),
            AppleScript.ints(b), .init(string: s.mode), .init(string: s.givenName), .init(boolean: s.minimized),
        ])
        return Int(r.int32Value)
    }
}

// MARK: - Finder ---------------------------------------------------------------------------

struct FinderWindowSnapshot: Codable {
    var finderWindowID: Int
    var path: String?        // nil for non-file targets (Recents, AirDrop, Network, search results…)
    var bounds: CGRect
    var currentView: String  // "icon view" | "list view" | "column view" | "flow view" (gallery)
    var collapsed: Bool
    var name: String
}

/// Finder: AX gives NO path (verified: AXDocument nil, AXProxy title is just the volume name), so the
/// folder must come from AppleScript `target of Finder window`. Requires Automation → Finder.
/// NOT VERIFIED BY RUNNING: this terminal's Automation permission for Finder is denied (-1743).
enum Finder {
    static let bundleID = "com.apple.finder"

    static func listWindows() throws -> [FinderWindowSnapshot] {
        let r = try AppleScript.call("""
        on listWindows()
          set out to {}
          tell application id "com.apple.finder"
            repeat with w in Finder windows
              set p to ""
              try
                set p to POSIX path of (target of w as alias)
              end try
              set end of out to {id of w, p, bounds of w, (current view of w) as text, collapsed of w, name of w}
            end repeat
          end tell
          return out
        end listWindows
        """, handler: "listWindows", [])
        return AppleScript.items(r).compactMap { w in
            let f = AppleScript.items(w); guard f.count == 6 else { return nil }
            let b = AppleScript.items(f[2]).map { Int($0.int32Value) }
            guard b.count == 4 else { return nil }
            let p = f[1].stringValue ?? ""
            return FinderWindowSnapshot(finderWindowID: Int(f[0].int32Value), path: p.isEmpty ? nil : p,
                                        bounds: CGRect(x: b[0], y: b[1], width: b[2] - b[0], height: b[3] - b[1]),
                                        currentView: f[3].stringValue ?? "icon view", collapsed: f[4].booleanValue,
                                        name: f[5].stringValue ?? "")
        }
    }

    /// Match by Finder id == CGWindowID first (widely reported to be equal; unverified here), then bounds+name.
    static func match(_ w: ParkableWindow, _ finder: [FinderWindowSnapshot]) -> FinderWindowSnapshot? {
        if let s = finder.first(where: { $0.finderWindowID == Int(w.windowID) }) { return s }
        let c = finder.filter { $0.bounds.integral == w.frame.integral && $0.collapsed == w.isMinimized && $0.name == (w.title ?? $0.name) }
        return c.count == 1 ? c[0] : nil
    }

    static func close(finderWindowID: Int) throws {
        _ = try AppleScript.call("""
        on closeWin(wid)
          tell application id "com.apple.finder" to close window id wid
        end closeWin
        """, handler: "closeWin", [.init(int32: Int32(finderWindowID))])
    }

    @discardableResult
    static func restore(_ s: FinderWindowSnapshot) throws -> Int {
        guard let path = s.path else { return 0 }
        let b = [Int(s.bounds.minX), Int(s.bounds.minY), Int(s.bounds.maxX), Int(s.bounds.maxY)]
        let r = try AppleScript.call("""
        on restoreWin(p, b, v)
          tell application id "com.apple.finder"
            set w to make new Finder window to (POSIX file p as alias)
            set bounds of w to b
            try
              if v is "list view" then set current view of w to list view
              if v is "column view" then set current view of w to column view
              if v is "icon view" then set current view of w to icon view
              if v is "flow view" then set current view of w to flow view
            end try
            return id of w
          end tell
        end restoreWin
        """, handler: "restoreWin", [.init(string: path), AppleScript.ints(b), .init(string: s.currentView)])
        return Int(r.int32Value)
    }

    /// Permission-free fallback for restore only: `NSWorkspace.open(folderURL)` opens a Finder window
    /// on the current Space (verified with `open <dir>`), then position it via AX. Capture still needs
    /// AppleScript (or the user's Finder window title → ambiguous path).
    @discardableResult
    static func restoreWithoutAutomation(path: String, frame: CGRect) -> Bool {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
        let deadline = Date().addingTimeInterval(3)
        let name = (path as NSString).lastPathComponent
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else { continue }
            if let (el, _) = AX.windows(pid: pid).first(where: { (AX.attr($0.0, kAXTitleAttribute) as String?) == name }) {
                AX.setFrame(el, frame); return true
            }
        }
        return false
    }
}

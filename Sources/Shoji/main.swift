import Cocoa
import ServiceManagement
import SwiftUI
import GlassDockKit
import MissionViewKit
import ShelfTabsKit

// GlassDock・ShelfTabs・MissionView の機能を 1 つのアプリで動かす。メニューバーのアイコンも 1 つにまとめる
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    // 動いている機能。単体アプリが動いている間は nil にして、その機能を単体アプリに譲る
    private var glassDock: GlassDockFeature?
    private var shelfTabs: ShelfTabsFeature?
    private var missionView: MissionViewFeature?
    // 止めて動かし直すときも同じものを使う
    private lazy var glassDockFeature = GlassDockFeature()
    private lazy var shelfTabsFeature = ShelfTabsFeature()
    private lazy var missionViewFeature = MissionViewFeature()
    private var optionTabLinked = false
    private var signalSource: DispatchSourceSignal?
    private var appsObservation: NSKeyValueObservation?
    private var syncing = false, syncAgain = false
    // 標準 Dock を隠したまま終了するか（ログアウト・再起動・システム終了、インストールし直すときの kill）
    private var keepSystemDockHidden = false
    private var safeMode = false

    // ログイン時の起動。異常終了したら launchd が起動し直す（KeepAlive）。普通に終了したときは起動し直さない
    private static let loginAgent = SMAppService.agent(plistName: "com.ryuto.Shoji.agent.plist")

    // 単体アプリのバンドル ID
    private static let dockID = "com.ryuto.GlassDock", tabsID = "com.ryuto.shelftabs", missionID = "com.ryuto.MissionView"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ログイン項目の起動と手動の起動が重なったときなどは、あとから起動した方が身を引く
        if Self.anotherInstanceRunning() { exit(0) }
        safeMode = LaunchGuard.begin()
        Self.importSettings()
        // kill などで終了されたときも applicationWillTerminate を通し、標準 Dock や隠したウィンドウを元に戻す
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.keepSystemDockHidden = true
            NSApp.terminate(nil)
        }
        source.resume()
        signalSource = source
        // 初回は自動でログイン項目に入れる（単体版の代わりに Shoji が起動するように）。
        // 以前の版はアプリそのものをログイン項目にしていた。落ちたときに起動し直せるよう launchd のエージェントに移す
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "shoji.loginItemConfigured") || SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            try? Self.loginAgent.register()
            defaults.set(true, forKey: "shoji.loginItemConfigured")
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepSystemDockHidden = true }
        }
        if UpdateController.isConfigured { _ = UpdateController.shared }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // 名前を付けないと既定の「Item-0」になり、Thaw などのメニューバー管理アプリが同名のほかのアプリと取り違える
        statusItem.autosaveName = "com.ryuto.Shoji.statusItem"
        statusItem.button?.image = Self.menuBarIcon()
        if safeMode { return enterSafeMode() }

        // 単体版が動いている間は、その機能を統合版では止めて取り合いを避ける。あとから起動・終了したときもその場で切り替える。
        // メニューバーだけのアプリは didLaunchApplication が届かないので、起動中のアプリの一覧の増減を見る。
        // 増減したアプリのバンドル ID は取れないことがあるため、増減のたびに調べ直す（変わっていなければ何もしない）。
        // 起動した直後はまだ一覧から見つからないことがあるので、少しあとにもう一度調べる。
        // 調べる前に監視を始め、ほぼ同時に起動したときも取りこぼさないようにする
        appsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.syncFeatures() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated { self?.syncFeatures() }
            }
        }
        syncFeatures()
    }

    private static func standaloneRunning(_ bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
    }

    // 単体版の動作状況に合わせて各機能を止める・始め、設定画面・機能間の連携・メニューを作り直す
    private func syncFeatures() {
        // 機能の起動中に RunLoop が回って、もう一度呼ばれることがある。終わってからやり直す
        guard !syncing else { return syncAgain = true }
        syncing = true
        defer {
            syncing = false
            if syncAgain {
                syncAgain = false
                DispatchQueue.main.async { MainActor.assumeIsolated { self.syncFeatures() } }
            }
        }
        let wantsDock = !Self.standaloneRunning(Self.dockID)
        let wantsTabs = !Self.standaloneRunning(Self.tabsID)
        let wantsMission = !Self.standaloneRunning(Self.missionID)
        var changed = statusItem.menu == nil

        // 止める機能を参照するフックを先に外してから止める
        if (!wantsDock && glassDock != nil) || (!wantsTabs && shelfTabs != nil) || (!wantsMission && missionView != nil) {
            disconnectFeatures()
            changed = true
        }
        if !wantsMission, let f = missionView {
            f.stop()
            missionView = nil
        }
        if !wantsTabs, let f = shelfTabs {
            f.stop()
            shelfTabs = nil
        }
        if !wantsDock, let f = glassDock {
            // 標準 Dock は戻さない（単体版がそのまま隠しておく。戻すと Dock が再起動し、最小化中のウィンドウが開いてしまう）
            f.stop(restoreSystemDock: false)
            glassDock = nil
        }
        if wantsDock, glassDock == nil {
            glassDockFeature.start()
            glassDock = glassDockFeature
            changed = true
        }
        if wantsTabs, shelfTabs == nil {
            shelfTabsFeature.start()
            shelfTabs = shelfTabsFeature
            changed = true
        }
        if wantsMission, missionView == nil {
            missionViewFeature.start()
            missionView = missionViewFeature
            changed = true
        }
        guard changed else { return }
        disconnectFeatures()
        connectSettings()
        connectFeatures()
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        section(menu, title: "Dock", items: glassDock?.menuItems())
        section(menu, title: "タブ", items: shelfTabs?.menuItems())
        section(menu, title: "ウィンドウ一覧", items: missionView?.menuItems())
        let login = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        login.target = self
        login.state = Self.loginAgent.status == .enabled ? .on : .off
        menu.addItem(login)
        if UpdateController.isConfigured {
            menu.addItem(withTitle: "アップデートを確認…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Shoji を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    // 3つの機能の設定を GlassDock の設定ウィンドウにまとめ、ページどうしを行き来できるようにする
    private func connectSettings() {
        guard let glassDock else { return }
        let features: [(String, Bool)] = [("Dock", true), ("タブ", shelfTabs != nil), ("ウィンドウ一覧", missionView != nil)]
        var panes = [HostSettingsPane(id: "shoji", title: "一般", symbol: "square.grid.2x2.fill", color: .gray, section: "Shoji") {
            ShojiGeneralPane(features: features)
        }]
        if let shelfTabs {
            panes += shelfTabs.settingsPages().map { p in
                HostSettingsPane(id: p.id, title: p.title, symbol: p.symbol, color: .teal, section: "タブ", wrapsInScroll: false) { p.view }
            }
            shelfTabs.presentSettings = { [weak glassDock] in glassDock?.openSettingsPane("shelfTabs.general") }
            shelfTabs.openDockSettings = { [weak glassDock] in glassDock?.openSettingsPane("general") }
        }
        if missionView != nil {
            panes.append(HostSettingsPane(id: "missionView", title: "ウィンドウ一覧", symbol: "rectangle.3.group.fill", color: .indigo,
                                          section: "ウィンドウ一覧") { MissionViewPane(glassDock: glassDock) })
            // Option+Tab は片方だけが動くようにする（両方オンなら、これまで使っていたウィンドウ一覧を優先）
            let mv = MissionViewSettings.shared
            if mv.optionTab { glassDock.windowSwitcherEnabled = false }
            if !optionTabLinked {
                // 設定の取り合いを防ぐだけなので、どちらかを止めている間もつないだままにする
                optionTabLinked = true
                glassDock.observeWindowSwitcher { on in if on { MissionViewSettings.shared.optionTab = false } }
                NotificationCenter.default.addObserver(forName: MissionViewSettings.didChange, object: nil, queue: .main) { [weak glassDock] _ in
                    MainActor.assumeIsolated { if MissionViewSettings.shared.optionTab { glassDock?.windowSwitcherEnabled = false } }
                }
            }
        }
        HostSettings.sectionsBeforeDock = ["Shoji"]
        HostSettings.panes = panes
    }

    // 機能どうしで情報を共有する。ウィンドウの判定・最小化した順・サムネイルは Dock と、
    // 分割表示・上端へのドラッグは ShelfTabs とウィンドウ一覧でつなぐ
    // connectSettings・connectFeatures で張ったものをすべて外す（止めた機能を呼ばないように）
    private func disconnectFeatures() {
        HostSettings.panes = []
        shelfTabsFeature.presentSettings = nil
        shelfTabsFeature.openDockSettings = nil
        shelfTabsFeature.onRequestMissionControl = nil
        shelfTabsFeature.onSnapPlaced = nil
        MissionViewHooks.userWindowIDs = nil
        MissionViewHooks.minimizeTimes = nil
        MissionViewHooks.lastMinimized = nil
        MissionViewHooks.cachedThumbnail = nil
        MissionViewHooks.storeThumbnail = nil
        MissionViewHooks.place = nil
        MissionViewHooks.restoreFrame = nil
        SharedWindows.onMinimizeChange = nil
        SharedWindows.splitSets = nil
    }

    private func connectFeatures() {
        guard let missionView else { return }
        MissionViewHooks.userWindowIDs = { SharedWindows.userWindowIDs(pid: $0) }
        if glassDock != nil {
            MissionViewHooks.minimizeTimes = { SharedWindows.minimizedTimes }
            MissionViewHooks.lastMinimized = { SharedWindows.lastMinimized }
            MissionViewHooks.cachedThumbnail = { SharedWindows.cachedThumbnail($0) }
            MissionViewHooks.storeThumbnail = { SharedWindows.storeThumbnail($0, for: $1) }
            SharedWindows.onMinimizeChange = { [weak missionView] pid, id, on in
                missionView?.windowMinimizeChanged(pid: pid, windowID: id, minimized: on)
            }
        }
        guard let shelfTabs else { return }
        SharedWindows.splitSets = { [weak missionView, weak shelfTabs] in
            missionView?.splitSets(snapped: shelfTabs?.snappedWindowIDs() ?? []) ?? []
        }
        MissionViewHooks.place = { [weak shelfTabs] pid, id, rect in shelfTabs?.place(pid: pid, windowID: id, in: rect) }
        MissionViewHooks.restoreFrame = { [weak shelfTabs] pid, id in shelfTabs?.restoreSnapped(pid: pid, windowID: id) }
        shelfTabs.onRequestMissionControl = { [weak missionView] pid, id, frame in
            missionView?.showCarrying(pid: pid, windowID: id, originalFrame: frame)
        }
        shelfTabs.onSnapPlaced = { [weak missionView, weak shelfTabs] rect, placedID, _ in
            missionView?.pickWindow(filling: rect, excluding: placedID) { pid, id in
                shelfTabs?.place(pid: pid, windowID: id, in: rect)
            }
        }
    }

    @objc private func openSettings() {
        if let glassDock { return glassDock.openSettingsPane("shoji") }
        // 単体版の GlassDock が動いていてまとめられないときは、それぞれの設定を開く
        shelfTabs?.openSettings()
    }

    @objc private func checkForUpdates() { UpdateController.shared.checkForUpdates() }

    @objc private func toggleLoginItem(_ item: NSMenuItem) {
        let service = Self.loginAgent
        if service.status == .enabled { try? service.unregister() } else { try? service.register() }
        item.state = service.status == .enabled ? .on : .off
    }

    // メニューから Shoji を終了したら、標準 Dock を元に戻して Shoji がないときと同じ動作にする。
    // ログアウト・再起動、アップデートやインストールし直しでの終了では戻さない（戻すと Dock が再起動し、
    // 最小化していたウィンドウが開いてしまう。次の起動ですぐまた隠す）。起動に失敗し続けたときは安全モードが戻す
    func applicationWillTerminate(_ notification: Notification) {
        glassDock?.stop(restoreSystemDock: !keepSystemDockHidden && !UpdateController.relaunchingForUpdate)
        shelfTabs?.stop()
        LaunchGuard.end()
    }

    private static func anotherInstanceRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0 != .current && !$0.isTerminated }
        guard !others.isEmpty else { return false }
        // 安全モードから起動し直したときは、前の Shoji が終わるのを待つ
        guard CommandLine.arguments.contains("--relaunch") else { return true }
        for _ in 0..<50 where others.contains(where: { kill($0.processIdentifier, 0) == 0 }) { usleep(100_000) }
        return others.contains { kill($0.processIdentifier, 0) == 0 }
    }

    // 続けて異常終了したときは機能を動かさず、隠した標準 Dock とタブの裏に隠したウィンドウを元に戻す
    private func enterSafeMode() {
        GlassDockFeature.restoreSystemDock()
        ShelfTabsFeature.recoverParkedWindows()
        let menu = NSMenu()
        menu.addItem(withTitle: "安全モードで起動しています", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "続けて異常終了したため、機能を止めて標準の動作に戻しました", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "通常どおり起動し直す", action: #selector(relaunchNormally), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Shoji を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func relaunchNormally() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["--relaunch"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // items が nil なら、単体アプリに譲って止めている
    private func section(_ menu: NSMenu, title: String, items: [NSMenuItem]?) {
        let header = NSMenuItem.sectionHeader(title: title)
        menu.addItem(header)
        if let items {
            // 各機能の「設定…」が同じ ⌘, を使うので、統合版ではショートカットを外す
            for item in items {
                // 統合版ではメニュー先頭の「設定…」にまとめる（単体版の GlassDock が動いているときは残す）
                if glassDock != nil,
                   item.action == #selector(GlassDockFeature.openSettings) || item.action == #selector(ShelfTabsFeature.openSettings) { continue }
                item.keyEquivalent = ""
                menu.addItem(item)
            }
        } else {
            menu.addItem(withTitle: "単体アプリが動作中のため停止中", action: nil, keyEquivalent: "").isEnabled = false
            // 単体アプリもログイン時に起動する設定だと、毎回こちらが止まるため
            menu.addItem(withTitle: "単体アプリを終了すると Shoji で動きます", action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.addItem(.separator())
    }

    // 初回だけ、単体アプリの設定を引き継ぐ（キーは両アプリで重ならない。Sparkle の項目は除く）
    private static func importSettings() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "shoji.importedSettings") else { return }
        for domain in [dockID, tabsID, missionID] {
            for (key, value) in defaults.persistentDomain(forName: domain) ?? [:]
            where !key.hasPrefix("SU") && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "shoji.importedSettings")
    }

    // 障子の組子（枠＋縦 1 本・横 2 本）。テンプレート画像にしてメニューバーの白黒表示に合わせる
    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let frame = NSRect(x: 2.5, y: 2.5, width: 13, height: 13)
            let path = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
            path.lineWidth = 1.6
            path.stroke()
            let lattice = NSBezierPath()
            lattice.move(to: NSPoint(x: 9, y: 3)); lattice.line(to: NSPoint(x: 9, y: 15))
            for y in [6.8, 11.2] { lattice.move(to: NSPoint(x: 3, y: y)); lattice.line(to: NSPoint(x: 15, y: y)) }
            lattice.lineWidth = 1.1
            lattice.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Shoji"
        return image
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

// 起動したまま落ちたかを覚えておき、3 分以内に 3 回落ちたら安全モードで起動する
enum LaunchGuard {
    private static let runningKey = "shoji.running", crashesKey = "shoji.recentCrashes"

    static func begin() -> Bool {
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        var crashes = (d.array(forKey: crashesKey) as? [Double] ?? []).filter { now - $0 < 180 }
        if d.bool(forKey: runningKey) { crashes.append(now) }
        let safe = crashes.count >= 3
        d.set(safe ? [] : crashes, forKey: crashesKey)
        d.set(true, forKey: runningKey)
        return safe
    }

    static func end() {
        UserDefaults.standard.set(false, forKey: runningKey)
    }
}

import GlassDockKit
import MissionViewKit
import ServiceManagement
import SwiftUI

// Option+Tab はウィンドウ一覧と Dock の切り替えのどちらか一方だけを使う
enum OptionTabOwner: String, CaseIterable, Identifiable {
    case missionView, glassDock, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .missionView: "ウィンドウ一覧"
        case .glassDock: "Dock の切り替え"
        case .none: "使わない"
        }
    }
}

struct MissionViewPane: View {
    @ObservedObject var settings = MissionViewSettings.shared
    let glassDock: GlassDockFeature?
    @State private var owner = OptionTabOwner.none

    var body: some View {
        SettingsCard(title: "4本指ジェスチャー", footer: "オフにすると、4本指の上下は macOS 標準の Mission Control に戻ります。") {
            SettingsSwitch("4本指の上下で開く・閉じる", isOn: $settings.fourFinger)
            if settings.fourFinger {
                SettingsDivider()
                SettingsSwitch("閉じているときの下スワイプで手前のウィンドウを最小化", isOn: $settings.minimizeOnSwipeDown)
                SettingsDivider()
                SettingsSwitch("4本指で開いたときに Dock を表示", isOn: $settings.showDockOnGesture)
                if glassDock != nil {
                    SettingsDivider()
                    SettingsLink("Dock の配置と自動的に隠す設定", pane: "general")
                }
            }
        }
        SettingsCard(title: "Option+Tab", footer: "同じキーを取り合わないよう、どちらか一方だけが動きます。") {
            SettingsRow("Option+Tab で開くもの") {
                Picker("", selection: Binding(get: { owner }, set: setOwner)) {
                    ForEach(OptionTabOwner.allCases.filter { $0 != .glassDock || glassDock != nil }) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        SettingsCard(title: "操作") {
            SettingsSwitch("2本指の横スクロールでデスクトップを切り替え", isOn: $settings.scrollSwitchesDesktop)
        }
        SettingsCard(title: "ウィンドウの移動", footer: MissionViewFeature.capabilitySummary) {
            SettingsLink("アクセシビリティと画面収録の権限", pane: "permissions")
        }
        .onAppear(perform: syncOwner)
        .onReceive(NotificationCenter.default.publisher(for: MissionViewSettings.didChange)) { _ in syncOwner() }
    }

    private func syncOwner() {
        owner = settings.optionTab ? .missionView : glassDock?.windowSwitcherEnabled == true ? .glassDock : .none
    }

    private func setOwner(_ o: OptionTabOwner) {
        owner = o
        glassDock?.windowSwitcherEnabled = o == .glassDock
        settings.optionTab = o == .missionView
    }
}

struct ShojiGeneralPane: View {
    let features: [(name: String, running: Bool)]
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        SettingsCard(title: "起動") {
            SettingsSwitch("ログイン時に起動", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, v in
                    if v { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
        }
        SettingsCard(title: "機能", footer: "単体アプリが起動しているあいだは、その機能を Shoji では止めて取り合いを避けます。") {
            ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                if i > 0 { SettingsDivider() }
                SettingsRow(f.name) {
                    Label(f.running ? "Shoji で動作中" : "単体アプリが動作中のため停止中",
                          systemImage: f.running ? "checkmark.circle.fill" : "pause.circle.fill")
                        .foregroundStyle(f.running ? .green : .orange)
                }
            }
        }
        SettingsCard(title: "権限") {
            SettingsLink("アクセシビリティ・画面収録などの権限", pane: "permissions")
        }
        UpdateCard()
    }
}

struct UpdateCard: View {
    @Bindable private var updates = UpdateController.shared

    var body: some View {
        SettingsCard(title: "アップデート", footer: UpdateController.isConfigured
                     ? "新しいバージョンは GitHub のリリースから取得し、署名を検証してから適用します。"
                     : "このビルドにはアップデート用の署名鍵が含まれていないため、自動アップデートは無効です。") {
            SettingsRow("バージョン") { Text(UpdateController.version).foregroundStyle(.secondary).monospacedDigit() }
            if UpdateController.isConfigured {
                SettingsDivider()
                SettingsSwitch("アップデートを自動的に確認", isOn: $updates.automaticallyChecks)
                SettingsDivider()
                SettingsRow("今すぐ確認") {
                    Button("アップデートを確認…") { updates.checkForUpdates() }.buttonStyle(.glass)
                }
            }
        }
    }
}

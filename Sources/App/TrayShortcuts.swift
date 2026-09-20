import AppIntents

struct TrayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshTrayActivityIntent(),
            phrases: [
                "\(.applicationName) の表示を更新",
                "\(.applicationName) を更新"
            ],
            shortTitle: "トレイの表示を更新",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: AddToTrayIntent(),
            phrases: [
                "\(.applicationName) に追加",
                "\(.applicationName) にファイルを追加"
            ],
            shortTitle: "トレイに追加",
            systemImageName: "tray.and.arrow.down"
        )
        AppShortcut(
            intent: AddToClipboardIntent(),
            phrases: [
                "\(.applicationName) にコピー",
                "\(.applicationName) のクリップボードに追加"
            ],
            shortTitle: "クリップボードに追加",
            systemImageName: "list.clipboard"
        )
    }
}

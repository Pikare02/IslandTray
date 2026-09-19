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
    }
}

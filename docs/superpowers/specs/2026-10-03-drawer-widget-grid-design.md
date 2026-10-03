# ドロワーウィジェット: 可変グリッド・個数設定・タイルごとの起動 設計

- Status: レビュー待ち
- Date: 2026-10-03
- Target: 1.11.0（1.10.0 のウィジェットの改良）

## 要望

1. ウィジェットのアイコンは先頭から詰め、ある分だけ出す。最大 9 個。タイルは常に正方形。
2. 長押し → ウィジェットを編集 で、表示する個数を明示的に選べる。
3. どのウィジェットでも、タイルをタップしたらそのアプリ（リンク）が開く。

ユーザー確認済みの決定: Small は 3×3、Medium は 5 列×2 行（どちらも名前なし、最大 9）。
アイランド自体は今までどおり先頭 6 個だけ描く。ロック画面の長方形ウィジェットもタイルごとに起動する。

## A. 状態が運ぶスロット数: 6 → 9

- `TrayContentState.maxSlots = 9`（状態・スナップショット・デコード時の上限）。
- 新規 `TrayContentState.islandSlots = 6`。アイランドの `DrawerStrip`（拡張領域・ロック画面 LA）は
  `slots.prefix(islandSlots)` だけ描く。表示は 1.10.0 と変わらない。
- `DrawerState.slots/icons` は `maxSlots` まで返す。
- **tray 状態の combined atlas**（`TrayActivityController.pagedState`, `lockDrawer` オン時）に載せる
  ドロワーアイコンは **先頭 `islandSlots` 個だけ**にする。trayタイル 4 + ドロワー 9 = 13 タイルは
  WebP でも 4096 バイトを超えやすく、`withDrawer` が全スロットを symbol-only に落として
  1.9.6 の症状が再発するため。7〜9 番目は tray 状態では `hasIcon: false` になるが、
  `DrawerSnapshot` は drawer 状態（9 タイルの atlas、品質ラダーあり）を優先し、アイコンの少ない
  tray 状態では上書きしないので、ウィジェットは drawer 状態の 9 個を保つ。
- drawer 状態の atlas は 9 タイルになり、`ThumbnailService.drawerQualities` のラダーで収まる段まで落ちる。
  ショートカットが 6 個以下のユーザーには何も変わらない。
- `DrawerIconFiles`（TrollStore の共有コンテナ）は `0..<maxSlots` = 9 ファイル。

## B. ウィジェット設定（個数）

- `Sources/Widget/DrawerWidgetConfigurationIntent.swift`:
  `struct DrawerWidgetConfigurationIntent: WidgetConfigurationIntent` に
  `@Parameter(title: LocalizedStringResource("widget.count.title"), default: 9, inclusiveRange: (1, 9)) var count: Int`。
  `title = LocalizedStringResource("widget.drawer.name")`。
- `DrawerWidget` は `StaticConfiguration` → `AppIntentConfiguration(kind:intent:provider:)`、
  `Provider: AppIntentTimelineProvider`。`Entry` に `count: Int` を持たせる。
- 文字列 `widget.count.title`（ja「表示するアイコン数」/ en “Icons shown” / ko「표시할 아이콘 수」）を 3 言語に追加。

## C. レイアウト（`Sources/Shared/DrawerWidgetLayout.swift`, テスト可能）

```swift
enum DrawerWidgetLayout {
    /// 1 行あたりの正方形タイル数。
    static func columns(for family: WidgetFamily) -> Int   // small 3, medium 5, accessoryRectangular 4, else 1
    /// その家族が持てる最大タイル数。
    static func capacity(for family: WidgetFamily) -> Int  // small 9, medium 9（5×2 の 10 を 9 に制限）, accessoryRectangular 4, else 1
    /// 先頭から、設定個数と容量の小さい方まで。
    static func shown(_ slots: [DrawerSlot], count: Int, family: WidgetFamily) -> [DrawerSlot]
}
```

- ビュー: `LazyVGrid(columns: columns × .flexible(), spacing: 6)` を上詰め（`VStack { grid; Spacer(minLength: 0) }`）。
  タイルは `Color.white.opacity(0.08).aspectRatio(1, .fit)` + `DrawerIcon` + 角丸 10。名前は出さない。
  Medium の `DrawerStrip` は使わない（1 行 6 個＋名前は廃止）。
- 空（payload なし / 0 個）: 従来の `widget.drawer.empty` 文言。
- Circular: 変更なし（ランチャーグリフ、タップでドロワー）。

## D. タップでそのアプリを開く

| 家族 | 仕組み |
|---|---|
| Medium | タイルごとに `Link(destination: slot.launch)`。システムが URL を直接開く（1.10.0 と同じ）。 |
| Small, Lock 長方形 | `Link` 不可の家族なので `Button(intent: LaunchDrawerSlotIntent(launch: slot.launch))`。 |

- `Sources/App/LaunchDrawerSlotIntent.swift`（project.yml でウィジェットターゲットにも追加。既存の
  `ToggleDrawerIntent` と同じ扱い）:
  `struct LaunchDrawerSlotIntent: AppIntent`、`openAppWhenRun = true`、`@Parameter var launch: String`。
  `perform()` はアプリ内で動く: `LaunchDrawerSlotIntent.pending = url` を立て、
  `NotificationCenter.default.post(name: .launchDrawerSlot, object: url)`。
  （`UIApplication` は拡張ターゲットではコンパイルできないので、intent 自身は URL を渡すだけ。）
- `IslandTrayApp`: 既存の `onOpenURL` の switch を `handle(_ url: URL)` に切り出し、`onOpenURL` と
  `.onReceive(.launchDrawerSlot)` の両方から呼ぶ。コールドスタートで通知が view より先に飛んだ場合に備え、
  scenePhase が `.active` になったとき `LaunchDrawerSlotIntent.takePending()` も `handle` に流す。
  分岐は従来どおり: `islandtray://launch?item=` → `LaunchRouter.performLaunch`、それ以外 → `UIApplication.shared.open`。
- ロック画面でボタンが効かない iOS では、従来の `.widgetURL(TrayIDs.drawerURL)` がフォールバックとして残る
  （Small と長方形にはこれまでどおり widgetURL を付けておく）。

## E. テスト

- `Tests/DrawerWidgetLayoutTests.swift`: columns/capacity の値、`shown` が `min(count, capacity, slots.count)` 個を先頭から返す、count が 0 以下でも落ちない。
- `Tests/TrayContentStateDrawerTests.swift`: 9 スロット＋atlas で `makeDrawer` が 9 個を保つ（予算内）、
  `islandSlots == 6`、デコードが 9 個まで通す。
- `Tests/DrawerStateTests.swift`: `slots(from:)` が 9 個まで返す（既存の 6 個前提があれば更新）。
- `LaunchDrawerSlotIntent`: `pending` の set/take が 1 回きりであることだけ（純粋ロジック）。

## リリース

- `project.yml` 1.11.0 / build 31、CHANGELOG（en/ja）、`docs/index.html`、タグはユーザー指示で。

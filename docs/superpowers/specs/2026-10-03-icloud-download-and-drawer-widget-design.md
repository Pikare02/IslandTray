# iCloud 未ダウンロード項目の即時取得 + ホーム/ロック画面「アプリドロワー」ウィジェット 設計

- Status: レビュー待ち
- Date: 2026-10-03
- Target: 次のマイナーリリース（1.10.0）。両機能とも iOS 17.0 の API のみで実装する

## 背景（ユーザー報告）

1. ファイル App（iCloud Drive）から**まだ端末にダウンロードされていない**ファイル/フォルダをトレイに
   入れると、正しく取り込まれない。入れた時点で即ダウンロードして取り込んでほしい。
2. 同じ項目をもう一度入れたときの「同じファイルがすでにトレイにあります」ポップアップが、
   上記の iCloud 未ダウンロード項目では出ない。
3. ダイナミックアイランドにあるアプリドロワーを、ホーム画面とロック画面のウィジェットでも使いたい。

1 と 2 は同じ原因である。既存の重複判定（`DropReceiver.duplicate(of:among:)`）はサイズ一致 → SHA-256
一致で実バイトを比べる。未ダウンロード項目はプレースホルダ（0 バイト、または `.X.icloud`）のまま
ステージングされるため、サイズも内容も既存項目と一致せず、重複として扱われない。
**実バイトを取り込めるようにすれば、重複ポップアップは既存ロジックのまま動く。** 新しい判定は足さない。

---

## パート A: 取り込み前に iCloud 項目をダウンロードする

### 決定

- **コピーの共通経路 1 箇所**で、取り込み元に含まれる未ダウンロード項目をすべてダウンロードし、
  完了を待ってからコピーする。ドロップ / 「トレイに追加」ショートカット / Files インボックス /
  共有拡張のすべてが `TrayStore.coordinatedCopy(from:to:)` を通るので、そこに入れる。
- 同期的に待つ（ポーリング）。呼び出し元はすべてバックグラウンド（`NSItemProvider` の完了ハンドラ、
  `Task.detached`、インボックス掃除）で動いており、UI は塞がない。
- タイムアウトは **120 秒**。超えたらエラーを投げ、既存の「取り込めませんでした: X」バナーに乗る。
- フォルダは**中身を再帰的に**対象にする。フォルダ自体の coordinated read は子を落としてこないため。

### 新規: `Sources/Shared/UbiquitousDownload.swift`

```swift
enum UbiquitousDownload {
    struct TimedOut: Error { let name: String }

    /// `url`（ファイルなら本体、フォルダなら中身すべて）のうち iCloud 上にしかないものを
    /// ダウンロードし、全部そろうまで待つ。iCloud と無関係な URL では即座に戻る。
    /// セキュリティスコープは呼び出し元が開いていること（既存の呼び出し元はすべて開いている）。
    static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 120, poll: TimeInterval = 0.5) throws

    /// `.X.icloud` → `X`。そうでなければ nil。`CloudFolder.placeholderTarget` はここへ委譲する。
    static func placeholderTarget(_ name: String) -> String?

    /// まだ落ちていない項目の URL（実名）。テスト用に公開する純粋関数。
    static func pending(in url: URL) -> [URL]
}
```

- `pending(in:)`: `url` と、ディレクトリなら `FileManager.enumerator(at:includingPropertiesForKeys:
  [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], options: [])`（隠しファイルを
  **含める**。`.X.icloud` は隠しファイル）で列挙した各項目について、
  - 名前が `placeholderTarget` に一致する → 実名 URL を pending に入れる
  - `isUbiquitousItem == true` かつ `ubiquitousItemDownloadingStatus != .current` → pending
- `ensureDownloaded`: `pending` の各 URL に `FileManager.startDownloadingUbiquitousItem(at:)`
  （失敗は無視。CloudSync と同じ扱い）。その後 `poll` 間隔で `pending(in:)` を取り直し、空になれば
  戻る。期限を過ぎたら `TimedOut(name: 最初の未完了項目の lastPathComponent)`。
  新たに現れた pending（フォルダのサブフォルダが落ちてきて中身が見えた場合）にも同じループ内で
  `startDownloading` をかける。

### 変更

- `TrayStore.coordinatedCopy(from:to:)`: 先頭で `try UbiquitousDownload.ensureDownloaded(source)`。
- `TrayStore.add(copyingFrom:…)`: `size` の算出をコピー**後**に `byteCount(of: destination)` で行う
  （ショートカット/インボックス経路で、プレースホルダのサイズを記録しないため）。
- `CloudFolder.placeholderTarget`: 本体を `UbiquitousDownload.placeholderTarget` に移し、1 行で委譲。
- `TrayModel`: `var isImporting = false`。`ingest(_:)` と `addPendingDuplicates()` の間 true。
- `TrayView`: バナー表示の隣（`model.banner` を描いている箇所）に、`isImporting` の間だけ
  `ProgressView().controlSize(.small)` + `L.s("banner.importing")` を出す。
- 文字列 `banner.importing`: ja「取り込み中…」/ en “Taking in…” / ko「가져오는 중…」。

### 影響しないこと

- CloudSync の `adopt(_:copyingFrom:)` も `coordinatedCopy` を通るが、同期は自前でダウンロード完了を
  確認してから `adopt` するので `ensureDownloaded` は即座に戻る。
- フォルダの重複判定は引き続き対象外（既存どおり）。

### テスト: `Tests/UbiquitousDownloadTests.swift`

1. ローカルのファイル/フォルダに対して `pending(in:)` が空、`ensureDownloaded` が即座に戻る。
2. `placeholderTarget`: `.a.txt.icloud` → `a.txt`、`a.txt` → nil、`.hidden` → nil。
3. フォルダ内に `.x.pdf.icloud` を置いたとき `pending(in:)` が `x.pdf` の URL を返す
   （iCloud 実機なしで到達できるのはここまで。実際のダウンロード待ちは実機で確認する）。
4. `TrayStoreTests`: フォルダを `add(copyingFrom:)` したとき `size` がコピー先の合計バイトに等しい。

---

## パート B: ホーム/ロック画面ウィジェット

### 制約と決定

- Free（AltStore/SideStore）ビルドには App Group がなく、アプリ → ウィジェット拡張にファイルを渡せない。
- しかし **Live Activity のビューはウィジェット拡張プロセスで描画される。** そこで届いた
  `TrayContentState` には、ドロワーのスロット（名前・起動 URL・シンボル）とアイコン atlas が
  すでに入っている（合計 4096 バイト以下）。
- 決定: **Live Activity を描画するたびに、拡張自身のコンテナにドロワー状態を保存**し、
  ホーム/ロック画面ウィジェットはそれを読む。エンタイトルメント不要で、Free / TrollStore 共通の
  1 本の経路になる。TrollStore では `DrawerIconFiles`（App Group の高解像度アイコン）を
  `DrawerStrip` が既に優先するので、そのまま高解像度になる。
- 既知の制限: アイランドが一度も更新されていない端末ではウィジェットは空で、
  「アプリドロワーをオンにしてアイランドを更新してください」と案内する。ドロワー構成の変更は
  アプリがアイランドを更新した時点（既存の `TrayActivityController.sync`）でウィジェットに反映される。

### 新規: `Sources/Shared/DrawerSnapshot.swift`

```swift
import WidgetKit

enum DrawerSnapshot {
    struct Payload: Codable, Equatable {
        let slots: [TrayContentState.DrawerSlot]
        let atlas: Data?
        /// `atlas` 内でドロワーのタイルが始まる位置（Live Activity の lockScreen と同じ式）。
        let atlasOffset: Int
    }

    enum Change { case written, removed, unchanged }

    static let widgetKind = "DrawerWidget"
    /// 呼び出したプロセス自身の Application Support/IslandTray/drawer-snapshot.json。
    static var url: URL

    /// 描画された状態を保存する。変化があったときだけ書き、`reloadTimelines(ofKind:)` を呼ぶ。
    /// 戻り値はテスト用: 書いた / 消した / 変化なし。
    @discardableResult
    static func record(_ state: TrayContentState, at url: URL = url) -> Change
    static func load(from url: URL = url) -> Payload?
}
```

- `record`: `state.drawerAvailable == false` → ファイルを削除（あったときだけ reload）。
  `state.drawer` があれば Payload を作り、既存バイトと比較して違うときだけ `.atomic` +
  `TrayContainer.lockScreenReadableWrite` で書き、`WidgetCenter.shared.reloadTimelines(ofKind:)`。
  ロック画面で描画中にも書けるよう保護クラスは既存の `completeUntilFirstUserAuthentication`。
- `atlasOffset = state.view == .drawer ? 0 : state.recent.count`（`TrayLiveActivity.lockScreen` と同じ）。
- Shared に置く理由: テストターゲットは App のソースしか見えず、`Sources/Widget` は含まれない。
  App/Share からは呼ばれない。`import WidgetKit` が App/Share にも入るが害はない。

### フック

- `TrayLiveActivity.lockScreen(_:)` の先頭で `let _ = DrawerSnapshot.record(state)`。
  ロック画面プレゼンテーションは更新のたびに必ず評価される（`hideLockScreen` のときも `Color.clear`
  を返す分岐が走る）ので、ここ 1 箇所でよい。

### 新規: `Sources/Widget/DrawerWidget.swift`

- `struct DrawerWidget: Widget` — `StaticConfiguration(kind: DrawerSnapshot.widgetKind, provider:)`。
  `supportedFamilies: [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular]`。
  表示名 `widget.drawer.name`、説明 `widget.drawer.desc`。
- `Provider: TimelineProvider` — `Entry { date; payload: DrawerSnapshot.Payload? }`。
  `placeholder` は SF Symbol だけの 4 スロット。`getTimeline` は `load()` 1 エントリ、
  ポリシー `.never`（更新は `record` が `reloadTimelines` で起こす）。
- ビュー（`@Environment(\.widgetFamily)` で分岐）:
  - **systemMedium**: `DrawerStrip(slots:atlas:side: 56, atlasOffset:)`。各タイルが `Link`（既存）。
  - **systemSmall**: 先頭 4 スロットを 2×2 グリッド。`Link` は使えない家族なので
    `.widgetURL(TrayIDs.drawerURL)`（タップでアプリのドロワー画面）。
  - **accessoryRectangular**: 先頭 4 スロットのアイコンを横一列。`.widgetURL(TrayIDs.drawerURL)`。
  - **accessoryCircular**: `AccessoryWidgetBackground()` + `square.grid.2x2.fill`。同じ widgetURL。
  - payload なし: `widget.drawer.empty` のテキスト（+ widgetURL）。
  - 背景は `containerBackground(for: .widget)` に黒 0.85（アイランドと同系）。アクセサリ家族は
    システムが単色化するのでそのまま。
- アイコン描画は `DrawerStrip.iconImage` を `DrawerIcon`（`slot`, `index`, `tiles` を受ける小さな
  View）に切り出し、`DrawerStrip` と `DrawerWidget` の両方がそれを使う。描画の優先順位
  （`DrawerIconFiles` → atlas タイル → SF Symbol）は変えない。
- `IslandTrayWidgetBundle.body` に `DrawerWidget()` を追加。

### 起動経路

- ホームウィジェットの `Link` の URL はシステムがそのまま開く（`shortcuts://`、他 App のスキーム、
  web URL）。`islandtray://launch?item=` はアプリに届き、既存の `LaunchRouter.route` →
  `.launch(id)` で処理される。ロック画面/Small の `TrayIDs.drawerURL` も既存の `.drawer`。
  **LaunchRouter に変更なし。**

### 文字列（ja / en / ko）

| キー | ja | en | ko |
|---|---|---|---|
| `widget.drawer.name` | アプリドロワー | App Drawer | 앱 서랍 |
| `widget.drawer.desc` | アイランドのアプリドロワーをホーム画面とロック画面に。 | The island's app drawer, on your Home and Lock Screen. | 아일랜드의 앱 서랍을 홈 화면과 잠금 화면에. |
| `widget.drawer.empty` | アプリドロワーをオンにして、アイランドを一度更新してください | Turn on the app drawer and refresh the island once | 앱 서랍을 켜고 아일랜드를 한 번 갱신하세요 |

### テスト: `Tests/DrawerSnapshotTests.swift`

1. ドロワーを含む状態を `record` → ファイルができ、`load` が同じ slots / atlas / offset を返す。
2. 同じ状態をもう一度 `record` → `.unchanged`（ファイルは書き直されない）。
3. `drawerAvailable == false` の状態を `record` → ファイルが消える。
4. tray ビュー + drawer の状態では `atlasOffset == recent.count`、drawer ビューでは 0。

---

## リリース準備（タグは打たない）

- `project.yml` のバージョンを 1.10.0 に、`CHANGELOG.md` / `CHANGELOG.ja.md` に両機能の項目を追加。
  `docs/index.html` の更新とタグ付けは別途ユーザーの指示で行う。

## 実機でしか確認できないこと

- iCloud 未ダウンロードのファイル/フォルダのドロップ（シミュレータでは iCloud Drive の
  未ダウンロード状態を作れない）。確認手順: ファイル App で項目を「ダウンロードを削除」してから
  IslandTray にドロップ → 取り込み中インジケータ → 実サイズで取り込まれる → 同じ項目を再ドロップ
  → 重複ポップアップ。
- ウィジェット: アイランドを一度更新した後にホーム/ロック画面ウィジェットを追加して、
  アイコンと起動を確認。

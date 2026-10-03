# iCloud 即時ダウンロード + ドロワーウィジェット 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ファイル App から入れた iCloud 未ダウンロードのファイル/フォルダを取り込み前に全部ダウンロードし（重複ポップアップが実バイトで動くようにし）、アイランドのアプリドロワーをホーム/ロック画面ウィジェットとして出す。

**Architecture:** (A) 取り込みのコピーが全部通る `TrayStore.coordinatedCopy` の直前に、新しい `UbiquitousDownload.ensureDownloaded` が未ダウンロード項目（`.X.icloud` プレースホルダ含む、フォルダは再帰）を `startDownloadingUbiquitousItem` して完了までポーリングで待つ。(B) Live Activity のロック画面ビュー（ウィジェット拡張プロセスで評価される）が受け取った `TrayContentState` のドロワー部分を `DrawerSnapshot` として拡張自身のコンテナに保存し、新しい `DrawerWidget`（Home Small/Medium, Lock Rectangular/Circular）がそれを読む。App Group 不要。

**Tech Stack:** Swift 5 / SwiftUI / WidgetKit / ActivityKit / XCTest。iOS 17.0 API のみ。プロジェクトは `project.yml`（XcodeGen）から生成。

## Global Constraints

- Deployment target iOS 17.0。iOS 18 専用 API は使わない。
- 新しい依存は追加しない。
- `Sources/Shared` は App / Widget / Share の 3 ターゲットでコンパイルされる。UIKit/SwiftUI 依存の重いものは置かない（`import WidgetKit` は可）。
- `Sources/Widget` はテストターゲット（`IslandTrayTests` は App ターゲットのみ依存）から見えない。テストしたいロジックは `Sources/Shared` に置く。
- 文字列は `L.s("key")`。`Resources/Localization/{en,ja,ko}.lproj/Localizable.strings` の 3 つすべてに追加する（ファイル末尾に追記でよい）。
- コードコメントは英語。
- コミットメッセージ末尾に `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` を付ける。
- テストコマンド（README と同じ）:
  `xcodebuild test -project IslandTray.xcodeproj -scheme IslandTray -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IslandTrayTests/<Class> 2>&1 | tail -30`
  （リポジトリルート `/Users/junyoungpark/Developer/IslandTray` で実行。`build/` ではない。）
- ビルド確認は両スキーム: `IslandTray`（TrollStore）と `IslandTray (Free)`。
- `IslandTray.xcodeproj` は git 管理外で、`project.yml` から XcodeGen が生成する（ソースはディレクトリ指定）。**新しい `.swift` ファイルを作ったら、ビルド/テストの前に必ずリポジトリルートで `xcodegen generate` を実行する**（Task 1, 4, 5, 6）。xcodeproj はコミットしない。
- タグは打たない。リリースは別途ユーザー指示。

## ファイル構成

| ファイル | 役割 |
|---|---|
| Create `Sources/Shared/UbiquitousDownload.swift` | iCloud 未ダウンロード項目の検出・ダウンロード待ち（Foundation のみ） |
| Modify `Sources/Shared/TrayStore.swift` | `coordinatedCopy` 先頭でダウンロード待ち、`add(copyingFrom:)` の size をコピー後に算出 |
| Modify `Sources/App/CloudSync.swift` | `CloudFolder.placeholderTarget` を `UbiquitousDownload` へ委譲 |
| Modify `Sources/App/TrayModel.swift` / `TrayView.swift` | `isImporting` と取り込み中インジケータ |
| Create `Sources/Shared/DrawerSnapshot.swift` | ドロワー状態の保存/読み込み（拡張自身のコンテナ） |
| Create `Sources/Widget/DrawerIcon.swift` | スロット 1 個のアイコン描画（`DrawerStrip` から切り出し） |
| Modify `Sources/Widget/DrawerStrip.swift` | `DrawerIcon` を使う |
| Modify `Sources/Widget/TrayLiveActivity.swift` | `lockScreen(_:)` 先頭で `DrawerSnapshot.record` |
| Create `Sources/Widget/DrawerWidget.swift` | ホーム/ロック画面ウィジェット |
| Modify `Sources/Widget/IslandTrayWidgetBundle.swift` | `DrawerWidget()` を登録 |
| Create `Tests/UbiquitousDownloadTests.swift`, `Tests/DrawerSnapshotTests.swift` | テスト |
| Modify `Resources/Localization/*/Localizable.strings` | 新規文字列 5 キー |
| Modify `project.yml`, `CHANGELOG.md`, `CHANGELOG.ja.md` | 1.10.0 |

---

### Task 1: `UbiquitousDownload` — 未ダウンロード項目の検出と待機

**Files:**
- Create: `Sources/Shared/UbiquitousDownload.swift`
- Modify: `Sources/App/CloudSync.swift:165-169`（`placeholderTarget` の本体を委譲）
- Modify: `Resources/Localization/{en,ja,ko}.lproj/Localizable.strings`（`cloud.downloadTimedOut`）
- Test: `Tests/UbiquitousDownloadTests.swift`

**Interfaces:**
- Produces:
  - `UbiquitousDownload.ensureDownloaded(_ url: URL, timeout: TimeInterval = 120, poll: TimeInterval = 0.5) throws`
  - `UbiquitousDownload.pending(in url: URL) -> [URL]`
  - `UbiquitousDownload.placeholderTarget(_ name: String) -> String?`
  - `UbiquitousDownload.TimedOut: LocalizedError { let name: String }`

- [ ] **Step 1: テストを書く**

`Tests/UbiquitousDownloadTests.swift`:

```swift
import XCTest
@testable import IslandTray

/// The real download can only be exercised on a device with iCloud Drive,
/// so these pin what can be pinned locally: which names count as
/// placeholders, that local files are never waited on, and that a
/// placeholder that never turns into a file is reported by name.
final class UbiquitousDownloadTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testPlaceholderNames() {
        XCTAssertEqual(UbiquitousDownload.placeholderTarget(".a.txt.icloud"), "a.txt")
        XCTAssertNil(UbiquitousDownload.placeholderTarget("a.txt"))
        XCTAssertNil(UbiquitousDownload.placeholderTarget(".hidden"))
    }

    func testLocalFilesHaveNothingPendingAndAreNotWaitedOn() throws {
        let file = scratch.appendingPathComponent("a.txt")
        try Data("hi".utf8).write(to: file)
        let sub = scratch.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: sub.appendingPathComponent("b.txt"))

        XCTAssertEqual(UbiquitousDownload.pending(in: file), [])
        XCTAssertEqual(UbiquitousDownload.pending(in: scratch), [])

        let started = Date()
        XCTAssertNoThrow(try UbiquitousDownload.ensureDownloaded(scratch, timeout: 5))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testAPlaceholderInsideAFolderIsPendingUnderItsRealName() throws {
        let sub = scratch.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data().write(to: sub.appendingPathComponent(".x.pdf.icloud"))

        XCTAssertEqual(UbiquitousDownload.pending(in: scratch).map(\.lastPathComponent), ["x.pdf"])
    }

    func testAPlaceholderThatNeverArrivesTimesOutNamingIt() throws {
        try Data().write(to: scratch.appendingPathComponent(".x.pdf.icloud"))

        XCTAssertThrowsError(
            try UbiquitousDownload.ensureDownloaded(scratch, timeout: 0.3, poll: 0.1)
        ) { error in
            XCTAssertEqual((error as? UbiquitousDownload.TimedOut)?.name, "x.pdf")
        }
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `xcodegen generate && xcodebuild test -project IslandTray.xcodeproj -scheme IslandTray -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IslandTrayTests/UbiquitousDownloadTests 2>&1 | tail -30`
Expected: コンパイルエラー `cannot find 'UbiquitousDownload' in scope`

- [ ] **Step 3: 実装**

`Sources/Shared/UbiquitousDownload.swift`:

```swift
import Foundation

/// Brings a file -- or everything inside a folder -- that iCloud lists but
/// has not put on this device down, before it is copied into the tray.
///
/// A coordinated read of one evicted file does trigger its download, but a
/// read of a folder does not fetch its children: a copy of the folder then
/// carries `.X.icloud` placeholders instead of files, with the wrong size,
/// and the bytes never match an item already in the tray. This walks the
/// source, asks for every missing item, and waits until none is missing.
///
/// Synchronous on purpose: every caller is already off the main actor (an
/// `NSItemProvider` completion queue, `Task.detached`, the inbox sweep).
/// The caller holds any security scope the URL needs.
enum UbiquitousDownload {
    struct TimedOut: LocalizedError {
        let name: String
        var errorDescription: String? { L.s("cloud.downloadTimedOut", name) }
    }

    /// `.X.icloud` is how iCloud lists a file it has not downloaded.
    static func placeholderTarget(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    private static let keys: Set<URLResourceKey> = [
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .isDirectoryKey,
    ]

    /// The real URLs of every item at or under `url` that is not on this
    /// device yet. Empty for anything outside iCloud.
    ///
    /// Hidden files are walked: the placeholders are hidden files.
    static func pending(in url: URL) -> [URL] {
        var urls = [url]
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
           let walker = FileManager.default.enumerator(
               at: url, includingPropertiesForKeys: Array(keys), options: []
           ) {
            while let child = walker.nextObject() as? URL { urls.append(child) }
        }
        return urls.compactMap { item in
            if let real = placeholderTarget(item.lastPathComponent) {
                return item.deletingLastPathComponent().appendingPathComponent(real)
            }
            // `.notDownloaded` only, not "anything but current": a folder in
            // iCloud reports no status at all, and would otherwise be waited
            // on until the deadline.
            guard let values = try? item.resourceValues(forKeys: keys),
                  values.isDirectory != true,
                  values.isUbiquitousItem == true,
                  values.ubiquitousItemDownloadingStatus == .notDownloaded else { return nil }
            return item
        }
    }

    /// Asks iCloud for everything `pending(in:)` lists and waits until the
    /// list is empty. Items that appear while waiting (a folder whose
    /// contents only became visible once it arrived) are asked for too.
    static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 120, poll: TimeInterval = 0.5) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var asked = Set<URL>()
        while true {
            let missing = pending(in: url)
            if missing.isEmpty { return }
            for item in missing where asked.insert(item).inserted {
                // A refusal is not reported here: an item that never
                // arrives is what the deadline below names.
                try? FileManager.default.startDownloadingUbiquitousItem(at: item)
            }
            if Date() >= deadline { throw TimedOut(name: missing[0].lastPathComponent) }
            Thread.sleep(forTimeInterval: poll)
        }
    }
}
```

`Sources/App/CloudSync.swift` の `placeholderTarget` を委譲に変える（docコメントは残す）:

```swift
    /// `.X.icloud` is how iCloud lists a file it has not downloaded.
    static func placeholderTarget(_ name: String) -> String? {
        UbiquitousDownload.placeholderTarget(name)
    }
```

3 つの `Localizable.strings` の末尾に追記:

- en: `"cloud.downloadTimedOut" = "%@ never finished downloading from iCloud";`
- ja: `"cloud.downloadTimedOut" = "%@ の iCloud からのダウンロードが終わりませんでした";`
- ko: `"cloud.downloadTimedOut" = "%@의 iCloud 다운로드가 끝나지 않았습니다";`

- [ ] **Step 4: テストを通す**

Run: `xcodegen generate` の後、上と同じコマンド（`UbiquitousDownloadTests`）、さらに `-only-testing:IslandTrayTests/CloudSyncTests`
Expected: 両方 `** TEST SUCCEEDED **`

- [ ] **Step 5: コミット**

```bash
git add Sources/Shared/UbiquitousDownload.swift Sources/App/CloudSync.swift Tests/UbiquitousDownloadTests.swift Resources/Localization
git commit -m "feat: detect and wait for iCloud items that are not on the device yet

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: コピー共通地点でダウンロードを待ち、size をコピー後に数える

**Files:**
- Modify: `Sources/Shared/TrayStore.swift:95-121`（`add(copyingFrom:)`）、`:596-607`（`coordinatedCopy`）
- Test: `Tests/TrayStoreTests.swift`（既存 `testAFolderIsStoredWholeAndKnownAsAFolder` が size を検証済み。新規テストは追加しない）

**Interfaces:**
- Consumes: `UbiquitousDownload.ensureDownloaded(_:)`（Task 1）
- Produces: 変更なし（`coordinatedCopy(from:to:)` のシグネチャはそのまま）

- [ ] **Step 1: `coordinatedCopy` の先頭でダウンロードを待つ**

`Sources/Shared/TrayStore.swift` の `coordinatedCopy` を次に置き換える:

```swift
    /// Copies inside a coordinated read of the source.
    ///
    /// The source is often another app's file -- the Files app's own copy of
    /// a folder, a document in iCloud Drive -- and its provider only
    /// materialises the contents (a folder's files, a download not yet on the
    /// device) for a reader that coordinates. An uncoordinated copy of a
    /// folder can fail, or copy an empty shell.
    ///
    /// Coordination alone does not fetch a folder's children from iCloud,
    /// so anything still in the cloud is downloaded first. Every way into the
    /// tray -- drop, share, shortcut, the Files inbox -- comes through here,
    /// which is what makes this the one place for it.
    static func coordinatedCopy(from source: URL, to destination: URL) throws {
        try UbiquitousDownload.ensureDownloaded(source)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
            do {
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
    }
```

- [ ] **Step 2: `add(copyingFrom:)` の size をコピー後に算出**

`add(copyingFrom:…)` 内の

```swift
        let name = suggestedName ?? source.lastPathComponent
        let size = Self.byteCount(of: source)
```

を

```swift
        let name = suggestedName ?? source.lastPathComponent
```

にし、`var item = makeItem(suggestedName: name, uti: uti, size: size)` を
`var item = makeItem(suggestedName: name, uti: uti, size: 0)` に変え、
`try Self.coordinatedCopy(from: source, to: destination)` の直後に次を入れる:

```swift
        // Counted on the copy, not the source: a source still partly in
        // iCloud reports its placeholders' sizes, the copy is the real bytes.
        item.size = Self.byteCount(of: destination)
```

- [ ] **Step 3: テスト**

Run: `xcodebuild test -project IslandTray.xcodeproj -scheme IslandTray -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IslandTrayTests/TrayStoreTests -only-testing:IslandTrayTests/DropReceiverTests -only-testing:IslandTrayTests/DocumentsInboxTests 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: コミット**

```bash
git add Sources/Shared/TrayStore.swift
git commit -m "fix: download iCloud items before copying them into the tray

A file or folder still in iCloud was copied as its placeholder, so it
arrived empty and never matched an item already in the tray.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: 取り込み中インジケータ

**Files:**
- Modify: `Sources/App/TrayModel.swift:169-181`（`ingest`）、`:242-270`（`addPendingDuplicates`）
- Modify: `Sources/App/TrayView.swift:311-318`（バナーの `safeAreaInset`）
- Modify: `Resources/Localization/{en,ja,ko}.lproj/Localizable.strings`（`banner.importing`）

**Interfaces:**
- Produces: `TrayModel.isImporting: Bool`

- [ ] **Step 1: `TrayModel` に `isImporting`**

`var banner: String?` の直後に追加:

```swift
    /// True while a drop (or an accepted duplicate) is being copied in. A
    /// source still in iCloud can take a while to arrive, and nothing else
    /// on screen moves until it has.
    var isImporting = false
```

`ingest(_:)` の先頭行 `let result = await DropReceiver.ingest(providers: providers)` の前に:

```swift
        isImporting = true
        defer { isImporting = false }
```

`addPendingDuplicates()` の `let staged = pendingDuplicates` の前にも同じ 2 行を入れる。

- [ ] **Step 2: `TrayView` にインジケータ**

`.safeAreaInset(edge: .bottom) { if let banner = model.banner { … } }` の**直前**に追加:

```swift
            .safeAreaInset(edge: .bottom) {
                if model.isImporting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L.s("banner.importing")).font(.footnote)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
                }
            }
```

- [ ] **Step 3: 文字列**

- en: `"banner.importing" = "Taking in…";`
- ja: `"banner.importing" = "取り込み中…";`
- ko: `"banner.importing" = "가져오는 중…";`

- [ ] **Step 4: ビルドとテスト**

Run: `xcodebuild test -project IslandTray.xcodeproj -scheme IslandTray -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IslandTrayTests/TrayModelTests 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: コミット**

```bash
git add Sources/App/TrayModel.swift Sources/App/TrayView.swift Resources/Localization
git commit -m "feat: show that a drop is still being taken in

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `DrawerSnapshot` — ドロワー状態の保存/読み込み

**Files:**
- Create: `Sources/Shared/DrawerSnapshot.swift`
- Test: `Tests/DrawerSnapshotTests.swift`

**Interfaces:**
- Consumes: `TrayContentState`（`drawer: [DrawerSlot]?`, `atlas: Data?`, `view: View`, `recent: [Preview]`, `drawerAvailable: Bool`）、`TrayContainer.lockScreenReadableWrite`
- Produces:
  - `DrawerSnapshot.Payload: Codable, Equatable { slots: [TrayContentState.DrawerSlot]; atlas: Data?; atlasOffset: Int }`
  - `DrawerSnapshot.Change: Equatable { .written, .removed, .unchanged }`
  - `DrawerSnapshot.widgetKind: String` = `"DrawerWidget"`
  - `DrawerSnapshot.url: URL`
  - `DrawerSnapshot.record(_ state: TrayContentState, at url: URL = url) -> Change`
  - `DrawerSnapshot.load(from url: URL = url) -> Payload?`

- [ ] **Step 1: テストを書く**

`Tests/DrawerSnapshotTests.swift`:

```swift
import XCTest
@testable import IslandTray

final class DrawerSnapshotTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("drawer-snapshot.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func slot(_ i: Int) -> TrayContentState.DrawerSlot {
        .init(symbol: "app", name: "App\(i)", launch: "islandtray://launch?item=\(i)", hasIcon: true)
    }

    private func item(_ i: Int) -> TrayItem {
        TrayItem(id: UUID(), name: "f\(i).txt", uti: "public.plain-text", size: 1, addedAt: Date(), ext: "txt")
    }

    private func drawerState() -> TrayContentState {
        TrayContentState.makeDrawer(
            weather: nil, slots: [slot(0), slot(1)],
            atlas: .init(jpeg: Data([1, 2, 3]), filled: [true, true]),
            view: .drawer, count: 0
        )
    }

    func testADrawerStateIsRecordedAndReadBack() {
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .written)
        let loaded = DrawerSnapshot.load(from: url)
        XCTAssertEqual(loaded?.slots.map(\.name), ["App0", "App1"])
        XCTAssertEqual(loaded?.atlas, Data([1, 2, 3]))
        XCTAssertEqual(loaded?.atlasOffset, 0)
    }

    func testTheSameStateIsNotRewritten() {
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .written)
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .unchanged)
    }

    func testATrayStateCarryingTheDrawerStartsAfterItsOwnTiles() {
        let state = TrayContentState.make(from: [item(0), item(1), item(2)], atlas: nil)
            .withDrawer([slot(0)], combined: nil, lockDrawer: false)
        XCTAssertEqual(DrawerSnapshot.record(state, at: url), .written)
        XCTAssertEqual(DrawerSnapshot.load(from: url)?.atlasOffset, 3)
    }

    func testTurningTheDrawerOffRemovesTheSnapshot() {
        XCTAssertEqual(DrawerSnapshot.record(drawerState(), at: url), .written)
        let off = TrayContentState.make(from: [], atlas: nil)
        XCTAssertFalse(off.drawerAvailable)
        XCTAssertEqual(DrawerSnapshot.record(off, at: url), .removed)
        XCTAssertNil(DrawerSnapshot.load(from: url))
        XCTAssertEqual(DrawerSnapshot.record(off, at: url), .unchanged)
    }
}
```

- [ ] **Step 2: 失敗を確認**

Run: `xcodegen generate && xcodebuild test -project IslandTray.xcodeproj -scheme IslandTray -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IslandTrayTests/DrawerSnapshotTests 2>&1 | tail -30`
Expected: `cannot find 'DrawerSnapshot' in scope`

- [ ] **Step 3: 実装**

`Sources/Shared/DrawerSnapshot.swift`:

```swift
import Foundation
import WidgetKit

/// The drawer as the island last drew it, kept by the widget extension for
/// its own Home Screen and Lock Screen widgets.
///
/// Nothing else can reach them: the free build has no App Group, so the app
/// cannot hand the extension a file. But the Live Activity's views are
/// evaluated in the extension's own process, with the slots and the icon
/// strip already inside the content state -- so the view records what it
/// was given, and the widgets read that back. The app never touches this.
enum DrawerSnapshot {
    struct Payload: Codable, Equatable {
        let slots: [TrayContentState.DrawerSlot]
        let atlas: Data?
        /// Where the drawer's tiles start in `atlas`: after the tray's own on
        /// a tray state, 0 on a drawer state. The island's own rule.
        let atlasOffset: Int
    }

    enum Change: Equatable { case written, removed, unchanged }

    /// The widget this feeds, for `reloadTimelines(ofKind:)`.
    static let widgetKind = "DrawerWidget"

    /// Inside whichever process asks -- the extension's own container when
    /// the extension does, which is the only one that ever reads it.
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IslandTray", isDirectory: true)
            .appendingPathComponent("drawer-snapshot.json")
    }

    static func payload(for state: TrayContentState) -> Payload? {
        guard let slots = state.drawer else { return nil }
        return Payload(slots: slots, atlas: state.atlas,
                       atlasOffset: state.view == .drawer ? 0 : state.recent.count)
    }

    /// Saves what the island was given. Writes only on a change, and only
    /// then asks the widget to reload, so a state the island redraws every
    /// few minutes costs nothing here.
    @discardableResult
    static func record(_ state: TrayContentState, at url: URL = url) -> Change {
        let fm = FileManager.default
        guard let payload = payload(for: state), let data = try? JSONEncoder().encode(payload) else {
            // Drawer turned off: the widget must not keep showing one.
            guard !state.drawerAvailable, fm.fileExists(atPath: url.path) else { return .unchanged }
            try? fm.removeItem(at: url)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
            return .removed
        }
        if (try? Data(contentsOf: url)) == data { return .unchanged }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            // Lock-screen-readable: the Live Activity is drawn, and this is
            // written, while the device is locked (see TrayContainer).
            try data.write(to: url, options: [.atomic, TrayContainer.lockScreenReadableWrite])
        } catch {
            return .unchanged
        }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        return .written
    }

    static func load(from url: URL = url) -> Payload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
```

- [ ] **Step 4: テストを通す**

Run: `xcodegen generate` の後、上と同じ（`DrawerSnapshotTests`）
Expected: `** TEST SUCCEEDED **`（4 件）

- [ ] **Step 5: コミット**

```bash
git add Sources/Shared/DrawerSnapshot.swift Tests/DrawerSnapshotTests.swift
git commit -m "feat: keep the island's drawer state for the widget extension's own widgets

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `DrawerIcon` の切り出しと Live Activity からの記録

**Files:**
- Create: `Sources/Widget/DrawerIcon.swift`
- Modify: `Sources/Widget/DrawerStrip.swift:22-29, 48-60`
- Modify: `Sources/Widget/TrayLiveActivity.swift:185`（`lockScreen(_:)` 先頭）

**Interfaces:**
- Consumes: `DrawerSnapshot.record(_:)`（Task 4）、`DrawerIconFiles.image(slot:)`、`AtlasSlicer.tiles(_:)`
- Produces: `DrawerIcon(slot: TrayContentState.DrawerSlot, index: Int, tiles: [UIImage], atlasOffset: Int = 0, symbolFont: Font = .title3): View`

- [ ] **Step 1: `DrawerIcon` を作る**

`Sources/Widget/DrawerIcon.swift`:

```swift
import SwiftUI

/// One drawer slot's picture, in the order the island has always used:
/// the full-resolution file (shared-container builds), then the slot's
/// atlas tile, then the kind's SF Symbol.
struct DrawerIcon: View {
    let slot: TrayContentState.DrawerSlot
    /// The slot's position in the island's drawer, which names its icon file.
    let index: Int
    let tiles: [UIImage]
    /// Where the drawer's tiles start in `tiles`.
    var atlasOffset = 0
    var symbolFont: Font = .title3

    var body: some View {
        if let file = DrawerIconFiles.image(slot: index) {
            Image(uiImage: file).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else if slot.hasIcon, tiles.indices.contains(atlasOffset + index) {
            Image(uiImage: tiles[atlasOffset + index])
                .resizable().interpolation(.high).aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: slot.symbol).font(symbolFont).foregroundStyle(.white)
        }
    }
}
```

- [ ] **Step 2: `DrawerStrip` が `DrawerIcon` を使う**

`Sources/Widget/DrawerStrip.swift` の `body` 内 2 箇所の `iconImage(index, tiles)` を
`DrawerIcon(slot: slot, index: index, tiles: tiles, atlasOffset: atlasOffset)` に置き換え、
`@ViewBuilder private func iconImage(_ index: Int, _ tiles: [UIImage]) -> some View { … }` 全体を削除する。

結果の `body`:

```swift
    var body: some View {
        let tiles = AtlasSlicer.tiles(atlas)
        HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                if let url = URL(string: slot.launch) {
                    Link(destination: url) {
                        tile(slot.name) { DrawerIcon(slot: slot, index: index, tiles: tiles, atlasOffset: atlasOffset) }
                    }
                } else {
                    tile(slot.name) { DrawerIcon(slot: slot, index: index, tiles: tiles, atlasOffset: atlasOffset) }
                }
            }
        }
    }
```

- [ ] **Step 3: Live Activity から記録**

`Sources/Widget/TrayLiveActivity.swift` の `lockScreen(_:)` を次のように変える（先頭に 1 行追加、コメント付き）:

```swift
    @ViewBuilder private func lockScreen(_ state: TrayContentState) -> some View {
        // The Lock Screen presentation is evaluated on every update, in this
        // extension's process: the one place the Home/Lock Screen drawer
        // widgets can learn what the drawer holds (see DrawerSnapshot).
        let _ = DrawerSnapshot.record(state)
        if state.hideLockScreen {
```

（以降の分岐は変更なし。）

- [ ] **Step 4: 両スキームでビルド**

Run:
```bash
xcodegen generate
xcodebuild build -project IslandTray.xcodeproj -scheme IslandTray -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
xcodebuild build -project IslandTray.xcodeproj -scheme 'IslandTray (Free)' -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```
Expected: 両方 `** BUILD SUCCEEDED **`

- [ ] **Step 5: 回帰テスト**

Run: `xcodebuild test -project IslandTray.xcodeproj -scheme IslandTray -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:IslandTrayTests/LockScreenDrawerIconsTests -only-testing:IslandTrayTests/TrayContentStateDrawerTests 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: コミット**

```bash
git add Sources/Widget/DrawerIcon.swift Sources/Widget/DrawerStrip.swift Sources/Widget/TrayLiveActivity.swift
git commit -m "refactor: one drawer icon view; record the drawer when the island draws it

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: `DrawerWidget` — ホーム/ロック画面ウィジェット

**Files:**
- Create: `Sources/Widget/DrawerWidget.swift`
- Modify: `Sources/Widget/IslandTrayWidgetBundle.swift`
- Modify: `Resources/Localization/{en,ja,ko}.lproj/Localizable.strings`（`widget.drawer.name` / `.desc` / `.empty`）

**Interfaces:**
- Consumes: `DrawerSnapshot.load()`, `DrawerSnapshot.widgetKind`, `DrawerSnapshot.Payload`（Task 4）、`DrawerStrip`, `DrawerIcon`（Task 5）、`AtlasSlicer.tiles(_:)`、`TrayIDs.drawerURL`
- Produces: `DrawerWidget: Widget`

- [ ] **Step 1: 文字列**

- en:
  ```
  "widget.drawer.name" = "App Drawer";
  "widget.drawer.desc" = "The island's app drawer, on your Home and Lock Screen.";
  "widget.drawer.empty" = "Turn on the app drawer and refresh the island once";
  ```
- ja:
  ```
  "widget.drawer.name" = "アプリドロワー";
  "widget.drawer.desc" = "アイランドのアプリドロワーをホーム画面とロック画面に。";
  "widget.drawer.empty" = "アプリドロワーをオンにして、アイランドを一度更新してください";
  ```
- ko:
  ```
  "widget.drawer.name" = "앱 서랍";
  "widget.drawer.desc" = "아일랜드의 앱 서랍을 홈 화면과 잠금 화면에.";
  "widget.drawer.empty" = "앱 서랍을 켜고 아일랜드를 한 번 갱신하세요";
  ```

- [ ] **Step 2: ウィジェット**

`Sources/Widget/DrawerWidget.swift`:

```swift
import SwiftUI
import WidgetKit

/// The island's app drawer on the Home Screen and the Lock Screen, drawn
/// from `DrawerSnapshot` -- whatever the Live Activity was last given.
///
/// Medium is the island's own row: six tiles, each a `Link`. Small and the
/// Lock Screen families take a single tap target (WidgetKit allows no
/// `Link` there), so they show the first icons and open the app's drawer.
struct DrawerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DrawerSnapshot.widgetKind, provider: Provider()) { entry in
            DrawerWidgetView(payload: entry.payload)
        }
        .configurationDisplayName(L.s("widget.drawer.name"))
        .description(L.s("widget.drawer.desc"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }

    struct Entry: TimelineEntry {
        let date: Date
        let payload: DrawerSnapshot.Payload?
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry {
            Entry(date: .now, payload: .init(
                slots: (0..<4).map { _ in .init(symbol: "app.fill", name: "", launch: "", hasIcon: false) },
                atlas: nil, atlasOffset: 0
            ))
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(context.isPreview ? placeholder(in: context) : Entry(date: .now, payload: DrawerSnapshot.load()))
        }

        /// `.never`: the snapshot is rewritten by the Live Activity, and that
        /// write is what reloads this timeline.
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now, payload: DrawerSnapshot.load())], policy: .never))
        }
    }
}

struct DrawerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let payload: DrawerSnapshot.Payload?

    private var isAccessory: Bool {
        family == .accessoryRectangular || family == .accessoryCircular
    }

    var body: some View {
        Group {
            if let payload, !payload.slots.isEmpty {
                content(payload)
            } else {
                empty
            }
        }
        // The Lock Screen draws its own vibrant material behind accessories;
        // the Home Screen gets the island's black.
        .containerBackground(for: .widget) {
            if isAccessory { Color.clear } else { Color.black.opacity(0.85) }
        }
    }

    @ViewBuilder private func content(_ payload: DrawerSnapshot.Payload) -> some View {
        switch family {
        case .systemMedium:
            DrawerStrip(slots: payload.slots, atlas: payload.atlas, side: 56, atlasOffset: payload.atlasOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "square.grid.2x2.fill").font(.title3)
            }
            .widgetURL(TrayIDs.drawerURL)
        default:
            grid(payload, columns: family == .systemSmall ? 2 : 4)
                .widgetURL(TrayIDs.drawerURL)
        }
    }

    /// The first four slots as tiles with no names: a glance, and one tap
    /// into the full drawer.
    private func grid(_ payload: DrawerSnapshot.Payload, columns: Int) -> some View {
        let tiles = AtlasSlicer.tiles(payload.atlas)
        let shown = Array(payload.slots.prefix(4).enumerated())
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(shown, id: \.offset) { index, slot in
                Color.white.opacity(0.08)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { DrawerIcon(slot: slot, index: index, tiles: tiles, atlasOffset: payload.atlasOffset) }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var empty: some View {
        Text(L.s("widget.drawer.empty"))
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .widgetURL(TrayIDs.drawerURL)
    }
}
```

- [ ] **Step 3: バンドルに登録**

`Sources/Widget/IslandTrayWidgetBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct IslandTrayWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrayLiveActivity()
        DrawerWidget()
    }
}
```

- [ ] **Step 4: 両スキームでビルド**

Run:
```bash
xcodegen generate
xcodebuild build -project IslandTray.xcodeproj -scheme IslandTray -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
xcodebuild build -project IslandTray.xcodeproj -scheme 'IslandTray (Free)' -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```
Expected: 両方 `** BUILD SUCCEEDED **`

- [ ] **Step 5: シミュレータで目視**

`IslandTray` スキームを iPhone 17 シミュレータで実行し、設定でアプリドロワーをオンにしてショートカットを 2 つ以上追加 → ホームに戻り、長押し → ウィジェット追加 → 「IslandTray」の「アプリドロワー」を Small と Medium で置く。Medium にタイル、Small に 2×2 グリッドが出ること（アイランドが更新されるまでは「アプリドロワーをオンにして…」の文言）。ロック画面は実機で確認。

- [ ] **Step 6: 全テスト**

Run: `xcodebuild test -project IslandTray.xcodeproj -scheme IslandTray -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: コミット**

```bash
git add Sources/Widget/DrawerWidget.swift Sources/Widget/IslandTrayWidgetBundle.swift Resources/Localization
git commit -m "feat: app-drawer widgets for the Home Screen and the Lock Screen

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: バージョンと変更履歴（タグは打たない）

**Files:**
- Modify: `project.yml:17-18`
- Modify: `CHANGELOG.md`, `CHANGELOG.ja.md`（`## [1.9.6]` の直前に挿入）

- [ ] **Step 1: バージョン**

`project.yml`:
```yaml
    MARKETING_VERSION: "1.10.0"
    CURRENT_PROJECT_VERSION: "30"
```

- [ ] **Step 2: CHANGELOG.md**

`## [1.9.6] — 2026-09-30` の直前に:

```markdown
## [1.10.0] — 2026-10-03

### Added
- **App Drawer widgets.** The island's app drawer is now available as a Home
  Screen widget (small: four icons, tap for the drawer; medium: six tiles,
  each launching directly) and as a Lock Screen widget (rectangular and
  circular, tap for the drawer). Works on the AltStore / SideStore build too:
  the widget shows whatever the island last drew, so it fills in the first
  time the island is refreshed after the drawer is turned on.

### Fixed
- A file or folder that was still in iCloud Drive, not yet on the device, is
  now downloaded before it is taken into the tray — from a drop, the share
  sheet, a shortcut or the Files inbox. It used to arrive as an empty
  placeholder, and because of that the "same file is already in the tray"
  check never recognised it either.
- While a drop is still being taken in, the tray says so.
```

- [ ] **Step 3: CHANGELOG.ja.md**

`## [1.9.6] — 2026-09-30` の直前に:

```markdown
## [1.10.0] — 2026-10-03

### 追加
- **アプリドロワーのウィジェット。** アイランドのアプリドロワーをホーム画面
  （小: アイコン 4 つ、タップでドロワーへ / 中: 6 枚のタイルをそれぞれ直接起動）と
  ロック画面（長方形・円形、タップでドロワーへ）のウィジェットとして置けます。
  AltStore / SideStore 版でも動きます。ウィジェットはアイランドが最後に描いた内容を
  映すので、ドロワーをオンにした後アイランドが一度更新されると表示されます。

### 修正
- iCloud Drive 上にあってまだ端末にないファイル/フォルダを、トレイに取り込む前に
  ダウンロードするようにしました（ドロップ・共有シート・ショートカット・ファイルの
  受信箱すべて）。これまでは空のプレースホルダのまま取り込まれ、そのせいで
  「同じファイルがすでにトレイにあります」の確認も効きませんでした。
- ドロップの取り込み中は、その旨をトレイに表示します。
```

- [ ] **Step 4: 生成とビルド確認**

Run:
```bash
xcodegen generate 2>&1 | tail -2
xcodebuild build -project IslandTray.xcodeproj -scheme 'IslandTray (Free)' -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: コミット**

```bash
git add project.yml CHANGELOG.md CHANGELOG.ja.md
git commit -m "release: 1.10.0 notes and version

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## 実機でしか確認できないこと（実装後にユーザーへ依頼）

1. ファイル App で iCloud Drive の項目を「ダウンロードを削除」→ IslandTray にドロップ → 「取り込み中…」→ 実サイズで取り込まれる → 同じ項目を再ドロップ → 「同じファイルがすでにトレイにあります」。フォルダでも同じ。
2. ロック画面ウィジェット（長方形・円形）の表示とタップ。
3. アイランドのドロワー構成を変えた後、ホームウィジェットが追従すること。

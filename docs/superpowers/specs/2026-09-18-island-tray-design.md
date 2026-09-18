# IslandTray 設計仕様書

- 作成日: 2026-09-18
- 対象: iOS / iPadOS 17.0 以降（ユニバーサル）。本実装で使う API はすべて iOS 17.0 で揃う。`.transient`（2.2 節）のみ iOS 18.0 以降だが本実装では使わない
- ステータス: レビュー待ち

---

## 1. 目的

ファイルや写真を一時的に「置いておく」ためのトレイ（シェルフ）アプリ。ユーザーはアプリ間ドラッグまたは共有シートで項目を預け、後から別のアプリへ取り出す。Dynamic Island の Live Activity がトレイの中身を常時表示し、トレイを呼び出す入口として機能する。

---

## 2. プラットフォーム制約（調査済みの事実）

設計の前提となる制約。すべて Apple 公式ドキュメントで確認済み。

### 2.1 Dynamic Island へ直接ドロップすることはできない

Live Activity のビューは Widget Extension 内でアーカイブされたスナップショットとして別プロセスでレンダリングされる。許可されている操作は次の 3 つのみ:

1. タップ → アプリを起動（`Link` / `widgetURL(_:)`）
2. 長押し → 拡張表示（expanded presentation）
3. `Button` / `Toggle` + `AppIntent`

`dropDestination` / `UIDropInteraction` はアーカイブ時に失われる。また「各 Live Activity は独自のサンドボックスで動作し、ウィジェットと異なりネットワークアクセスや位置情報の更新を受け取れない」と明記されている。

検討して却下した迂回路:

| 案 | 却下理由 |
| --- | --- |
| システム全体のドラッグセッション検知 | `UIDragSession` はドラッグ元アプリと、フォアグラウンドで可視なドロップターゲットからしか観測できない。グローバル API は存在しない |
| 他アプリ上へのオーバーレイ描画 | iOS に Android の `SYSTEM_ALERT_WINDOW` に相当する仕組みはない |
| PiP ウィンドウをドロップターゲットにする | PiP はシステムが動画レイヤーを描画するもので、ビュー階層ではない。ドロップインタラクションを付けられない。動画以外の用途は審査で却下される |
| `UISpringLoadedInteraction` | 自アプリのビュー内でのみ動作する |
| iOS 26 の新 API | 予約 Live Activity、transient スタイル等が追加されたが、ドロップ関連はない |

### 2.2 一方で「展開される」演出は実現できる

`Activity.request(attributes:content:pushType:style:)` に `.transient`（iOS 18.0+）を渡すと、Live Activity は**最初から拡張表示の状態**で Dynamic Island に現れる。ミュージックアプリが再生開始時に AirPlay 出力先を選ばせるあの挙動と同じもの。Dynamic Island の外側をタップするか折りたたむと自動的に終了する。

### 2.3 Live Activity は 8 時間で終了するが、再起動できる

- Dynamic Island からは 8 時間で自動的に消える（ロック画面にはさらに最大 4 時間残る）。
- 通常、開始にはアプリがフォアグラウンドである必要がある。
- ただし `LiveActivityIntent`（iOS 17.0+）の `perform()` 内からは**バックグラウンドでも開始できる**。「システムがインテントを実行するとき、アプリを開かずにアプリプロセスを起動し、インテントを実行して Live Activity を開始する」。
- App Intents は Shortcuts に公開されるため、時刻トリガーのオートメーションから 8 時間ごとに呼び出せば 24 時間維持できる。

### 2.4 その他

- `ContentState` のエンコード後サイズ上限は **4KB**。画像データを直接載せることはできない。
- App Group は**有料の Apple Developer Program が必須**。無料の Personal Team では使えない。
- iPad に Dynamic Island はない。Live Activity はロック画面にのみ表示される。代わりに Split View / Stage Manager で本来のドラッグ＆ドロップが成立する。

---

## 3. スコープ

### 含むもの

- アプリ間ドラッグによる取り込み（アプリ全体をドロップターゲットにする）
- 共有シート拡張による取り込み（有料アカウント時）
- 横スクロールのサムネイル一覧
- ドラッグによる取り出し、共有シートによる取り出し、削除
- Live Activity / Dynamic Island 表示
- Shortcuts オートメーションによる 24 時間維持
- iPhone / iPad ユニバーサル対応

### 含まないもの（YAGNI）

- iCloud 同期、複数デバイス間の共有
- フォルダ、タグ、並べ替え、検索
- ファイルのプレビュー・編集
- 項目の自動有効期限
- 100 件を超える規模を想定した最適化

---

## 4. アーキテクチャ

### 4.1 ターゲット構成

| ターゲット | 役割 | 有料アカウント |
| --- | --- | --- |
| `IslandTray` | アプリ本体。ドロップターゲット、一覧、取り出し | 不要 |
| `IslandTrayWidget` | Widget Extension。Live Activity のビュー定義 | 不要 |
| `IslandTrayShare` | Share Extension。共有シートからの取り込み | **必要** |
| App Group `group.com.pikare.islandtray` | 拡張とアプリ間のデータ共有 | **必要** |

Bundle ID のプレフィックス `com.pikare` は仮。実際の Team ID に合わせて変更する。

スキームは `IslandTray` と `IslandTray (Free)` の 2 つを用意する。詳細は第 8 節。

### 4.2 データモデル

項目は**コピーとして**保存する。参照だけを保持しない理由は 2 つある。ドラッグで受け取った項目は寿命が短く、写真アプリの項目は元のパスへのアクセス権がない。

```
<container>/
  Items/<uuid>.<ext>        // 実体のコピー
  Thumbs/<uuid>.png         // サムネイル
  items.json                // メタデータ
```

`<container>` は App Group コンテナ。App Group が使えない場合はアプリのサンドボックス内 Application Support にフォールバックする。この切り替えは `TrayStore` の 1 箇所に閉じる。

`items.json` の 1 項目:

```json
{
  "id": "UUID",
  "name": "元のファイル名",
  "uti": "public.jpeg",
  "size": 123456,
  "addedAt": "2026-09-18T12:00:00Z",
  "ext": "jpeg"
}
```

SwiftData や SQLite は使わない。想定規模は数十件で、JSON ファイル 1 つで十分。

サムネイルは `QuickLookThumbnailing` の `QLThumbnailGenerator` で生成する。ファイルアプリが使っているのと同じ API なので、「ファイルアプリに出てくるアイコンそのまま」という要件はこれで満たされる。独自のアイコンセットは作らない。

### 4.3 コンポーネント

境界を小さく保つため、以下の単位に分ける。

| 型 | 責務 | 依存 |
| --- | --- | --- |
| `TrayItem` | 1 項目のメタデータ。`Codable` な値型 | なし |
| `TrayStore` | コンテナの読み書き。追加・削除・一覧。`items.json` の永続化 | Foundation のみ |
| `ThumbnailService` | UTI とファイル URL からサムネイル PNG を生成・キャッシュ | QuickLookThumbnailing |
| `TrayActivityController` | Live Activity の開始・更新・終了。`ContentState` の組み立てと 4KB 制約の担保 | ActivityKit, TrayStore |
| `TrayView` | 横スクロール一覧、ドロップターゲット、取り出し UI | SwiftUI, TrayStore |
| `RefreshTrayActivityIntent` | `LiveActivityIntent`。Live Activity を作り直す | AppIntents, TrayActivityController |
| `IslandTrayLiveActivity` | Widget Extension 側のビュー定義（compact / minimal / expanded / ロック画面） | WidgetKit, ActivityKit |

`TrayItem` / `TrayStore` / `TrayActivityAttributes` はアプリ本体・Share Extension・Widget Extension の 3 ターゲットから参照される。共有フレームワークのターゲットは作らず、同じソースファイルを 3 ターゲットの Compile Sources に追加する方式にする（ファイル数が少なく、フレームワークの署名と埋め込み設定を増やさないため）。

書き込みはアプリ本体と Share Extension の両方から起こりうるので、`NSFileCoordinator` で `items.json` の読み書きを調停する。

---

## 5. 主要フロー

### 5.1 ドラッグで取り込む（主経路）

1. ユーザーが他アプリで項目を長押しして持ち上げる。
2. 指で保持したまま Dynamic Island をタップする。
3. `widgetURL` の `islandtray://drop` により IslandTray が起動し、全画面がドロップ受付状態になる。
4. ユーザーが指を離して項目をドロップする。
5. `TrayStore` がコンテナへコピーし、`ThumbnailService` がサムネイルを生成し、`TrayActivityController` が Live Activity を更新する。

ステップ 2〜3 は**実機検証が必要な仮定**である（第 11 節）。

ドロップ後にアプリが自らホーム画面へ戻ることはできない（iOS アプリは自身をバックグラウンドへ送れない）。ユーザーがスワイプして戻る。この摩擦は受け入れる。

### 5.2 共有シートで取り込む（副経路、有料アカウント時）

共有シートから `IslandTrayShare` を選ぶと、拡張が App Group コンテナへ直接コピーして `items.json` を更新する。拡張プロセスからは Live Activity を開始できないため、次にアプリがフォアグラウンドになった時点で表示が同期される。

### 5.3 iPad での取り込み

Split View または Stage Manager で IslandTray を並べて表示し、ドラッグして直接ドロップする。アプリ側のコードは iPhone と共通で、追加実装は不要。

### 5.4 取り出す

- カードに `.draggable()` を付け、他アプリへドラッグして渡す。
- 長押しのコンテキストメニューから `ShareLink` で共有、または削除。

---

## 6. Live Activity 設計

`ContentState` には画像バイトを一切載せない。

```swift
struct TrayActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var count: Int
        var recent: [Preview]   // 最大 4 件
    }
    struct Preview: Codable, Hashable {
        var id: String          // サムネイルファイル名の導出に使う
        var symbol: String      // App Group が無い場合のフォールバック用 SF Symbol 名
    }
}
```

| 表示 | 内容 |
| --- | --- |
| compact leading | トレイアイコン |
| compact trailing | 件数 |
| minimal | 件数 |
| expanded | 直近 4 件のサムネイルを横並び＋件数。**スクロールは不可**（ウィジェットビューではジェスチャーが効かない） |
| ロック画面 | 直近 4 件＋件数＋アプリ名 |

サムネイルは App Group コンテナ内のファイルを Widget Extension が直接読む。App Group が使えない場合は UTI から導出した SF Symbol を表示する。

タップ時の遷移先は `widgetURL(URL(string: "islandtray://drop"))`。

Live Activity は項目の追加・削除のたびに `update(_:)` する。トレイが空になったら `end(_:dismissalPolicy: .immediate)` で終了する。

---

## 7. 24 時間維持

```swift
struct RefreshTrayActivityIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "トレイの表示を更新"
    func perform() async throws -> some IntentResult {
        await TrayActivityController.shared.restart()
        return .result()
    }
}
```

`restart()` は既存の Activity を `end` してから現在のトレイ状態で `request` し直す。これにより 8 時間の枠がリセットされる。

`AppShortcutsProvider` に登録し、Shortcuts アプリから「トレイの表示を更新」として直接選べるようにする。アプリ内の設定画面に、8 時間間隔（例: 07:00 / 15:00 / 23:00）の時刻オートメーションを「すぐに実行」で 3 つ作る手順を表示する。

アプリがフォアグラウンドになったときにも同じ `restart()` を通す。オートメーションが失敗しても、アプリを開けば復旧する。

---

## 8. アカウント種別による縮退

機能は有料アカウントを前提に一通り実装する。そのうえで、無料の Personal Team でもビルドして動かせるようにする。

**ソースは分岐させない。** 2 つのバージョンを作ると片方だけ修正するバグが必ず出る。コードベースは 1 つのまま、境界を次の 2 箇所だけに閉じ込める。

### 8.1 ビルド時の分岐（スキーム）

App Group は entitlement なので、無料アカウントで App Group を要求すると**実行時ではなくビルド時の署名エラー**になる。逆に言えば、entitlement さえ要求しなければ 3 つのターゲットはすべて無料アカウントでビルドできる。Share Extension も「ビルドできない」のではなく「共有コンテナに書けない」だけである。

したがってターゲット構成やスキームのビルド対象は一切変えず、**ビルド構成（configuration）ごとに entitlements ファイルを差し替えるだけ**にする。

| 構成 | Entitlements | スキーム |
| --- | --- | --- |
| `Debug` / `Release` | `Entitlements/Paid/*.entitlements`（App Group あり） | `IslandTray` |
| `Free-Debug` / `Free-Release` | `Entitlements/Free/*.entitlements`（App Group なし） | `IslandTray (Free)` |

両スキームとも 3 ターゲットすべてをビルドする。差分は `CODE_SIGN_ENTITLEMENTS` の値だけ。ソースファイルの分岐も Swift の `#if` も一切使わない。

無料構成では Share Extension が起動時に `TrayContainer.isShared` を確認し、`false` なら「共有シートからの追加は有料アカウントでのみ利用できます」と表示して何もせず終了する。黙って自分のサンドボックスへ書き込んでデータが消えるのを防ぐため。

なお無料の Personal Team は 1 週間あたりに作成できる App ID 数に制限がある。本プロジェクトは 3 つ（アプリ・Widget・Share）を使うため、バンドル ID の変更は最小限に留める。

### 8.2 実行時の分岐（1 箇所のみ）

```swift
// TrayStore.swift
static let container: URL = {
    FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        ?? applicationSupportURL   // App Group entitlement が無い場合
}()

static var isShared: Bool {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
}
```

`isShared` を見て判断するのは Live Activity のサムネイル表示のみ。`true` なら App Group 内のサムネイル画像、`false` なら UTI から導出した SF Symbol を出す。それ以外のコードは両方の構成で完全に同一。

### 8.3 結果

| 機能 | 無料 Personal Team | 有料 |
| --- | --- | --- |
| ドラッグでの取り込み | ○ | ○ |
| アプリ内の横スクロール一覧（**QuickLook の実サムネイル**） | ○ | ○ |
| 取り出し（ドラッグ / 共有 / 削除） | ○ | ○ |
| Live Activity / Dynamic Island | ○ | ○ |
| Shortcuts による 24 時間維持 | ○ | ○ |
| Dynamic Island 内の実サムネイル | × SF Symbol で代替 | ○ |
| 共有シートからの取り込み | × | ○ |
| 7 日ごとの再インストール | 必要 | 不要 |

アプリ内のサムネイルは無料アカウントでも実物が出る。アプリは自分のサンドボックスを読むだけで、App Group を必要としないため。SF Symbol への縮退は Dynamic Island の中だけに限られる。

有料アカウントが有効になったあとの移行作業は、スキームを `IslandTray` に切り替えることだけ。`TrayStore.container` が自動的に App Group を指し、Share Extension がビルド対象に入る。既存のトレイの中身は移行が必要なため、初回起動時に旧コンテナから新コンテナへコピーする処理を `TrayStore.migrateIfNeeded()` に置く。

---

## 9. エラー処理

| 状況 | 対応 |
| --- | --- |
| Live Activity の開始失敗（同時実行数の上限、`visibility` エラー等） | 例外を握りつぶさず、アプリ内にバナーで理由を表示する。トレイの機能自体は継続する |
| `ContentState` が 4KB を超える | `recent` を 4 件に固定し、エンコード後のサイズを組み立て時にアサートする。超えた場合は件数のみの最小状態へ縮退する |
| サムネイル生成の失敗 | UTI から導出した SF Symbol を表示する。項目の取り込み自体は成功として扱う |
| ドロップされた項目のコピー失敗（容量不足等） | その項目だけを失敗として通知し、他の項目は取り込む |
| `items.json` の破損 | 破損ファイルを退避し、`Items/` の実体から一覧を再構築する |
| Live Activity が未許可 | 設定への導線を表示する。アプリ本体は通常どおり動作する |

ドロップされたデータは外部由来の入力として扱う。ファイル名はパス区切り文字を除去して正規化し、コンテナ内のパスは必ず UUID から組み立てる（元のファイル名をパスに使わない）。

---

## 10. 検証方針

自動テスト（`TrayStoreTests`、フレームワークなし、`XCTest` のみ）:

- `TrayStore` の追加・削除・一覧の往復。同名ファイルを複数追加しても衝突しないこと。
- `items.json` が破損した状態からの再構築。
- `ContentState` のエンコード後サイズが 4KB 未満であること（4 件ぶんの最大長ファイル名で検証）。
- ファイル名の正規化（`../` を含む名前がコンテナ外へ出ないこと）。

実機での手動確認:

- 第 11 節のスパイク項目。
- Shortcuts の無人オートメーションから Live Activity が実際に再起動されるか（一晩放置して確認）。
- iPad の Split View でのドラッグ＆ドロップ。

---

## 11. Phase 0: スパイク（最優先）

設計全体が 1 つの未検証の仮定に依存している。**ドラッグセッションの進行中に Dynamic Island をタップするとアプリが起動し、そのドラッグセッションが生きたままか。**

空のアプリ＋最小の Live Activity＋全画面ドロップターゲットだけを作り、実機で確認する。

1. ドラッグ中に Dynamic Island をタップしてアプリが前面に来るか。
2. 来た場合、ドラッグセッションが維持されていてドロップできるか。
3. `.transient` スタイルでの展開演出がそのタイミングで自然か。
4. 一連の流れが手に馴染むか、それとも共有シートのほうが速いか。

**1 が成立しない場合**: Dynamic Island は表示専用に降格し、取り込みの主経路を「アプリを切り替えてからドロップ」と共有シートにする。第 4 節以降のアプリ本体の設計はそのまま有効で、影響は第 5.1 節のみ。

---

## 12. 実装順序

1. Phase 0 スパイク（上記）
2. `TrayItem` / `TrayStore` / `ThumbnailService` とテスト
3. `TrayView`（ドロップ、横スクロール一覧、取り出し、削除）
4. `TrayActivityController` と Widget Extension のビュー
5. `RefreshTrayActivityIntent` と `AppShortcutsProvider`、設定画面の手順表示
6. `IslandTrayShare`（Share Extension）と App Group 構成、および `IslandTray (Free)` スキーム

6 は有料アカウントの取得を待たずに実装する。無料アカウントの間は `IslandTray (Free)` スキームで実機確認を行い、有料アカウントが有効になった時点で `IslandTray` スキームに切り替えて Share Extension と App Group の動作を確認する。

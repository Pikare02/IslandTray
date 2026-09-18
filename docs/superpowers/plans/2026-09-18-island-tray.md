# IslandTray 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ファイルや写真を一時的に預けておくトレイアプリを作る。Dynamic Island の Live Activity が中身を常時表示し、トレイを呼び出す入口として機能する。

**Architecture:** SwiftUI のアプリ本体、Live Activity 用の Widget Extension、共有シート用の Share Extension の 3 ターゲット。項目はコンテナへコピーし、メタデータは `items.json` 1 ファイルで管理する。App Group が使えるかどうかは `TrayContainer` 1 箇所で実行時に吸収し、ソースは分岐させない。

**Tech Stack:** Swift 6 / SwiftUI / ActivityKit / WidgetKit / AppIntents / QuickLookThumbnailing / XcodeGen / XCTest

設計仕様: [`docs/superpowers/specs/2026-09-18-island-tray-design.md`](../specs/2026-09-18-island-tray-design.md)

## Global Constraints

- デプロイメントターゲットは **iOS 17.0**。本実装で使う API はすべて iOS 17.0 で揃う（`@Observable`、`LiveActivityIntent`、`ContentUnavailableView`、`scrollClipDisabled`）。`.transient` のみ iOS 18.0 以降だが、Task 2 のスパイクで一度試すだけで本実装では使わないため、そこだけ `#available` で囲う。
- テストとビルドの確認は **iPhone 18 Pro シミュレータ**（Dynamic Island あり）で行う。`-destination` に OS は固定しない。実機が必要なのは Task 2 のスパイクと Task 10 の実機確認だけ。
- ユニバーサルアプリ（iPhone / iPad 両対応）。`TARGETED_DEVICE_FAMILY = "1,2"`。
- Swift の条件付きコンパイル（`#if`）による有料・無料の分岐は**禁止**。差分は entitlements ファイルのみ。
- `ContentState` のエンコード後サイズは **4096 バイト未満**。画像データを載せてはならない。
- Live Activity の `recent` は**最大 4 件**。
- コード内のコメントは**英語**で書く。
- 新しい依存ライブラリを追加しない。XcodeGen はプロジェクト生成用のビルドツールであり、アプリの依存ではない。
- バンドル ID のプレフィックスは `com.pikare`。無料アカウントは 1 週間あたりの App ID 作成数に制限があるため、**バンドル ID を後から変更しない**。
- 項目のコンテナ内パスは必ず UUID から組み立てる。元のファイル名をパスに使わない。
- git コミットメッセージの末尾に `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` を付ける。

## ファイル構成

```
IslandTray/
├── project.yml                              # XcodeGen 定義
├── Entitlements/
│   ├── Paid/{App,Widget,Share}.entitlements # App Group あり
│   └── Free/{App,Widget,Share}.entitlements # App Group なし（空）
├── Sources/
│   ├── Shared/                              # 3 ターゲット全部にコンパイル
│   │   ├── TrayIDs.swift                    # バンドル ID / App Group ID / URL スキーム定数
│   │   ├── FilenameSanitizer.swift          # 外部由来のファイル名の正規化
│   │   ├── TrayContainer.swift              # コンテナ URL の解決と isShared 判定
│   │   ├── TrayItem.swift                   # 1 項目のメタデータ（値型）
│   │   ├── TrayStore.swift                  # items.json の読み書きと項目の追加・削除
│   │   ├── TrayContentState.swift           # Live Activity の動的データ（Foundation のみ）
│   │   └── TrayActivityAttributes.swift     # ActivityAttributes 適合
│   ├── App/
│   │   ├── IslandTrayApp.swift              # @main、URL スキーム受け
│   │   ├── TrayModel.swift                  # 画面の状態。Store と Activity を束ねる
│   │   ├── TrayView.swift                   # 横スクロール一覧とドロップターゲット
│   │   ├── TrayCardView.swift               # 1 枚のカード
│   │   ├── DropReceiver.swift               # NSItemProvider → TrayStore への取り込み
│   │   ├── ThumbnailService.swift           # QLThumbnailGenerator によるサムネイル生成
│   │   ├── TrayActivityController.swift     # Live Activity の開始・更新・終了
│   │   ├── RefreshTrayActivityIntent.swift  # LiveActivityIntent
│   │   ├── TrayShortcuts.swift              # AppShortcutsProvider
│   │   └── SetupGuideView.swift             # ショートカット設定手順の表示
│   ├── Widget/
│   │   ├── IslandTrayWidgetBundle.swift     # @main
│   │   ├── TrayLiveActivity.swift           # ActivityConfiguration と DynamicIsland
│   │   └── TrayPreviewStrip.swift           # サムネイル横並び（アイランド・ロック画面共用）
│   └── Share/
│       └── ShareViewController.swift        # 共有シートからの取り込み
├── Resources/
│   ├── App/{Info.plist,Assets.xcassets}
│   ├── Widget/Info.plist
│   └── Share/Info.plist
└── Tests/
    ├── FilenameSanitizerTests.swift
    ├── TrayStoreTests.swift
    └── TrayContentStateTests.swift
```

`Sources/Shared/` の全ファイルは 3 ターゲットすべての Compile Sources に含める（共有フレームワークのターゲットは作らない）。テストターゲットにも含める。

---

## Task 1: プロジェクト雛形と 2 構成 2 スキーム


XcodeGen でプロジェクトを生成し、空のアプリ・Widget・Share の 3 ターゲットが有料構成と無料構成の両方でビルドできる状態にする。Task 2 の実機スパイクに必要な最小限（全画面ドロップターゲットと最小の Live Activity）もここに含める。

**Files:**
- Create: `project.yml`
- Create: `Entitlements/Paid/App.entitlements`, `Entitlements/Paid/Widget.entitlements`, `Entitlements/Paid/Share.entitlements`
- Create: `Entitlements/Free/App.entitlements`, `Entitlements/Free/Widget.entitlements`, `Entitlements/Free/Share.entitlements`
- Create: `Sources/Shared/TrayIDs.swift`
- Create: `Sources/App/IslandTrayApp.swift`, `Sources/App/TrayView.swift`
- Create: `Sources/Widget/IslandTrayWidgetBundle.swift`, `Sources/Widget/TrayLiveActivity.swift`
- Create: `Sources/Shared/TrayActivityAttributes.swift`, `Sources/Shared/TrayContentState.swift`
- Create: `Sources/Share/ShareViewController.swift`
- Create: `Resources/App/Info.plist`, `Resources/Widget/Info.plist`, `Resources/Share/Info.plist`
- Create: `.gitignore`

**Interfaces:**
- Consumes: なし
- Produces: `TrayIDs.appGroupID: String`, `TrayIDs.urlScheme: String`, `TrayIDs.dropURL: URL`, `TrayContentState`（`count: Int`, `recent: [TrayContentState.Preview]`）, `TrayActivityAttributes`

- [ ] **Step 1: XcodeGen をインストールする**

```bash
brew install xcodegen
```

期待: `xcodegen --version` がバージョンを表示する。

- [ ] **Step 2: `.gitignore` を作る**

```
.DS_Store
*.xcodeproj/
!project.yml
build/
DerivedData/
xcuserdata/
```

`.xcodeproj` は `project.yml` から再生成できるためコミットしない。

- [ ] **Step 3: entitlements ファイルを 6 つ作る**

`Entitlements/Paid/App.entitlements`（Widget.entitlements と Share.entitlements も**同じ内容**でよい。3 つとも同じ App Group に属する必要があるため）:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>IslandTray</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionAttributes</key>
		<dict>
			<key>NSExtensionActivationRule</key>
			<dict>
				<key>NSExtensionActivationSupportsFileWithMaxCount</key>
				<integer>20</integer>
				<key>NSExtensionActivationSupportsImageWithMaxCount</key>
				<integer>20</integer>
				<key>NSExtensionActivationSupportsMovieWithMaxCount</key>
				<integer>20</integer>
				<key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
				<integer>1</integer>
			</dict>
		</dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.share-services</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
	</dict>
</dict>
</plist>
```

`Entitlements/Free/App.entitlements`（Widget / Share も同内容）:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 4: `project.yml` を書く**

```yaml
name: IslandTray
options:
  bundleIdPrefix: com.pikare
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true

# Note: targets deliberately have no `info:` block. An `info:` block makes
# XcodeGen generate its own Info.plist and overwrite the hand-authored ones,
# destroying NSSupportsLiveActivities, the URL scheme and the share rules.
# INFOPLIST_FILE + GENERATE_INFOPLIST_FILE: NO is what wires them up.
configs:
  Debug: debug
  Release: release
  Free-Debug: debug
  Free-Release: release

settings:
  base:
    SWIFT_VERSION: "6.0"
    TARGETED_DEVICE_FAMILY: "1,2"
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
    CODE_SIGN_STYLE: Automatic
    GENERATE_INFOPLIST_FILE: NO
    ENABLE_USER_SCRIPT_SANDBOXING: YES

targets:
  IslandTray:
    type: application
    platform: iOS
    sources:
      - Sources/Shared
      - Sources/App
      - path: Resources/App/Assets.xcassets
        buildPhase: resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pikare.islandtray
        INFOPLIST_FILE: Resources/App/Info.plist
      configs:
        Debug:        { CODE_SIGN_ENTITLEMENTS: Entitlements/Paid/App.entitlements }
        Release:      { CODE_SIGN_ENTITLEMENTS: Entitlements/Paid/App.entitlements }
        Free-Debug:   { CODE_SIGN_ENTITLEMENTS: Entitlements/Free/App.entitlements }
        Free-Release: { CODE_SIGN_ENTITLEMENTS: Entitlements/Free/App.entitlements }
    dependencies:
      - target: IslandTrayWidget
      - target: IslandTrayShare

  IslandTrayWidget:
    type: app-extension
    platform: iOS
    sources:
      - Sources/Shared
      - Sources/Widget
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pikare.islandtray.widget
        INFOPLIST_FILE: Resources/Widget/Info.plist
      configs:
        Debug:        { CODE_SIGN_ENTITLEMENTS: Entitlements/Paid/Widget.entitlements }
        Release:      { CODE_SIGN_ENTITLEMENTS: Entitlements/Paid/Widget.entitlements }
        Free-Debug:   { CODE_SIGN_ENTITLEMENTS: Entitlements/Free/Widget.entitlements }
        Free-Release: { CODE_SIGN_ENTITLEMENTS: Entitlements/Free/Widget.entitlements }

  IslandTrayShare:
    type: app-extension
    platform: iOS
    sources:
      - Sources/Shared
      - Sources/Share
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pikare.islandtray.share
        INFOPLIST_FILE: Resources/Share/Info.plist
      configs:
        Debug:        { CODE_SIGN_ENTITLEMENTS: Entitlements/Paid/Share.entitlements }
        Release:      { CODE_SIGN_ENTITLEMENTS: Entitlements/Paid/Share.entitlements }
        Free-Debug:   { CODE_SIGN_ENTITLEMENTS: Entitlements/Free/Share.entitlements }
        Free-Release: { CODE_SIGN_ENTITLEMENTS: Entitlements/Free/Share.entitlements }

  IslandTrayTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests
    settings:
      base:
        # The base GENERATE_INFOPLIST_FILE: NO assumes a checked-in Info.plist,
        # which a unit test bundle does not need. Without this override the test
        # bundle fails to code sign.
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: IslandTray

schemes:
  IslandTray:
    build:
      targets: { IslandTray: all }
    run: { config: Debug }
    test: { config: Debug, targets: [IslandTrayTests] }
    archive: { config: Release }
  IslandTray (Free):
    build:
      targets: { IslandTray: all }
    run: { config: Free-Debug }
    test: { config: Free-Debug, targets: [IslandTrayTests] }
    archive: { config: Free-Release }
```

テストターゲットに `Sources/Shared` を含めてはならない。共有ソースは `IslandTray` 側で既にコンパイルされており、`@testable import IslandTray` で参照できる。両方に含めるとシンボルが二重定義になる。

- [ ] **Step 5: Info.plist を 3 つ作る**

`GENERATE_INFOPLIST_FILE: NO` のもとでは、Xcode は `CFBundleIdentifier` / `CFBundleExecutable` / `CFBundleName` / `CFBundlePackageType` / `CFBundleInfoDictionaryVersion` を自動で埋めない。これらが欠けるとシミュレータがバンドルのインストールを拒否する（`missing or invalid CFBundleExecutable`）。下のとおり明示的に書くこと。

`Resources/App/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>IslandTray</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSSupportsLiveActivities</key>
	<true/>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<true/>
	</dict>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.pikare.islandtray</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>islandtray</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

`Resources/Widget/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>IslandTrayWidget</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
```

`Resources/Share/Info.plist`（`NSExtensionActivationRule` は「ファイル・画像・動画・URL のいずれか 1 個以上」を受け付ける）:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>IslandTray</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.share-services</string>
		<key>NSExtensionPrincipalClass</key>
		<string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
		<key>NSExtensionAttributes</key>
		<dict>
			<key>NSExtensionActivationRule</key>
			<dict>
				<key>NSExtensionActivationSupportsFileWithMaxCount</key>
				<integer>20</integer>
				<key>NSExtensionActivationSupportsImageWithMaxCount</key>
				<integer>20</integer>
				<key>NSExtensionActivationSupportsMovieWithMaxCount</key>
				<integer>20</integer>
				<key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
				<integer>1</integer>
			</dict>
		</dict>
	</dict>
</dict>
</plist>
```

- [ ] **Step 6: 共有の定数を書く**

`Sources/Shared/TrayIDs.swift`:

```swift
import Foundation

/// Identifiers shared by the app and both extensions.
/// Keep these in sync with project.yml and the entitlements files.
enum TrayIDs {
    static let appGroupID = "group.com.pikare.islandtray"
    static let urlScheme = "islandtray"

    /// Deep link used by the Live Activity to bring the tray forward for a drop.
    static let dropURL = URL(string: "\(urlScheme)://drop")!
}
```

- [ ] **Step 7: Live Activity の型を書く**

`ContentState` は ActivityKit に依存しない素の `Codable` として定義する。こうするとサイズ検証のテストが Foundation だけで書ける。

`Sources/Shared/TrayContentState.swift`:

```swift
import Foundation

/// Dynamic data shown by the Live Activity.
/// Must stay under 4096 bytes when encoded, so it never carries image data —
/// only an id the widget uses to locate a thumbnail file, plus a symbol fallback.
struct TrayContentState: Codable, Hashable {
    /// Maximum number of previews the Dynamic Island can show at once.
    static let maxPreviews = 4

    struct Preview: Codable, Hashable {
        /// TrayItem id. The widget derives the thumbnail path from this.
        var id: String
        /// SF Symbol name, used when the App Group container is unavailable.
        var symbol: String
    }

    var count: Int
    var recent: [Preview]
}
```

`Sources/Shared/TrayActivityAttributes.swift`:

```swift
import ActivityKit

struct TrayActivityAttributes: ActivityAttributes {
    typealias ContentState = TrayContentState
}
```

- [ ] **Step 8: 最小のアプリを書く**

`Sources/App/IslandTrayApp.swift`:

```swift
import SwiftUI

@main
struct IslandTrayApp: App {
    var body: some Scene {
        WindowGroup {
            TrayView()
        }
    }
}
```

`Sources/App/TrayView.swift`（この時点ではドロップを数えるだけ。Task 8 で本実装に置き換える）:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct TrayView: View {
    @State private var isTargeted = false
    @State private var dropCount = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("IslandTray")
                .font(.largeTitle.bold())
            Text("dropped: \(dropCount)")
                .font(.title2.monospacedDigit())
            Text(isTargeted ? "release to drop" : "drag something here")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        .onDrop(of: [UTType.item], isTargeted: $isTargeted) { providers in
            dropCount += providers.count
            return true
        }
    }
}
```

- [ ] **Step 9: 最小の Live Activity を書く**

`Sources/Widget/IslandTrayWidgetBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct IslandTrayWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrayLiveActivity()
    }
}
```

`Sources/Widget/TrayLiveActivity.swift`（Task 9 で本実装に置き換える）:

```swift
import ActivityKit
import SwiftUI
import WidgetKit

struct TrayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrayActivityAttributes.self) { context in
            HStack {
                Image(systemName: "tray.full.fill")
                Text("\(context.state.count) items")
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.count) items")
                }
            } compactLeading: {
                Image(systemName: "tray.full.fill")
            } compactTrailing: {
                Text("\(context.state.count)")
            } minimal: {
                Text("\(context.state.count)")
            }
            .widgetURL(TrayIDs.dropURL)
        }
    }
}
```

- [ ] **Step 10: 最小の Share Extension を書く**

`Sources/Share/ShareViewController.swift`（Task 11 で本実装に置き換える）:

```swift
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extensionContext?.completeRequest(returningItems: nil)
    }
}
```

- [ ] **Step 11: Assets カタログを作る**

```bash
mkdir -p Resources/App/Assets.xcassets/AppIcon.appiconset
cat > Resources/App/Assets.xcassets/Contents.json <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
cat > Resources/App/Assets.xcassets/AppIcon.appiconset/Contents.json <<'JSON'
{
  "images" : [ { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
```

- [ ] **Step 12: プロジェクトを生成する**

```bash
xcodegen generate
```

期待: `Created project at .../IslandTray.xcodeproj` と表示される。

- [ ] **Step 13: 両方の構成でビルドが通ることを確認する**

無料構成（署名なしでコンパイルだけ確認する）:

```bash
xcodebuild build -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -configuration Free-Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

期待: `** BUILD SUCCEEDED **`

有料構成:

```bash
xcodebuild build -project IslandTray.xcodeproj -scheme "IslandTray" -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

期待: `** BUILD SUCCEEDED **`

- [ ] **Step 14: entitlements が構成ごとに切り替わっていることを確認する**

```bash
xcodebuild -project IslandTray.xcodeproj -target IslandTray -configuration Free-Debug -showBuildSettings 2>/dev/null | grep CODE_SIGN_ENTITLEMENTS
xcodebuild -project IslandTray.xcodeproj -target IslandTray -configuration Debug -showBuildSettings 2>/dev/null | grep CODE_SIGN_ENTITLEMENTS
```

期待: 前者が `Entitlements/Free/App.entitlements`、後者が `Entitlements/Paid/App.entitlements`。違っていれば `project.yml` の `configs` ブロックを直して `xcodegen generate` からやり直す。

- [ ] **Step 15: コミット**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: scaffold IslandTray project with paid/free build configurations

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Phase 0 実機スパイク（手動検証）


設計全体が 1 つの未検証の仮定に依存している。**ドラッグセッションの進行中に Dynamic Island をタップするとアプリが起動し、そのドラッグセッションが生きたままか。** ここで確かめる。

このタスクだけは自動テストがない。実機での手動確認であり、**結果を計画にそのまま書き戻す**ことが成果物になる。

**Files:**
- Modify: `Sources/App/TrayView.swift`（スパイク用に一時的な起動ボタンを足す）
- Modify: `Sources/App/IslandTrayApp.swift`
- Create: `docs/superpowers/plans/2026-09-18-island-tray-spike-result.md`

**Interfaces:**
- Consumes: `TrayActivityAttributes`, `TrayContentState`, `TrayIDs.dropURL`（Task 1）
- Produces: 実機での検証結果。Task 8 以降のドロップ導線の設計判断がこれに依存する。

- [ ] **Step 1: Live Activity を起動するボタンをアプリに足す**

`Sources/App/TrayView.swift` の `VStack` の末尾（`Text(isTargeted ? ...)` の直後）に追加する:

```swift
            Button("start live activity") {
                let attributes = TrayActivityAttributes()
                let state = TrayContentState(count: dropCount, recent: [])
                _ = try? Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil)
                )
            }
            .buttonStyle(.borderedProminent)
```

ファイル冒頭に `import ActivityKit` を足す。

- [ ] **Step 2: ディープリンクを受けたことが分かるようにする**

`Sources/App/IslandTrayApp.swift` を次の内容に差し替える:

```swift
import SwiftUI

@main
struct IslandTrayApp: App {
    @State private var openedFromIsland = false

    var body: some Scene {
        WindowGroup {
            TrayView()
                .overlay(alignment: .top) {
                    if openedFromIsland {
                        Text("opened from island")
                            .padding(8)
                            .background(.green.opacity(0.3), in: .capsule)
                    }
                }
                .onOpenURL { url in
                    openedFromIsland = (url == TrayIDs.dropURL)
                }
        }
    }
}
```

- [ ] **Step 3: 実機にインストールする**

iPhone を Mac に接続し、Xcode でチームを選んでから実行する。

```bash
xcodegen generate
open IslandTray.xcodeproj
```

Xcode で `IslandTray (Free)` スキームを選び、Signing & Capabilities で自分の Team を選択し、接続した実機を選んで実行する。

**注意:** 無料の Personal Team の場合、初回は iPhone の「設定 → 一般 → VPN とデバイス管理」で開発者を信頼する必要がある。

- [ ] **Step 4: 検証 1 — アイランドにライブアクティビティが出るか**

1. アプリで「start live activity」をタップする。
2. ホーム画面へスワイプする。
3. Dynamic Island にトレイアイコンと数字が出ることを確認する。

出ない場合: iPhone の「設定 → IslandTray → ライブアクティビティ」がオンか確認する。

- [ ] **Step 5: 検証 2 — ドラッグ中にアイランドをタップできるか（最重要）**

1. 写真アプリを開く。
2. 写真を 1 枚長押しして持ち上げる（指は離さない）。
3. **指を保持したまま**、もう一方の指でホームへスワイプする。
4. Dynamic Island を**タップ**する。
5. IslandTray が前面に来るか確認する。
6. 来た場合、持っている写真をアプリ上でドロップできるか確認する。
7. 「opened from island」バッジと「dropped: 1」が出るか確認する。

- [ ] **Step 6: 検証 3 — transient スタイルの演出**

Step 1 のボタンの `Activity.request` を次に差し替えて再実行し、Dynamic Island が最初から展開状態で現れるか確認する。

```swift
                if #available(iOS 18.0, *) {
                    _ = try? Activity.request(
                        attributes: attributes,
                        content: .init(state: state, staleDate: nil),
                        style: .transient
                    )
                }
```

確認後、この `#available` ブロックは消して元に戻す（トレイの常駐表示には `.transient` は使わない。アイランド外をタップすると終了してしまうため）。端末が iOS 17 の場合はこの検証だけ省略する。

- [ ] **Step 7: 結果を記録する**

`docs/superpowers/plans/2026-09-18-island-tray-spike-result.md` を作り、次の表を埋める。

```markdown
# Phase 0 スパイク結果

実施日:
端末 / iOS バージョン:

| 検証項目 | 結果 | メモ |
| --- | --- | --- |
| Dynamic Island に Live Activity が表示される | 〇 / × | |
| ドラッグ中にアイランドをタップするとアプリが前面に来る | 〇 / × | |
| 前面に来た後、ドラッグセッションが維持されドロップできる | 〇 / × | |
| `.transient` で展開状態から始まる | 〇 / × | |
| 一連の流れが実用的だと感じるか | 〇 / × | |

## 判定

- 2 と 3 が両方 〇 → 計画どおり進む。Task 8 のドロップ導線は Live Activity タップを主経路とする。
- 2 または 3 が × → Dynamic Island は表示専用に降格する。Task 8 のドロップ導線は「アプリを切り替えてからドロップ」を主経路とし、Task 11 の共有シートの優先度を上げる。**Task 3 以降の実装内容は変わらない。**
```

- [ ] **Step 8: コミット**

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: record Phase 0 device spike results

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: ファイル名の正規化


ドロップや共有シートから来るファイル名は外部由来の入力である。パス区切りや親ディレクトリ参照を含みうるため、コンテナの外へ書き出せないように正規化する。

**Files:**
- Create: `Sources/Shared/FilenameSanitizer.swift`
- Test: `Tests/FilenameSanitizerTests.swift`

**Interfaces:**
- Consumes: なし
- Produces: `FilenameSanitizer.sanitize(_ raw: String?, fallbackExtension: String?) -> (name: String, ext: String)`
  - `name` は表示用のファイル名（拡張子を含む）。空にはならない。
  - `ext` は拡張子（ドットなし、小文字）。不明な場合は空文字列。

- [ ] **Step 1: 失敗するテストを書く**

`Tests/FilenameSanitizerTests.swift`:

```swift
import Foundation

/// Normalizes filenames that arrive from drops and the share sheet.
/// These are untrusted input: they may contain path separators, parent
/// references, or control characters. Container paths are always built from a
/// UUID, so this result is only used for display and for the file extension —
/// but it must still never escape the container if it is ever joined to a path.
enum FilenameSanitizer {
    private static let maxBytes = 255

    // Real-world extensions top out around 12 chars (e.g. "sketchplugin",
    // "numbers-tef"). Anything longer isn't a genuine extension, and if left
    // unbounded it can drive `truncate`'s byte budget negative, defeating the
    // 255-byte guarantee (see task-3-review.md Finding 1). Cap with headroom.
    private static let maxExtensionBytes = 20

    static func sanitize(_ raw: String?, fallbackExtension: String?) -> (name: String, ext: String) {
        // Take only the last path component, which drops "../" and any directories.
        var base = (raw ?? "")
            .components(separatedBy: CharacterSet(charactersIn: "/\\"))
            .last ?? ""

        base = base.components(separatedBy: .controlCharacters).joined()
        base = base.components(separatedBy: CharacterSet(charactersIn: "\u{2028}\u{2029}")).joined()
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)

        // A name made only of dots would still resolve to a directory reference.
        if base.allSatisfy({ $0 == "." }) { base = "" }

        var ext = (base as NSString).pathExtension.lowercased()
        if ext.utf8.count > maxExtensionBytes {
            // Not a real extension -- treat as absent so the fallback path below applies.
            ext = ""
        }
        if ext.isEmpty, let fallback = fallbackExtension?.lowercased(), !fallback.isEmpty,
           fallback.utf8.count <= maxExtensionBytes {
            ext = fallback
        }

        var stem = (base as NSString).deletingPathExtension
        if stem.isEmpty { stem = "Untitled" }

        stem = truncate(stem, toBytes: maxBytes - (ext.isEmpty ? 0 : ext.utf8.count + 1))

        let name = ext.isEmpty ? stem : "\(stem).\(ext)"
        return (name, ext)
    }

    private static func truncate(_ s: String, toBytes limit: Int) -> String {
        guard s.utf8.count > limit, limit > 0 else { return s }
        var out = s
        while out.utf8.count > limit { out.removeLast() }
        return out
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -destination 'platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | tail -20
```

期待: `cannot find 'FilenameSanitizer' in scope` でコンパイルエラーになる。

- [ ] **Step 3: 実装する**

`Sources/Shared/FilenameSanitizer.swift`:

```swift
import Foundation

/// Normalizes filenames that arrive from drops and the share sheet.
/// These are untrusted input: they may contain path separators, parent
/// references, or control characters. Container paths are always built from a
/// UUID, so this result is only used for display and for the file extension —
/// but it must still never escape the container if it is ever joined to a path.
enum FilenameSanitizer {
    private static let maxBytes = 255

    static func sanitize(_ raw: String?, fallbackExtension: String?) -> (name: String, ext: String) {
        // Take only the last path component, which drops "../" and any directories.
        var base = (raw ?? "")
            .components(separatedBy: CharacterSet(charactersIn: "/\\"))
            .last ?? ""

        base = base.components(separatedBy: .controlCharacters).joined()
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)

        // A name made only of dots would still resolve to a directory reference.
        if base.allSatisfy({ $0 == "." }) { base = "" }

        var ext = (base as NSString).pathExtension.lowercased()
        if ext.isEmpty, let fallback = fallbackExtension?.lowercased(), !fallback.isEmpty {
            ext = fallback
        }

        var stem = (base as NSString).deletingPathExtension
        if stem.isEmpty { stem = "Untitled" }

        stem = truncate(stem, toBytes: maxBytes - (ext.isEmpty ? 0 : ext.utf8.count + 1))

        let name = ext.isEmpty ? stem : "\(stem).\(ext)"
        return (name, ext)
    }

    private static func truncate(_ s: String, toBytes limit: Int) -> String {
        guard s.utf8.count > limit, limit > 0 else { return s }
        var out = s
        while out.utf8.count > limit { out.removeLast() }
        return out
    }
}
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -destination 'platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | tail -20
```

期待: `** TEST SUCCEEDED **`、14 件すべて成功。

- [ ] **Step 5: コミット**

```bash
git add Sources/Shared/FilenameSanitizer.swift Tests/FilenameSanitizerTests.swift
git commit -m "$(cat <<'EOF'
feat: sanitize untrusted filenames from drops and share sheet

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: コンテナの解決


App Group が使えるかどうかを実行時に判定し、使えない場合はアプリのサンドボックスへフォールバックする。**この判定はこのファイル 1 箇所にしか書かない。**

**Files:**
- Create: `Sources/Shared/TrayContainer.swift`

**Interfaces:**
- Consumes: `TrayIDs.appGroupID`（Task 1）
- Produces:
  - `TrayContainer.isShared: Bool` — App Group コンテナが使えるか
  - `TrayContainer.root: URL` — コンテナのルート
  - `TrayContainer.itemsDirectory: URL` — `<root>/Items`
  - `TrayContainer.thumbsDirectory: URL` — `<root>/Thumbs`
  - `TrayContainer.metadataURL: URL` — `<root>/items.json`
  - `TrayContainer.localRoot: URL` — App Group を無視したローカルのルート（Task 11 の移行で使う）

- [ ] **Step 1: 実装する**

境界の解決だけで分岐ロジックがないため、このタスクは単体テストを持たない。振る舞いは Task 5 の `TrayStore` のテストが間接的に検証する。

`Sources/Shared/TrayContainer.swift`:

```swift
import Foundation

/// Resolves where tray data lives.
///
/// This is the only place in the codebase that knows whether the App Group
/// entitlement is present. Everything else just uses the URLs below.
/// Without a paid developer account the entitlement is absent, the App Group
/// container URL comes back nil, and we fall back to the app's own sandbox.
enum TrayContainer {
    static var isShared: Bool { appGroupRoot != nil }

    static var root: URL { appGroupRoot ?? localRoot }

    /// The sandbox location, ignoring any App Group. Used by the migration in
    /// TrayStore when the app moves from a free to a paid account.
    static var localRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("IslandTray", isDirectory: true)
    }

    static var itemsDirectory: URL { root.appendingPathComponent("Items", isDirectory: true) }
    static var thumbsDirectory: URL { root.appendingPathComponent("Thumbs", isDirectory: true) }
    static var metadataURL: URL { root.appendingPathComponent("items.json") }

    private static var appGroupRoot: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TrayIDs.appGroupID)
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認する**

```bash
xcodebuild build -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -configuration Free-Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

期待: `** BUILD SUCCEEDED **`

- [ ] **Step 3: コミット**

```bash
git add Sources/Shared/TrayContainer.swift
git commit -m "$(cat <<'EOF'
feat: resolve tray container with App Group fallback

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: 項目モデルとストア


トレイの中身そのものを扱う。追加・削除・一覧と `items.json` の永続化。アプリと Share Extension の両方から書かれるため `NSFileCoordinator` で調停する。

**Files:**
- Create: `Sources/Shared/TrayItem.swift`
- Create: `Sources/Shared/TrayStore.swift`
- Test: `Tests/TrayStoreTests.swift`

**Interfaces:**
- Consumes: `TrayContainer`（Task 4）, `FilenameSanitizer`（Task 3）
- Produces:
  - `TrayItem`: `id: UUID`, `name: String`, `uti: String`, `size: Int`, `addedAt: Date`, `ext: String`
  - `TrayItem.fileURL: URL`, `TrayItem.thumbnailURL: URL`, `TrayItem.symbolName: String`
  - `TrayStore(root: URL)` — テストのために任意のルートを渡せる
  - `TrayStore.shared: TrayStore`
  - `TrayStore.load() throws -> [TrayItem]`
  - `TrayStore.add(data: Data, suggestedName: String?, uti: String?) throws -> TrayItem`
  - `TrayStore.add(copyingFrom: URL, suggestedName: String?, uti: String?) throws -> TrayItem`
  - `TrayStore.remove(id: UUID) throws`
  - `TrayStore.rebuildFromDisk() throws -> [TrayItem]`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/TrayStoreTests.swift`:

```swift
import XCTest
@testable import IslandTray

final class TrayStoreTests: XCTestCase {
    private var root: URL!
    private var store: TrayStore!

    /// TrayItem.fileURL resolves against TrayContainer, which is the real app
    /// container. Tests run against a temporary root, so they must pass it in.
    private var itemsDir: URL { root.appendingPathComponent("Items", isDirectory: true) }

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = TrayStore(root: root)
        try store.prepare()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAddThenLoadRoundTrip() throws {
        let item = try store.add(data: Data("hello".utf8), suggestedName: "a.txt", uti: "public.plain-text")
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, item.id)
        XCTAssertEqual(loaded[0].name, "a.txt")
        XCTAssertEqual(loaded[0].size, 5)
        XCTAssertEqual(loaded[0].ext, "txt")
    }

    func testStoredBytesMatch() throws {
        let payload = Data("island".utf8)
        let item = try store.add(data: payload, suggestedName: "b.bin", uti: "public.data")
        XCTAssertEqual(try Data(contentsOf: item.fileURL(in: itemsDir)), payload)
    }

    func testDuplicateNamesDoNotCollide() throws {
        let a = try store.add(data: Data("1".utf8), suggestedName: "same.txt", uti: "public.plain-text")
        let b = try store.add(data: Data("22".utf8), suggestedName: "same.txt", uti: "public.plain-text")
        XCTAssertNotEqual(a.fileURL(in: itemsDir), b.fileURL(in: itemsDir))
        XCTAssertEqual(try store.load().count, 2)
        XCTAssertEqual(try Data(contentsOf: a.fileURL(in: itemsDir)).count, 1)
        XCTAssertEqual(try Data(contentsOf: b.fileURL(in: itemsDir)).count, 2)
    }

    func testPathTraversalNameStaysInsideContainer() throws {
        let item = try store.add(data: Data("x".utf8), suggestedName: "../../escape.txt", uti: "public.plain-text")
        XCTAssertTrue(
            item.fileURL(in: itemsDir).standardizedFileURL.path
                .hasPrefix(itemsDir.standardizedFileURL.path)
        )
    }

    func testRemoveDeletesFileAndMetadata() throws {
        let item = try store.add(data: Data("x".utf8), suggestedName: "c.txt", uti: "public.plain-text")
        try store.remove(id: item.id)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.fileURL(in: itemsDir).path))
    }

    func testNewestFirstOrdering() throws {
        let first = try store.add(data: Data("1".utf8), suggestedName: "1.txt", uti: "public.plain-text")
        let second = try store.add(data: Data("2".utf8), suggestedName: "2.txt", uti: "public.plain-text")
        let loaded = try store.load()
        XCTAssertEqual(loaded.map(\.id), [second.id, first.id])
    }

    func testAddCopyingFromURL() throws {
        let src = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("src.txt")
        try Data("from disk".utf8).write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }

        let item = try store.add(copyingFrom: src, suggestedName: nil, uti: "public.plain-text")
        XCTAssertEqual(item.name, "src.txt")
        XCTAssertEqual(try Data(contentsOf: item.fileURL(in: itemsDir)), Data("from disk".utf8))
    }

    func testRebuildFromDiskRecoversAfterCorruptMetadata() throws {
        let item = try store.add(data: Data("keep".utf8), suggestedName: "d.txt", uti: "public.plain-text")
        try Data("}{ not json".utf8).write(to: root.appendingPathComponent("items.json"))

        // load() must not throw on corrupt metadata; it rebuilds instead.
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, item.id)
    }

    func testSymbolNameFallsBackByUTI() throws {
        let image = try store.add(data: Data("x".utf8), suggestedName: "p.jpeg", uti: "public.jpeg")
        let text = try store.add(data: Data("x".utf8), suggestedName: "t.txt", uti: "public.plain-text")
        XCTAssertEqual(image.symbolName, "photo")
        XCTAssertEqual(text.symbolName, "doc.text")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -destination 'platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | tail -20
```

期待: `cannot find 'TrayStore' in scope` でコンパイルエラーになる。

- [ ] **Step 3: `TrayItem` を実装する**

`Sources/Shared/TrayItem.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

struct TrayItem: Codable, Hashable, Identifiable {
    var id: UUID
    /// Display name, already sanitized. Never used to build a path.
    var name: String
    var uti: String
    var size: Int
    var addedAt: Date
    /// Lowercased extension without the dot. May be empty.
    var ext: String

    /// Path is built from the UUID only, never from `name`.
    var fileName: String { ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)" }

    func fileURL(in itemsDirectory: URL) -> URL {
        itemsDirectory.appendingPathComponent(fileName)
    }

    func thumbnailURL(in thumbsDirectory: URL) -> URL {
        thumbsDirectory.appendingPathComponent("\(id.uuidString).png")
    }

    var fileURL: URL { fileURL(in: TrayContainer.itemsDirectory) }
    var thumbnailURL: URL { thumbnailURL(in: TrayContainer.thumbsDirectory) }

    /// Fallback glyph used in the Dynamic Island when thumbnails are unreachable.
    var symbolName: String { Self.symbolName(forUTI: uti) }

    static func symbolName(forUTI identifier: String) -> String {
        guard let type = UTType(identifier) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if type.conforms(to: .sourceCode) { return "chevron.left.forwardslash.chevron.right" }
        if type.conforms(to: .url) { return "link" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}
```

- [ ] **Step 4: `TrayStore` を実装する**

`Sources/Shared/TrayStore.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

/// Reads and writes the tray contents.
///
/// Items are stored as copies: drag payloads are short-lived and Photos items
/// carry no durable path, so keeping a reference would leave dangling entries.
///
/// The app and the share extension can both write, so every access to
/// items.json goes through NSFileCoordinator.
final class TrayStore {
    static let shared = TrayStore(root: TrayContainer.root)

    private let root: URL
    private let itemsDirectory: URL
    private let thumbsDirectory: URL
    private let metadataURL: URL
    private let fileManager = FileManager.default

    init(root: URL) {
        self.root = root
        self.itemsDirectory = root.appendingPathComponent("Items", isDirectory: true)
        self.thumbsDirectory = root.appendingPathComponent("Thumbs", isDirectory: true)
        self.metadataURL = root.appendingPathComponent("items.json")
    }

    func prepare() throws {
        for dir in [root, itemsDirectory, thumbsDirectory] {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Reading

    /// Newest first. Never throws on corrupt metadata — it rebuilds from disk.
    func load() throws -> [TrayItem] {
        try prepare()
        guard let data = coordinatedRead(), !data.isEmpty else { return [] }
        guard let items = try? JSONDecoder.tray.decode([TrayItem].self, from: data) else {
            return try rebuildFromDisk()
        }
        return items
            .filter { fileManager.fileExists(atPath: $0.fileURL(in: itemsDirectory).path) }
            .sorted { $0.addedAt > $1.addedAt }
    }

    /// Recovers the list from the files actually present in Items/.
    /// Metadata that cannot be recovered (original name, UTI) is approximated.
    @discardableResult
    func rebuildFromDisk() throws -> [TrayItem] {
        try prepare()
        let urls = (try? fileManager.contentsOfDirectory(
            at: itemsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        )) ?? []

        let recovered: [TrayItem] = urls.compactMap { url in
            let stem = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: stem) else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let ext = url.pathExtension.lowercased()
            return TrayItem(
                id: id,
                name: url.lastPathComponent,
                uti: utiIdentifier(forExtension: ext),
                size: values?.fileSize ?? 0,
                addedAt: values?.creationDate ?? Date(),
                ext: ext
            )
        }
        .sorted { $0.addedAt > $1.addedAt }

        try write(recovered)
        return recovered
    }

    // MARK: - Writing

    @discardableResult
    func add(data: Data, suggestedName: String?, uti: String?) throws -> TrayItem {
        try prepare()
        let item = makeItem(suggestedName: suggestedName, uti: uti, size: data.count)
        try data.write(to: item.fileURL(in: itemsDirectory), options: .atomic)
        try mutate { $0.insert(item, at: 0) }
        return item
    }

    @discardableResult
    func add(copyingFrom source: URL, suggestedName: String?, uti: String?) throws -> TrayItem {
        try prepare()
        let name = suggestedName ?? source.lastPathComponent
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let item = makeItem(suggestedName: name, uti: uti, size: size)
        let destination = item.fileURL(in: itemsDirectory)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try mutate { $0.insert(item, at: 0) }
        return item
    }

    func remove(id: UUID) throws {
        var removed: TrayItem?
        try mutate { items in
            if let index = items.firstIndex(where: { $0.id == id }) {
                removed = items.remove(at: index)
            }
        }
        if let removed {
            try? fileManager.removeItem(at: removed.fileURL(in: itemsDirectory))
            try? fileManager.removeItem(at: removed.thumbnailURL(in: thumbsDirectory))
        }
    }

    func removeAll() throws {
        let items = try load()
        for item in items {
            try? fileManager.removeItem(at: item.fileURL(in: itemsDirectory))
            try? fileManager.removeItem(at: item.thumbnailURL(in: thumbsDirectory))
        }
        try write([])
    }

    // MARK: - Internals

    private func makeItem(suggestedName: String?, uti: String?, size: Int) -> TrayItem {
        let fallbackExtension = uti.flatMap { UTType($0)?.preferredFilenameExtension }
        let clean = FilenameSanitizer.sanitize(suggestedName, fallbackExtension: fallbackExtension)
        return TrayItem(
            id: UUID(),
            name: clean.name,
            uti: uti ?? utiIdentifier(forExtension: clean.ext),
            size: size,
            addedAt: Date(),
            ext: clean.ext
        )
    }

    private func mutate(_ body: (inout [TrayItem]) -> Void) throws {
        var items = (try? load()) ?? []
        body(&items)
        try write(items)
    }

    private func write(_ items: [TrayItem]) throws {
        let data = try JSONEncoder.tray.encode(items.sorted { $0.addedAt > $1.addedAt })
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: metadataURL, options: .forReplacing, error: &coordinatorError
        ) { url in
            do { try data.write(to: url, options: .atomic) } catch { writeError = error }
        }
        if let writeError { throw writeError }
        if let coordinatorError { throw coordinatorError }
    }

    private func coordinatedRead() -> Data? {
        var result: Data?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: metadataURL, options: [], error: &coordinatorError
        ) { url in
            result = try? Data(contentsOf: url)
        }
        return result
    }

    private func utiIdentifier(forExtension ext: String) -> String {
        guard !ext.isEmpty,
              let type = UTType(filenameExtension: ext) else { return "public.data" }
        return type.identifier
    }
}

extension JSONEncoder {
    static var tray: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var tray: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 5: テストが通ることを確認する**

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -destination 'platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | tail -20
```

期待: `** TEST SUCCEEDED **`、9 件すべて成功。

- [ ] **Step 6: コミット**

```bash
git add Sources/Shared/TrayItem.swift Sources/Shared/TrayStore.swift Tests/TrayStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: add tray item model and file-coordinated store

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Live Activity の状態づくりと 4KB 制約


`TrayItem` の配列から `TrayContentState` を作る。`ContentState` は 4096 バイトを超えると `Activity.request` が `attributesTooLarge` で失敗するため、組み立て側でサイズを保証する。

**Files:**
- Modify: `Sources/Shared/TrayContentState.swift`
- Test: `Tests/TrayContentStateTests.swift`

**Interfaces:**
- Consumes: `TrayItem`（Task 5）, `TrayContentState`（Task 1）
- Produces:
  - `TrayContentState.make(from items: [TrayItem]) -> TrayContentState`
  - `TrayContentState.encodedByteCount: Int`
  - `TrayContentState.maxEncodedBytes: Int`（= 4096）

- [ ] **Step 1: 失敗するテストを書く**

`Tests/TrayContentStateTests.swift`:

```swift
import XCTest
@testable import IslandTray

final class TrayContentStateTests: XCTestCase {
    private func item(name: String, uti: String = "public.jpeg") -> TrayItem {
        TrayItem(id: UUID(), name: name, uti: uti, size: 1, addedAt: Date(), ext: "jpeg")
    }

    func testCountReflectsAllItems() {
        let items = (0..<10).map { item(name: "\($0).jpeg") }
        let state = TrayContentState.make(from: items)
        XCTAssertEqual(state.count, 10)
    }

    func testRecentIsCappedAtMaxPreviews() {
        let items = (0..<10).map { item(name: "\($0).jpeg") }
        let state = TrayContentState.make(from: items)
        XCTAssertEqual(state.recent.count, TrayContentState.maxPreviews)
    }

    func testRecentPreservesOrder() {
        let items = (0..<4).map { item(name: "\($0).jpeg") }
        let state = TrayContentState.make(from: items)
        XCTAssertEqual(state.recent.map(\.id), items.map { $0.id.uuidString })
    }

    func testEmptyTray() {
        let state = TrayContentState.make(from: [])
        XCTAssertEqual(state.count, 0)
        XCTAssertTrue(state.recent.isEmpty)
    }

    func testSymbolComesFromUTI() {
        let state = TrayContentState.make(from: [item(name: "a.txt", uti: "public.plain-text")])
        XCTAssertEqual(state.recent.first?.symbol, "doc.text")
    }

    func testStaysUnderFourKilobytesWithWorstCaseNames() {
        // Worst case: the maximum number of previews, each with a long id and symbol.
        let items = (0..<TrayContentState.maxPreviews).map { _ in
            item(name: String(repeating: "x", count: 255))
        }
        let state = TrayContentState.make(from: items)
        XCTAssertLessThan(state.encodedByteCount, TrayContentState.maxEncodedBytes)
    }

    func testEncodedByteCountIsNonZero() {
        let state = TrayContentState.make(from: [item(name: "a.jpeg")])
        XCTAssertGreaterThan(state.encodedByteCount, 0)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -destination 'platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | tail -20
```

期待: `type 'TrayContentState' has no member 'make'` でコンパイルエラーになる。

- [ ] **Step 3: 実装する**

`Sources/Shared/TrayContentState.swift` を次の内容に差し替える:

```swift
import Foundation

/// Dynamic data shown by the Live Activity.
///
/// ActivityKit rejects a content state whose encoded form exceeds 4096 bytes,
/// so this never carries image data — only an id the widget uses to locate a
/// thumbnail file on disk, plus an SF Symbol name to fall back to.
struct TrayContentState: Codable, Hashable {
    /// Maximum number of previews the Dynamic Island can show at once.
    static let maxPreviews = 4
    /// ActivityKit's hard limit for an encoded content state.
    static let maxEncodedBytes = 4096

    struct Preview: Codable, Hashable {
        /// TrayItem id. The widget derives the thumbnail path from this.
        var id: String
        /// SF Symbol name, used when the App Group container is unavailable.
        var symbol: String
    }

    var count: Int
    var recent: [Preview]

    static func make(from items: [TrayItem]) -> TrayContentState {
        let previews = items.prefix(maxPreviews).map {
            Preview(id: $0.id.uuidString, symbol: $0.symbolName)
        }
        return TrayContentState(count: items.count, recent: Array(previews))
    }

    var encodedByteCount: Int {
        (try? JSONEncoder().encode(self).count) ?? 0
    }
}
```

`Preview` はファイル名を持たない。UUID 文字列 36 バイトと短い SF Symbol 名だけなので、4 件でも 400 バイト程度に収まり 4096 バイトに届かない。

- [ ] **Step 4: テストが通ることを確認する**

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -destination 'platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | tail -20
```

期待: `** TEST SUCCEEDED **`

- [ ] **Step 5: コミット**

```bash
git add Sources/Shared/TrayContentState.swift Tests/TrayContentStateTests.swift
git commit -m "$(cat <<'EOF'
feat: build Live Activity content state within the 4KB limit

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: サムネイル生成


`QLThumbnailGenerator` でサムネイルを作る。ファイルアプリが使っているのと同じ API なので、「ファイルアプリに出てくるアイコンそのまま」という要件はこれで満たされる。独自のアイコンセットは作らない。

**Files:**
- Create: `Sources/App/ThumbnailService.swift`

**Interfaces:**
- Consumes: `TrayItem`（Task 5）, `TrayContainer`（Task 4）
- Produces:
  - `ThumbnailService.shared`
  - `ThumbnailService.thumbnail(for: TrayItem) async -> UIImage?` — キャッシュがあれば読み、なければ生成して保存する
  - `ThumbnailService.removeCache(for: TrayItem)`

単体テストは置かない。`QLThumbnailGenerator` は実ファイルとシステムのレンダラに依存し、テストで固定できる出力がないため。失敗時に SF Symbol へ落ちることは Task 8 の UI コードで保証し、実機で目視確認する。

- [ ] **Step 1: 実装する**

`Sources/App/ThumbnailService.swift`:

```swift
import QuickLookThumbnailing
import UIKit

/// Generates and caches thumbnails using the same API the Files app uses,
/// so tray items look exactly like they do in Files.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private static let pointSize = CGSize(width: 120, height: 120)
    private var inFlight: [UUID: Task<UIImage?, Never>] = [:]

    func thumbnail(for item: TrayItem) async -> UIImage? {
        if let cached = loadCached(item) { return cached }
        if let running = inFlight[item.id] { return await running.value }

        let task = Task<UIImage?, Never> { [pointSize = Self.pointSize] in
            let scale = await MainActor.run { UIScreen.main.scale }
            let request = QLThumbnailGenerator.Request(
                fileAt: item.fileURL,
                size: pointSize,
                scale: scale,
                representationTypes: .all
            )
            guard let rep = try? await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request) else { return nil }
            return rep.uiImage
        }
        inFlight[item.id] = task

        let image = await task.value
        inFlight[item.id] = nil
        if let image { store(image, for: item) }
        return image
    }

    func removeCache(for item: TrayItem) {
        try? FileManager.default.removeItem(at: item.thumbnailURL)
    }

    // MARK: - Disk cache
    //
    // The cache lives in the container so the widget process can read it too,
    // which is what makes real thumbnails possible in the Dynamic Island.

    private func loadCached(_ item: TrayItem) -> UIImage? {
        guard let data = try? Data(contentsOf: item.thumbnailURL) else { return nil }
        return UIImage(data: data)
    }

    private func store(_ image: UIImage, for item: TrayItem) {
        guard let data = image.pngData() else { return }
        try? FileManager.default.createDirectory(
            at: TrayContainer.thumbsDirectory, withIntermediateDirectories: true
        )
        try? data.write(to: item.thumbnailURL, options: .atomic)
    }
}
```

- [ ] **Step 2: ビルドが通ることを確認する**

```bash
xcodebuild build -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -configuration Free-Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

期待: `** BUILD SUCCEEDED **`

- [ ] **Step 3: コミット**

```bash
git add Sources/App/ThumbnailService.swift
git commit -m "$(cat <<'EOF'
feat: generate Files-style thumbnails with QLThumbnailGenerator

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Live Activity の制御と表示


アプリ側で Live Activity を開始・更新・終了し、Widget Extension 側で 4 つの表示を作る。

**Files:**
- Create: `Sources/App/TrayActivityController.swift`
- Create: `Sources/Widget/TrayPreviewStrip.swift`
- Modify: `Sources/Widget/TrayLiveActivity.swift`（Task 1 の仮実装を置き換える）

**Interfaces:**
- Consumes: `TrayContentState`（Task 6）, `TrayActivityAttributes`（Task 1）, `TrayItem`（Task 5）, `TrayContainer`（Task 4）
- Produces:
  - `TrayActivityController.shared`
  - `TrayActivityController.sync(items: [TrayItem]) async` — 開始または更新。空なら終了
  - `TrayActivityController.restart() async` — 終了してから開始し直し、8 時間の枠をリセットする
  - `TrayPreviewStrip(previews:)`

- [ ] **Step 1: コントローラを実装する**

`Sources/App/TrayActivityController.swift`:

```swift
import ActivityKit
import Foundation

/// Owns the tray's Live Activity.
///
/// ActivityKit ends an activity after eight hours, so `restart()` exists to
/// reset that window. It runs when the app comes forward and from the
/// RefreshTrayActivityIntent that the Shortcuts automation triggers.
actor TrayActivityController {
    static let shared = TrayActivityController()

    /// Surfaced to the UI when starting fails, rather than swallowing the error.
    private(set) var lastError: String?

    private var current: Activity<TrayActivityAttributes>? {
        Activity<TrayActivityAttributes>.activities.first
    }

    func sync(items: [TrayItem]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "ライブアクティビティが許可されていません"
            return
        }
        guard !items.isEmpty else {
            await end()
            return
        }

        let state = TrayContentState.make(from: items)
        guard state.encodedByteCount < TrayContentState.maxEncodedBytes else {
            // Should be unreachable given the preview cap, but degrade instead
            // of letting ActivityKit reject the whole update.
            await update(TrayContentState(count: items.count, recent: []))
            return
        }

        if current != nil {
            await update(state)
        } else {
            await start(state)
        }
    }

    func restart() async {
        let items = (try? TrayStore.shared.load()) ?? []
        await end()
        await sync(items: items)
    }

    // MARK: - Internals

    private func start(_ state: TrayContentState) async {
        do {
            _ = try Activity.request(
                attributes: TrayActivityAttributes(),
                content: .init(state: state, staleDate: nil)
            )
            lastError = nil
        } catch {
            lastError = "アイランドの表示を開始できません: \(error.localizedDescription)"
        }
    }

    private func update(_ state: TrayContentState) async {
        guard let current else { return }
        await current.update(.init(state: state, staleDate: nil))
        lastError = nil
    }

    private func end() async {
        for activity in Activity<TrayActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
```

- [ ] **Step 2: サムネイルの横並びを実装する**

`Sources/Widget/TrayPreviewStrip.swift`:

```swift
import SwiftUI

/// Shared by the expanded Dynamic Island and the Lock Screen presentation.
///
/// Reads thumbnail files straight from the container. Without the App Group
/// entitlement that container is unreachable from this process, so each preview
/// falls back to the SF Symbol carried in the content state.
struct TrayPreviewStrip: View {
    let previews: [TrayContentState.Preview]
    var side: CGFloat = 36

    var body: some View {
        HStack(spacing: 6) {
            ForEach(previews, id: \.id) { preview in
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white.opacity(0.14))
                    if let image = thumbnail(for: preview) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    } else {
                        Image(systemName: preview.symbol)
                            .font(.system(size: side * 0.42))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: side, height: side)
            }
        }
    }

    private func thumbnail(for preview: TrayContentState.Preview) -> UIImage? {
        guard TrayContainer.isShared else { return nil }
        let url = TrayContainer.thumbsDirectory.appendingPathComponent("\(preview.id).png")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
```

- [ ] **Step 3: 4 つの表示を実装する**

`Sources/Widget/TrayLiveActivity.swift` を次の内容に差し替える:

```swift
import ActivityKit
import SwiftUI
import WidgetKit

struct TrayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrayActivityAttributes.self) { context in
            lockScreen(context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.count)", systemImage: "tray.full.fill")
                        .font(.caption.bold())
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("トレイ")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // No ScrollView: widget views cannot receive gestures, so the
                    // full swipeable list lives in the app.
                    TrayPreviewStrip(previews: context.state.recent, side: 40)
                        .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: "tray.full.fill")
            } compactTrailing: {
                Text("\(context.state.count)")
                    .font(.caption.monospacedDigit())
            } minimal: {
                Text("\(context.state.count)")
                    .font(.caption2.monospacedDigit())
            }
            .widgetURL(TrayIDs.dropURL)
        }
    }

    private func lockScreen(_ state: TrayContentState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 6) {
                Text("トレイに \(state.count) 件")
                    .font(.subheadline.bold())
                TrayPreviewStrip(previews: state.recent, side: 32)
            }
            Spacer()
        }
        .padding(14)
        .activityBackgroundTint(Color.black.opacity(0.45))
    }
}
```

- [ ] **Step 4: コミット**

```bash
git add Sources/App/TrayActivityController.swift Sources/Widget/TrayPreviewStrip.swift Sources/Widget/TrayLiveActivity.swift
git commit -m "$(cat <<'EOF'
feat: drive Live Activity and render Dynamic Island presentations

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: トレイ画面


全画面のドロップターゲットと、横スクロールのサムネイル一覧。取り出しと削除もここ。

**Files:**
- Create: `Sources/App/DropReceiver.swift`
- Create: `Sources/App/TrayModel.swift`
- Create: `Sources/App/TrayCardView.swift`
- Create: `Sources/App/SetupGuideView.swift`
- Modify: `Sources/App/TrayView.swift`（Task 1 と Task 2 の仮実装を置き換える）
- Modify: `Sources/App/IslandTrayApp.swift`

**Interfaces:**
- Consumes: `TrayStore`（Task 5）, `ThumbnailService`（Task 7）, `TrayItem`（Task 5）
- Produces:
  - `DropReceiver.ingest(providers: [NSItemProvider]) async -> (added: Int, failed: [String])`
  - `TrayModel`（`@Observable`）: `items: [TrayItem]`, `banner: String?`, `reload()`, `ingest(_:)`, `remove(_:)`
  - `TrayCardView(item:onDelete:)`

- [ ] **Step 1: ドロップの取り込みを実装する**

`Sources/App/DropReceiver.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

/// Turns dropped NSItemProviders into tray items.
///
/// The URL handed to loadFileRepresentation is only valid for the duration of
/// the completion handler, so the bytes are copied before returning.
enum DropReceiver {
    struct Result {
        var added: Int
        var failed: [String]
    }

    static func ingest(providers: [NSItemProvider]) async -> Result {
        var added = 0
        var failed: [String] = []

        for provider in providers {
            let typeIdentifier = preferredTypeIdentifier(for: provider)
            do {
                let payload = try await loadFile(from: provider, typeIdentifier: typeIdentifier)
                _ = try TrayStore.shared.add(
                    copyingFrom: payload,
                    suggestedName: provider.suggestedName,
                    uti: typeIdentifier
                )
                try? FileManager.default.removeItem(at: payload)
                added += 1
            } catch {
                failed.append(provider.suggestedName ?? "unnamed item")
            }
        }
        return Result(added: added, failed: failed)
    }

    /// Prefer the most specific concrete type the provider offers, ignoring
    /// container-ish identifiers that would give us a useless extension.
    private static func preferredTypeIdentifier(for provider: NSItemProvider) -> String {
        let ignored: Set<String> = ["public.item", "public.content", "public.data"]
        let candidates = provider.registeredTypeIdentifiers
        return candidates.first { !ignored.contains($0) }
            ?? candidates.first
            ?? UTType.data.identifier
    }

    /// Copies the provider's file representation into a temporary location that
    /// stays valid after the completion handler returns.
    private static func loadFile(
        from provider: NSItemProvider, typeIdentifier: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: CocoaError(.fileNoSuchFile))
                    return
                }
                // Must copy synchronously: url is deleted once this returns.
                let staging = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: staging)
                    continuation.resume(returning: staging)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

- [ ] **Step 2: 画面の状態を実装する**

`Sources/App/TrayModel.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class TrayModel {
    var items: [TrayItem] = []
    var banner: String?

    func reload() {
        items = (try? TrayStore.shared.load()) ?? []
    }

    func ingest(_ providers: [NSItemProvider]) async {
        let result = await DropReceiver.ingest(providers: providers)
        reload()

        if !result.failed.isEmpty {
            banner = "取り込めませんでした: \(result.failed.joined(separator: ", "))"
        } else if result.added > 0 {
            banner = nil
        }
        await syncActivity()
    }

    /// Updates the Live Activity and surfaces any failure rather than
    /// swallowing it — the spec requires the reason to be visible.
    func syncActivity() async {
        await TrayActivityController.shared.sync(items: items)
        if let error = await TrayActivityController.shared.lastError {
            banner = error
        }
    }

    func remove(_ item: TrayItem) async {
        do {
            try TrayStore.shared.remove(id: item.id)
        } catch {
            banner = "削除に失敗しました"
        }
        await ThumbnailService.shared.removeCache(for: item)
        reload()
        await syncActivity()
    }
}
```

- [ ] **Step 3: カードを実装する**

`Sources/App/TrayCardView.swift`:

```swift
import SwiftUI

struct TrayCardView: View {
    let item: TrayItem
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?

    private static let cardWidth: CGFloat = 104

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.cardWidth, height: Self.cardWidth)

            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.cardWidth)
        }
        .task(id: item.id) {
            thumbnail = await ThumbnailService.shared.thumbnail(for: item)
        }
        // onDrag rather than .draggable: this hands other apps the actual file
        // rather than a link to it.
        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
        .contextMenu {
            ShareLink(item: item.fileURL) {
                Label("共有", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive, action: onDelete) {
                Label("削除", systemImage: "trash")
            }
        }
    }
}
```

- [ ] **Step 4: 設定手順の画面を実装する**

`Sources/App/SetupGuideView.swift`:

```swift
import SwiftUI

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("ダイナミックアイランドの表示は 8 時間で自動的に消えます。ショートカットのオートメーションで 8 時間ごとに作り直すと、24 時間途切れずに表示できます。")
                        .font(.callout)
                } header: {
                    Text("なぜ設定が必要か")
                }

                Section {
                    step(1, "ショートカットアプリを開き、「オートメーション」タブを選びます。")
                    step(2, "「+」から「時刻」を選びます。")
                    step(3, "時刻を 07:00 に設定し、「毎日」を選びます。")
                    step(4, "「すぐに実行」を選びます。確認を求める設定のままだと自動で動きません。")
                    step(5, "アクションで「トレイの表示を更新」を選びます。")
                    step(6, "同じ手順を 15:00 と 23:00 でも繰り返します。")
                } header: {
                    Text("設定手順")
                }

                Section {
                    Text("アプリを開いたときにも表示は作り直されます。オートメーションが動かなかった場合は、アプリを一度開けば復帰します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("共有コンテナ", value: TrayContainer.isShared ? "有効" : "無効")
                    if !TrayContainer.isShared {
                        Text("有料の Apple Developer アカウントがないため、共有シートからの追加と、アイランド内の実サムネイルは利用できません。それ以外の機能はすべて動作します。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("状態")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold().monospacedDigit())
                .frame(width: 20, height: 20)
                .background(.tint.opacity(0.18), in: .circle)
            Text(text)
                .font(.callout)
        }
    }
}
```

- [ ] **Step 5: トレイ画面を実装する**

`Sources/App/TrayView.swift` を次の内容に差し替える:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct TrayView: View {
    @State private var model = TrayModel()
    @State private var isTargeted = false
    @State private var showsSetupGuide = false

    var body: some View {
        NavigationStack {
            ZStack {
                if model.items.isEmpty {
                    emptyState
                } else {
                    strip
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dropHighlight)
            .navigationTitle("トレイ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSetupGuide = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showsSetupGuide) { SetupGuideView() }
            .safeAreaInset(edge: .bottom) {
                if let banner = model.banner {
                    Text(banner)
                        .font(.footnote)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.red.opacity(0.15))
                }
            }
        }
        .onDrop(of: [UTType.item], isTargeted: $isTargeted) { providers in
            Task { await model.ingest(providers) }
            return true
        }
        .task {
            model.reload()
            await model.syncActivity()
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                ForEach(model.items) { item in
                    TrayCardView(item: item) {
                        Task { await model.remove(item) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("トレイは空です", systemImage: "tray")
        } description: {
            Text("ファイルや写真をドラッグしてここに落とすと預かります。")
        }
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 4 : 0)
            .background(isTargeted ? Color.accentColor.opacity(0.10) : Color.clear)
            .padding(8)
            .animation(.snappy(duration: 0.15), value: isTargeted)
            .ignoresSafeArea()
    }
}
```

- [ ] **Step 6: アプリのエントリポイントを戻す**

`Sources/App/IslandTrayApp.swift` を次の内容に差し替える（Task 2 のスパイク用バッジを外す）:

```swift
import SwiftUI

@main
struct IslandTrayApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TrayView()
                .onOpenURL { _ in
                    // The Live Activity's only deep link brings the tray forward
                    // so a drag in flight can be dropped. Nothing else to do.
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Restart the Live Activity whenever the app comes forward, so the
            // eight-hour window resets even if the Shortcuts automation missed.
            if phase == .active {
                Task { await TrayActivityController.shared.restart() }
            }
        }
    }
}
```

- [ ] **Step 7: 両構成でビルドが通ることを確認する**

```bash
xcodebuild build -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -configuration Free-Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
xcodebuild build -project IslandTray.xcodeproj -scheme "IslandTray" -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

期待: どちらも `** BUILD SUCCEEDED **`

- [ ] **Step 8: コミット**

```bash
git add Sources/App/DropReceiver.swift Sources/App/TrayModel.swift Sources/App/TrayCardView.swift Sources/App/SetupGuideView.swift Sources/App/TrayView.swift Sources/App/IslandTrayApp.swift
git commit -m "$(cat <<'EOF'
feat: add tray screen with drop target and horizontal card strip

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: 24 時間維持のためのインテントと設定画面


`LiveActivityIntent` をショートカットに公開し、時刻オートメーションから 8 時間ごとに呼び出せるようにする。設定手順をアプリ内に表示する。

**Files:**
- Create: `Sources/App/RefreshTrayActivityIntent.swift`
- Create: `Sources/App/TrayShortcuts.swift`

**Interfaces:**
- Consumes: `TrayActivityController`（Task 9）
- Produces: `RefreshTrayActivityIntent`, `TrayShortcuts`

- [ ] **Step 1: インテントを実装する**

`Sources/App/RefreshTrayActivityIntent.swift`:

```swift
import AppIntents

/// Recreates the Live Activity so its eight-hour window restarts.
///
/// Conforming to LiveActivityIntent is what makes this work from the
/// background: the system launches the app's process without opening the app,
/// runs perform(), and grants permission to start a Live Activity. A Shortcuts
/// time-of-day automation calling this three times a day keeps the tray visible
/// around the clock.
struct RefreshTrayActivityIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "トレイの表示を更新"
    static var description = IntentDescription(
        "ダイナミックアイランドのトレイ表示を作り直します。8 時間ごとに実行すると表示が途切れません。"
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await TrayActivityController.shared.restart()
        return .result()
    }
}
```

- [ ] **Step 2: ショートカットに公開する**

`Sources/App/TrayShortcuts.swift`:

```swift
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
```

- [ ] **Step 3: 両構成でビルドが通ることを確認する**

```bash
xcodebuild build -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -configuration Free-Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
xcodebuild build -project IslandTray.xcodeproj -scheme "IslandTray" -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

期待: どちらも `** BUILD SUCCEEDED **`

- [ ] **Step 4: 既存のテストが通り続けることを確認する**

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -destination 'platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | tail -20
```

期待: `** TEST SUCCEEDED **`

- [ ] **Step 5: 実機で動作を確認する**

1. 実機にインストールする。
2. 写真をドラッグして取り込み、横スクロール一覧にサムネイルが出ることを確認する。
3. カードを長押しして共有・削除が動くことを確認する。
4. カードを他アプリへドラッグして渡せることを確認する。
5. ホームへ出て、ダイナミックアイランドに件数が出ることを確認する。
6. アイランドを長押しして展開表示にサムネイル（無料構成では SF Symbol）が並ぶことを確認する。
7. ショートカットアプリに「トレイの表示を更新」が出ることを確認し、手動実行して表示が作り直されることを確認する。

- [ ] **Step 6: コミット**

```bash
git add Sources/App/RefreshTrayActivityIntent.swift Sources/App/TrayShortcuts.swift
git commit -m "$(cat <<'EOF'
feat: keep the Live Activity alive via a Shortcuts-exposed intent

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: 共有シート拡張とコンテナ移行


共有シートからの取り込みと、無料構成から有料構成へ移ったときのデータ移行。

**Files:**
- Modify: `Sources/Share/ShareViewController.swift`（Task 1 の仮実装を置き換える）
- Modify: `Sources/Shared/TrayStore.swift`（`migrateIfNeeded()` を足す）
- Modify: `Sources/App/IslandTrayApp.swift`（起動時に移行を呼ぶ）
- Test: `Tests/TrayStoreTests.swift`（移行のテストを足す）

**Interfaces:**
- Consumes: `TrayStore`（Task 5）, `TrayContainer`（Task 4）
- Produces: `TrayStore.migrateIfNeeded(from localRoot: URL) throws -> Int`（移行した件数を返す）

- [ ] **Step 1: 移行の失敗するテストを書く**

`Tests/TrayStoreTests.swift` の末尾（最後の `}` の直前）に追加する:

```swift
    func testMigrationMovesItemsFromLocalRoot() throws {
        let oldRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oldStore = TrayStore(root: oldRoot)
        try oldStore.prepare()
        defer { try? FileManager.default.removeItem(at: oldRoot) }

        let a = try oldStore.add(data: Data("one".utf8), suggestedName: "a.txt", uti: "public.plain-text")
        _ = try oldStore.add(data: Data("two".utf8), suggestedName: "b.txt", uti: "public.plain-text")

        let moved = try store.migrateIfNeeded(from: oldRoot)
        XCTAssertEqual(moved, 2)

        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertTrue(loaded.contains { $0.id == a.id })
        XCTAssertEqual(try Data(contentsOf: loaded.first { $0.id == a.id }!.fileURL(in: itemsDir)), Data("one".utf8))
    }

    func testMigrationIsIdempotent() throws {
        let oldRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oldStore = TrayStore(root: oldRoot)
        try oldStore.prepare()
        defer { try? FileManager.default.removeItem(at: oldRoot) }

        _ = try oldStore.add(data: Data("one".utf8), suggestedName: "a.txt", uti: "public.plain-text")

        XCTAssertEqual(try store.migrateIfNeeded(from: oldRoot), 1)
        XCTAssertEqual(try store.migrateIfNeeded(from: oldRoot), 0)
        XCTAssertEqual(try store.load().count, 1)
    }

    func testMigrationFromSameRootDoesNothing() throws {
        _ = try store.add(data: Data("x".utf8), suggestedName: "a.txt", uti: "public.plain-text")
        XCTAssertEqual(try store.migrateIfNeeded(from: root), 0)
        XCTAssertEqual(try store.load().count, 1)
    }
```

- [ ] **Step 2: テストが失敗することを確認する**

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -destination 'platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | tail -20
```

期待: `value of type 'TrayStore' has no member 'migrateIfNeeded'` でコンパイルエラーになる。

- [ ] **Step 3: 移行を実装する**

`Sources/Shared/TrayStore.swift` の `removeAll()` の直後に追加する:

```swift
    /// Moves items from a previous container into this one.
    ///
    /// Needed when the app moves from a free account (sandbox container) to a
    /// paid one (App Group container): the tray would otherwise appear empty.
    /// Safe to call on every launch — it no-ops when there is nothing to move.
    @discardableResult
    func migrateIfNeeded(from oldRoot: URL) throws -> Int {
        guard oldRoot.standardizedFileURL != root.standardizedFileURL else { return 0 }

        let oldStore = TrayStore(root: oldRoot)
        let incoming = (try? oldStore.load()) ?? []
        guard !incoming.isEmpty else { return 0 }

        try prepare()
        var existing = (try? load()) ?? []
        let knownIDs = Set(existing.map(\.id))
        var moved = 0

        for item in incoming where !knownIDs.contains(item.id) {
            let source = item.fileURL(in: oldRoot.appendingPathComponent("Items", isDirectory: true))
            let destination = item.fileURL(in: itemsDirectory)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            try? fileManager.removeItem(at: source)
            existing.append(item)
            moved += 1
        }

        if moved > 0 { try write(existing) }
        return moved
    }
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -destination 'platform=iOS Simulator,name=iPhone 18 Pro' 2>&1 | tail -20
```

期待: `** TEST SUCCEEDED **`

- [ ] **Step 5: 起動時に移行を呼ぶ**

`Sources/App/IslandTrayApp.swift` の `WindowGroup` 内、`TrayView()` に付いている `.onOpenURL` の直後に追加する:

```swift
                .task {
                    // Carries the tray over when the app gains an App Group
                    // container after moving to a paid developer account.
                    if TrayContainer.isShared {
                        try? TrayStore.shared.migrateIfNeeded(from: TrayContainer.localRoot)
                    }
                }
```

- [ ] **Step 6: 共有シート拡張を実装する**

`Sources/Share/ShareViewController.swift` を次の内容に差し替える:

```swift
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Without the App Group entitlement this process writes to its own
        // sandbox, which the app can never read. Say so instead of silently
        // losing the item.
        guard TrayContainer.isShared else {
            present(message: "共有シートからの追加は、有料の Apple Developer アカウントでビルドした場合のみ利用できます。")
            return
        }
        Task { await ingest() }
    }

    private func ingest() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }

        var added = 0
        for provider in providers {
            let typeIdentifier = provider.registeredTypeIdentifiers.first
                ?? UTType.data.identifier
            guard let staged = await loadFile(from: provider, typeIdentifier: typeIdentifier)
            else { continue }
            if (try? TrayStore.shared.add(
                copyingFrom: staged,
                suggestedName: provider.suggestedName,
                uti: typeIdentifier
            )) != nil {
                added += 1
            }
            try? FileManager.default.removeItem(at: staged)
        }

        await MainActor.run {
            present(message: added > 0 ? "\(added) 件をトレイに追加しました" : "追加できませんでした")
        }
    }

    private func loadFile(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                // Must copy synchronously: url is deleted once this returns.
                let staging = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: staging)
                continuation.resume(
                    returning: FileManager.default.fileExists(atPath: staging.path) ? staging : nil
                )
            }
        }
    }

    private func present(message: String) {
        let host = UIHostingController(rootView: ShareResultView(message: message) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

private struct ShareResultView: View {
    let message: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 40))
            Text(message)
                .multilineTextAlignment(.center)
                .font(.callout)
            Button("閉じる", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
```

- [ ] **Step 7: 両構成でビルドが通ることを確認する**

```bash
xcodebuild build -project IslandTray.xcodeproj -scheme "IslandTray (Free)" -configuration Free-Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
xcodebuild build -project IslandTray.xcodeproj -scheme "IslandTray" -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

期待: どちらも `** BUILD SUCCEEDED **`

- [ ] **Step 8: コミット**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: add share extension and container migration

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## 有料アカウント取得後の確認

Apple Developer Program の登録が完了したら、次を実施する。実装の変更は不要。

- [ ] Apple Developer の Certificates, Identifiers & Profiles で App Group `group.com.pikare.islandtray` を作る。
- [ ] 3 つの App ID（`com.pikare.islandtray`, `.widget`, `.share`）に App Group を紐付ける。
- [ ] Xcode で `IslandTray` スキーム（`Debug` 構成）を選んで実機にインストールする。
- [ ] 設定画面の「共有コンテナ」が「有効」になっていることを確認する。
- [ ] 無料構成で預けた項目が移行されて残っていることを確認する。
- [ ] 写真アプリの共有シートに IslandTray が出ること、選ぶと追加されることを確認する。
- [ ] ダイナミックアイランドを長押しし、SF Symbol ではなく実サムネイルが並ぶことを確認する。

---

## Task 12: 未署名 IPA のパッケージング

サイドローディング用に未署名の `.ipa` を作るスクリプトを用意する。`.ipa` は `Payload/` に `.app` を入れて zip しただけのものなので、専用のツールは要らない。

**LiveContainer では動かない。** LiveContainer は app extension を登録できない（サンドボックス内で動くため SpringBoard が中のアプリを認識しない）。本アプリの中心である Widget Extension = Live Activity が丸ごと使えなくなるので、**SideStore で直接インストールする**こと。

**TrollStore は使えない。** 対象端末は iPhone 16 Pro / iOS 27 で、TrollStore がインストールできるバージョン範囲を大きく超えている。したがって任意 entitlement の付与は不可。

**App Group が SideStore で通るかは実測する。** 無料 Personal Team は Developer Portal 上で App Group を作れないが、SideStore / AltStore 側の既知の不具合報告は「App Group が 3 個を超えると失敗する」という書き方であり、1 個なら通る可能性がある。本アプリが必要とするのは 1 個。まず `Release`（App Group あり）の ipa を入れてみて、インストールが弾かれたら `Free-Release` に落とす。

サイドローディングのツールは自前で再署名するため、未署名のまま渡すのが正しい。構成を引数で選べるようにして、App Group を要求する `Release`（TrollStore のように任意の entitlement を付与できるツール向け）と、要求しない `Free-Release`（AltStore / SideStore のように無料の個人 Team で署名するツール向け）の両方を出せるようにする。

**Files:**
- Create: `scripts/make-ipa.sh`

**Interfaces:**
- Consumes: Task 1 の `project.yml` と 2 つのビルド構成
- Produces: `scripts/make-ipa.sh [Release|Free-Release]` → `build/IslandTray-<構成>.ipa`

- [ ] **Step 1: スクリプトを書く**

`scripts/make-ipa.sh`:

```bash
#!/usr/bin/env bash
# Builds an UNSIGNED .ipa for sideloading. Sideloading tools re-sign the bundle
# themselves, so signing here would only be thrown away.
#
#   Release       entitlements request the App Group (TrollStore and other tools
#                 that can grant arbitrary entitlements)
#   Free-Release  no entitlements (AltStore / SideStore, which sign with a free
#                 personal team and cannot grant App Groups)
set -euo pipefail

CONFIG="${1:-Release}"
case "$CONFIG" in
  Release)      SCHEME="IslandTray" ;;
  Free-Release) SCHEME="IslandTray (Free)" ;;
  *) echo "usage: $0 [Release|Free-Release]" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen generate

BUILD_DIR="build/$CONFIG"
rm -rf "$BUILD_DIR"

xcodebuild build \
  -project IslandTray.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  | tail -5

APP="$BUILD_DIR/Build/Products/$CONFIG-iphoneos/IslandTray.app"
[ -d "$APP" ] || { echo "app bundle not found at $APP" >&2; exit 1; }

STAGE="$BUILD_DIR/stage"
rm -rf "$STAGE"; mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"

OUT="$PWD/build/IslandTray-$CONFIG.ipa"
rm -f "$OUT"
(cd "$STAGE" && zip -qry "$OUT" Payload)

echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
```

- [ ] **Step 2: 実行権限を付けて両方の構成で走らせる**

```bash
chmod +x scripts/make-ipa.sh
./scripts/make-ipa.sh Free-Release
./scripts/make-ipa.sh Release
```

期待: どちらも `wrote .../IslandTray-<構成>.ipa` と表示される。

- [ ] **Step 3: 中身を検証する**

```bash
unzip -l build/IslandTray-Release.ipa | head -20
```

期待: `Payload/IslandTray.app/` 以下にアプリ本体があり、`Payload/IslandTray.app/PlugIns/` に Widget と Share の 2 つの拡張が含まれている。拡張が入っていなければ、アプリターゲットへの埋め込み設定を確認する。

```bash
unzip -p build/IslandTray-Release.ipa Payload/IslandTray.app/Info.plist | plutil -p - | grep -E "NSSupportsLiveActivities|CFBundleURLSchemes" -A2
```

期待: `NSSupportsLiveActivities => 1` と `islandtray` が出る。

- [ ] **Step 4: build/ を git から除外する**

`.gitignore` に次の行が無ければ足す:

```
build/
```

- [ ] **Step 5: コミット**

```bash
git add scripts/make-ipa.sh .gitignore
git commit -m "$(cat <<'EOF'
feat: package unsigned ipa for sideloading

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

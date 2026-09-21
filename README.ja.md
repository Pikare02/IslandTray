# IslandTray

[English](README.md) · **日本語**

ファイル・写真・コピーしたテキストを一時的に置いておける、iPhone / iPad 用のトレイです。
Dynamic Island がその取っ手になります。作業中に放り込んでおけば、どのアプリにいても
アイランドで中身が見え、必要な場所へドラッグで取り出せます。

## 機能

- **トレイ** — どのアプリからでも、ファイル・写真・動画・テキストをドラッグで入れられます。
  項目はアプリ内にコピーされるので、元のアプリで消えてもトレイには残ります。
- **Dynamic Island / Live Activity** — 待っている項目の数を、小さなサムネイルとファイル名つきで
  表示し、ボタンでページをめくれます。タップするとトレイが開きます。
- **ドラッグで取り出す** — カードを別のアプリへドラッグします。1 枚持ち上げたまま別の指で
  ほかのカードをタップすれば、写真アプリやファイルアプリと同じようにまとめて運べます。
- **クリップボード** — コピーした内容を、次のコピーで上書きされる前に保存できます。
  書式つきのテキストは、対応するアプリには書式ごと、それ以外のアプリにはテキストだけが
  貼り付けられます。
- **共有シート** — ほかのアプリの共有シートから何でもトレイに送れます
  （有料アカウントでは共有拡張、無料アカウントでは用意済みのショートカット）。
- **「ファイルに保存」受け取りフォルダ** — ファイルアプリの *このiPhone内 → IslandTray* に
  保存したものは、次にアプリを開いたときトレイに取り込まれます。
- **整理** — 2 つのボードをまとめて検索、種類で絞り込み、名前・日付・サイズで並べ替え、
  種類ごとにグループ化、グリッドとリストの切り替え。
- **削除** — 行を左にスワイプして削除（最後までスワイプすると即削除）、複数選択して共有・削除、
  または取り出した項目をトレイから消す設定（コピーではなく切り取り）。
- **英語と日本語**、ライト / ダークのテーマ、好きなハイライトカラー。

## 動作環境

- iOS / iPadOS 17.0 以降
- ビルドには macOS、Xcode（Swift 6）、[XcodeGen](https://github.com/yonaskolb/XcodeGen) が必要です

## はじめかた

```bash
brew install xcodegen
xcodegen generate
open IslandTray.xcodeproj
```

Xcode プロジェクトは [`project.yml`](project.yml) から生成するもので、リポジトリには含めていません。
通常のビルドは `IslandTray` スキーム、無料アカウント向けの構成（App Group なし）を試すときは
`IslandTray (Free)` スキームを使います。

サイドロード用の `.ipa` を作る方法は [docs/INSTALL.ja.md](docs/INSTALL.ja.md) を参照してください。

## テスト

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme IslandTray \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## 構成

| パス | 内容 |
|------|------|
| `Sources/App` | アプリ本体：ボード、ドラッグの受け渡し、ショートカット用の App Intent |
| `Sources/Widget` | Dynamic Island に出る Live Activity |
| `Sources/Share` | 共有拡張（App Group が必要） |
| `Sources/Shared` | 全ターゲットで共有する保存・並べ替え・絞り込み |
| `Resources/Shortcuts` | アプリからインストールできる署名済みショートカット |
| `scripts/` | `make-ipa.sh`、`make-shortcuts.py`、`make-icon.swift` |
| `Tests/` | ユニットテスト |
| `docs/superpowers/` | 設計仕様書と実装計画（開発記録） |

## ドキュメント

- [変更履歴](CHANGELOG.ja.md)
- [インストールと .ipa のビルド](docs/INSTALL.ja.md)
- [ショートカット：共有シート、クリップボード、アイランドを出し続ける方法](docs/SHORTCUTS.ja.md)

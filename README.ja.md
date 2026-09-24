<p align="center">
  <img src="docs/icon.png" width="220" alt="IslandTray app icon">
</p>

<h1 align="center">IslandTray</h1>

<p align="center">
  <a href="https://pikare02.github.io/IslandTray/"><img src="https://img.shields.io/badge/iPhone_%E3%81%AB%E3%82%A4%E3%83%B3%E3%82%B9%E3%83%88%E3%83%BC%E3%83%AB-1d6f86?style=for-the-badge&logo=apple&logoColor=white" alt="iPhone にインストール"></a>
  <a href="https://github.com/Pikare02/IslandTray/releases/latest"><img src="https://img.shields.io/github/v/release/Pikare02/IslandTray?style=for-the-badge&color=13161c" alt="Latest release"></a>
</p>

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
- **アプリドロワー（ラボ機能、初期値はオフ）** — トレイの下にある、全画面のショートカット
  一覧です。何も置いていないときは時計と天気が出ます。オフのときは何も変わりません。
  オンにすると、インストール済みアプリ・ショートカット・URL スキーム・Web リンクの
  4 種類を登録できます。インストール済みアプリの選択のみ TrollStore 限定で、
  残り 3 種類はどちらのビルドでも使えます。各項目にはカスタムアイコンを、ドロワー全体には
  背景画像を設定できます。何もないときは日付と、位置情報を許可すれば現在地の天気
  （[Open-Meteo](https://open-meteo.com/) 提供）を表示します。位置情報を共有する代わりに、
  地域を手動で選ぶこともできます。

## リリースノート

各バージョンの詳しい内容と `.ipa` は、GitHub のリリースページにあります。全体は[変更履歴](CHANGELOG.ja.md)にもまとめています。

| バージョン | 主な変更 |
|---|---|
| [1.7.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.7.0) | アプリドロワー（ラボ機能）：トレイの下に全画面のショートカット一覧。空のときは時計と天気を表示 |
| [1.6.2](https://github.com/Pikare02/IslandTray/releases/tag/v1.6.2) | iCloud 同期で別デバイスの変更がより速く反映されるように |
| [1.6.1](https://github.com/Pikare02/IslandTray/releases/tag/v1.6.1) | セットアップの案内を分かりやすく。「状態」を「外観」のすぐ下に |
| [1.6.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.6.0) | iCloud 同期を通常機能に。設定の並びを変更 |
| [1.5.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.5.0) | 「重要なアップデートを毎回知らせる」設定を追加。クリップボードから取り出しても消えないように |
| [1.4.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.4.0) | ダイナミックアイランドの表示でダイアログを置き換え。中身も検索（テキストと画像 OCR）。ショートカットが「常に許可」を記憶 |
| [1.3.1](https://github.com/Pikare02/IslandTray/releases/tag/v1.3.1) | フォルダの取り込みを改善し、共有シートのショートカットにも対応。失敗したドロップは理由を表示 |
| [1.3.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.3.0) | フォルダをそのままトレイに入れ、フォルダのまま取り出せるように |
| [1.2.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.2.0) | クリップボードからコピー（名前をタップ・右スワイプ・長押し）。共有シートのショートカットで追加するとアイランドがすぐ更新 |
| [1.1.5](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.5) | 2 つのショートカットを復旧（1.1.4 に含まれていなかった） |
| [1.1.4](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.4) | トレイからの削除と元ファイルの削除を別々の設定に。取り出しは常にコピー |
| [1.1.3](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.3) | インストールページを GitHub Pages に移動 |
| [1.1.2](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.2) | iOS が知らない形式（`.ipa` など）もファイルアプリへドラッグ可能に |
| [1.1.1](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.1) | アップデートのお知らせで、そのバージョンをスキップ可能に |
| [1.1.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.0) | 起動時に新しいリリースを確認。既定は切り取りではなくコピー |
| [1.0.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.0.0) | 最初のリリース |

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
- [インストールページ（iPhone で最新の .ipa を入手）](https://pikare02.github.io/IslandTray/)
- [インストールと .ipa のビルド](docs/INSTALL.ja.md)
- [ショートカット：共有シート、クリップボード、アイランドを出し続ける方法](docs/SHORTCUTS.ja.md)

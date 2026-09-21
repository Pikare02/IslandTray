# IslandTray のインストール

[English](INSTALL.md) · **日本語**

IslandTray は App Store では配布していません。Xcode からインストールするか、
署名なしの `.ipa` をビルドしてサイドロードします。

## Xcode から

1. `xcodegen generate` を実行し、`IslandTray.xcodeproj` を開きます。
2. 各ターゲットの *Signing & Capabilities* で自分のチームを選びます。
3. スキームを選んで実機で実行します。
   - `IslandTray` — **有料**の Apple Developer アカウント向け。App Group を使うので、
     共有拡張が動きます。
   - `IslandTray (Free)` — **無料**の個人チーム向け。App Group はなく、共有シートからは
     ショートカット経由で使います（[SHORTCUTS.ja.md](SHORTCUTS.ja.md) を参照）。

## .ipa のビルド

```bash
./scripts/make-ipa.sh Release        # build/IslandTray-Release.ipa
./scripts/make-ipa.sh Free-Release   # build/IslandTray-Free-Release.ipa
```

`.ipa` は署名されていません。署名はサイドロードツールが行います。パッケージ後、
スクリプトは 2 つの拡張（ウィジェットと共有）、Live Activity と URL スキームのキー、
正しいエンタイトルメントが揃っているかを確認し、壊れたビルドを残さずに失敗します。

| ファイル | 用途 |
|----------|------|
| `IslandTray-Release.ipa` | TrollStore など、任意のエンタイトルメントを付与できるツール向け。App Group を要求します。 |
| `IslandTray-Free-Release.ipa` | AltStore / SideStore など、無料アカウントで署名するツール向け。エンタイトルメントなし。 |

## 無料アカウントでの違い

- アプリを共有シートに直接出すことはできません。アプリの **設定 → セットアップ** から
  共有シート用ショートカットをインストールするか、*ファイルに保存* で
  *このiPhone内 → IslandTray* を選んでください。次にアプリを開いたときに取り込まれます。
- それ以外（トレイ、アイランド、ドラッグでの出し入れ、クリップボード）はすべて同じように動きます。

## アップデートしたら

新しいビルドで同梱のショートカットが変わった場合は、ショートカットアプリで古いものを削除し、
アプリの設定から入れ直してください。インストール済みのショートカットはコピーなので、
自動では更新されません。

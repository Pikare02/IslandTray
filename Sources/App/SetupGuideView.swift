import Foundation
import SwiftUI

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let model: TrayModel

    @State private var showActivityWhenEmpty = TraySettings().showActivityWhenEmpty
    /// Held in state, not read straight from `DropDiagnostics` in the body:
    /// it is plain UserDefaults with nothing to observe, so clearing it left
    /// the old lines on screen until the sheet was closed and reopened.
    @State private var diagnostics = DropDiagnostics.lines
    @State private var removeOnExport = TraySettings().removeOnExport

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if diagnostics.isEmpty {
                        Text("まだ記録がありません。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                        }
                        Button("記録を消す", role: .destructive) {
                            DropDiagnostics.clear()
                            diagnostics = []
                        }
                    }
                } header: {
                    Text("取り込みの記録")
                } footer: {
                    Text("トレイに入れた項目ごとに、元のファイルをたどれたか（file / photo-id / photo-exif）、たどれなかったか（none）と、相手のアプリが渡してきた種類を並べています。none の項目は、取り出しても元の場所には残ります。")
                }

                Section {
                    Toggle("トレイが空でも表示する", isOn: $showActivityWhenEmpty)
                        .onChange(of: showActivityWhenEmpty) { _, newValue in
                            TraySettings().showActivityWhenEmpty = newValue
                            Task { await model.syncActivity() }
                        }
                } header: {
                    Text("ライブアクティビティ")
                } footer: {
                    Text("オンにすると、アプリがバックグラウンドで生きている間はトレイが空でもアイランドの表示を続けます。オフにすると、トレイが空になった時点で表示を終了します。")
                }

                Section {
                    Toggle("取り出したらトレイから削除する", isOn: $removeOnExport)
                        .onChange(of: removeOnExport) { _, newValue in
                            TraySettings().removeOnExport = newValue
                        }
                } header: {
                    Text("取り出し")
                } footer: {
                    Text("オンにすると、他のアプリへドラッグして渡した項目はトレイから消えます（切り取り）。オフにすると残ります（コピー）。共有シートから渡した場合は、成功したかどうかを iOS が教えてくれないため、この設定に関わらず残ります。\n\n元のファイルまで削除できるのは、ファイルとして受け取ったものだけです。写真アプリから取り込んだものは、写真が変換されて渡されるため元の写真を特定できず、つねにコピーになります。")
                }

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
                    step(
                        5,
                        // Interpolates the intent's own title rather than a
                        // second hard-typed copy, so this instruction and the
                        // action name Shortcuts actually shows cannot drift
                        // apart.
                        "アクションで「\(String(localized: RefreshTrayActivityIntent.title))」を選びます。"
                    )
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("有料の Apple Developer アカウントがないため、共有シートからこのアプリを直接選ぶことはできません。かわりに「ファイルに保存」を使ってください。")
                            Text("保存先: 「ファイル」App →「ブラウズ」→「このiPhone内」→「IslandTray」")
                            Text("そこに保存したファイルは、次にこのアプリを開いたときトレイへ取り込まれ、フォルダからは消えます。アイランド内のサムネイルとファイル名は、この状態でも表示されます。")
                        }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("状態")
                }
            }
            .onAppear { diagnostics = DropDiagnostics.lines }
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

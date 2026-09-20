import Foundation
import SwiftUI

struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    let model: TrayModel

    @State private var showActivityWhenEmpty = TraySettings().showActivityWhenEmpty

    var body: some View {
        NavigationStack {
            List {
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

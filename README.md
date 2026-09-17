# Pomoblock

ポモドーロタイマーとサイトブロッカーを兼ねた macOS メニューバーアプリ。
作業フェーズの間だけ X などのサイトを遮断し、休憩に入ると自動で解除する。

## 特徴

- **メニューバー常駐** — Dock には出ず、残り時間がメニューバーに出る
- **フェーズ連動ブロック** — 作業中は遮断、休憩中は解除を自動で切り替える
- **`/etc/hosts` 方式** — Safari / Chrome / Arc など全ブラウザとアプリに一括で効く
- **改ざん復旧** — `/etc/hosts` を手で書き換えられても 15 秒以内に元へ戻す
- **常時起動** — ログイン時に自動起動し、終了されても数秒で復帰する

## 動作要件

macOS 14 以降。ビルドには Xcode（Swift 6 以降）が必要。

## ビルドと起動

```bash
./Scripts/build-app.sh
open dist/Pomoblock.app
```

`dist/Pomoblock.app` を `/Applications` へ移せばそのまま常用できる。

## 初回セットアップ

メニューバーのアイコンから「常駐ガードを導入」を押す。
管理者パスワードを一度だけ求められ、以下が設置される。

| 設置先 | 役割 |
|---|---|
| `/usr/local/libexec/pomoblock-guard.sh` | hosts を書き換える本体（root 実行） |
| `/Library/LaunchDaemons/jp.havas.pomoblock.guard.plist` | ガードの起動定義 |
| `/Library/Application Support/Pomoblock/desired.conf` | アプリが書くブロック要求（ユーザー所有） |

導入後は、ブロックの ON/OFF でパスワードを求めない。
パスワードが必要なのはガードの導入と撤去だけ。

## 設計

### なぜ常駐ガードを分けたか

`/etc/hosts` の書き換えには root 権限が要る。フェーズが変わるたびに認証を求めては使い物にならないため、権限が要る部分だけを LaunchDaemon として切り出した。

アプリは `desired.conf` に「ブロックしたい/したくない」を書くだけ。ガードが `WatchPaths` でその変化を検知し、`/etc/hosts` へ反映する。この分離により、日常操作は認証なしで完結する。

### ブロックが効く条件

遮断するのは**ポモドーロの作業フェーズ中だけ**。休憩と待機中は自動で解除する。
判定は `AppModel.applyBlockingPolicy()` の一箇所に集約してある。

作業フェーズ中にアプリを終了すると状態ファイルは `blocked=1` のまま残るため、
起動時にポリシーを適用し直して待機中の状態へ揃える。

### 常時起動の仕組み

設定の「起動」タブで有効にすると、`~/Library/LaunchAgents/jp.havas.pomoblock.agent.plist` を書いて
`launchctl bootstrap` する。ユーザー領域の LaunchAgent なので管理者パスワードは要らない。

`RunAtLoad` でログイン時に起動し、`KeepAlive` で終了されても起動し直す。
メニューの「終了」を押しても 1 秒ほどで戻るため、完全に止めるにはスイッチを切ってから終了する。

launchd は実行ファイルを直接起動するため、Finder や `open` から重ねて起動すると
メニューバーにアイコンが 2 つ並びうる。`AppDelegate` で起動時に同一バンドルの先行インスタンスを探し、
見つかったら自分を終了して 1 つに保つ。

再ビルド時は `Scripts/build-app.sh` が一度エージェントを止め、完了後に入れ直す。
`KeepAlive` が差し替え中のバンドルを掴むのを避けるため。

### 開いたままのタブの扱い

`/etc/hosts` はこれから行う名前解決を止めるだけで、読み込み済みのページや確立済みの接続には効かない。
遮断開始時にタブを操作する仕組みは持たないため、開いているページは手動で閉じる。

## 制限

- 解除の抑止は行わない。自動起動を切ってアプリを終了すれば遮断は解ける
- **Service Worker を登録した PWA には効かない。** X は `sw.js` をスコープ `/` で登録しているため、
  登録済みのブラウザではキャッシュから配信され、hosts の遮断を素通りする。
  これを塞ぐにはブラウザ拡張が要る
- アプリを別の場所へ移動したら、自動起動のスイッチを入れ直す。登録時のパスを指すため
- 自動起動はシステム設定 > 一般 > ログイン項目 からも無効にできる
- ad-hoc 署名のため、再ビルドすると署名が変わり自動化の許可を求め直される場合がある
- 未署名（ad-hoc 署名）のため、通知の許可が通らない環境では音のみで通知する

## 構成

```
Sources/Pomoblock/
├── PomoblockApp.swift          # エントリポイント（MenuBarExtra）
├── Support/AppConstants.swift  # 定数の集約
├── Models/
│   ├── PomodoroPhase.swift     # フェーズ定義
│   ├── AppSettings.swift       # 設定の永続化
│   ├── PomodoroEngine.swift    # タイマー本体
│   └── AppModel.swift          # タイマーとブロックの調停
├── Blocking/
│   ├── PrivilegedRunner.swift  # 管理者権限での実行
│   └── BlockController.swift   # 状態ファイルの管理
└── Views/
    ├── MenuBarContentView.swift
    └── SettingsView.swift

Resources/
├── pomoblock-guard.sh                 # 常駐ガード本体
└── jp.havas.pomoblock.guard.plist     # LaunchDaemon 定義
```

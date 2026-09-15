# Pomoblock

ポモドーロタイマーとサイトブロッカーを兼ねた macOS メニューバーアプリ。
作業フェーズの間だけ X などのサイトを遮断し、休憩に入ると自動で解除する。

## 特徴

- **メニューバー常駐** — Dock には出ず、残り時間がメニューバーに出る
- **フェーズ連動ブロック** — 作業中は遮断、休憩中は解除を自動で切り替える
- **`/etc/hosts` 方式** — Safari / Chrome / Arc など全ブラウザとアプリに一括で効く
- **Locked Mode** — 指定時間まで解除不能。アプリを終了しても Mac を再起動してもブロックが続く
- **改ざん復旧** — `/etc/hosts` を手で書き換えられても 15 秒以内に元へ戻す

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
| `/Library/Application Support/Pomoblock/lock.conf` | ロック期限（root 所有） |

導入後は、通常のブロック ON/OFF でパスワードを求めない。
パスワードが必要なのはロックの設定、ガードの導入と撤去だけ。

## 設計

### なぜ常駐ガードを分けたか

`/etc/hosts` の書き換えには root 権限が要る。フェーズが変わるたびに認証を求めては使い物にならないため、権限が要る部分だけを LaunchDaemon として切り出した。

アプリは `desired.conf` に「ブロックしたい/したくない」を書くだけ。ガードが `WatchPaths` でその変化を検知し、`/etc/hosts` へ反映する。この分離により、日常操作は認証なしで完結する。

### Locked Mode の仕組み

`lock.conf` は root 所有で、アプリの権限では書き換えられない。ガードは次の順で判断する。

1. `lock.conf` の期限が未来 → 強制的にブロック。**ドメイン一覧もロック時点のものを使う**
2. 期限内でなければ `desired.conf` の指定に従う
3. 期限を過ぎた `lock.conf` はガードが自動削除する

ロック時点のドメイン一覧を使うのは、アプリ側でリストを空にして抜け道を作られるのを防ぐため。

### ブロックが効く条件

次のいずれかを満たすと遮断される。

1. Locked Mode の期限内
2. ポモドーロの作業フェーズ中

タイマーを止めている間は遮断しない。常時遮断したい場合は Locked Mode を使う。

なお、作業フェーズ中にアプリを終了しても状態ファイルは `blocked=1` のまま残るため、
起動時にポリシーを適用し直して待機中の状態へ揃える。

### ロック中は休憩でもブロックが続く

通常モードではフェーズに応じてブロックが切り替わるが、ロック中は期限まで遮断しっぱなしになる。休憩の 5 分だけ X を開ける仕様にすると、ロックの意味が薄れるため意図的にこうしてある。

## 制限

- root 権限を持つ以上、`sudo launchctl bootout` で強制解除は可能。これは Cold Turkey など既存アプリも同じで、「面倒にする」ことが目的
- Chrome は DNS を独自にキャッシュするため、ブロック直後はタブの再読み込みが要る場合がある
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

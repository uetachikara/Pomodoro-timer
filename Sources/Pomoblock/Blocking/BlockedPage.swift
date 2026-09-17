import Foundation

/// 遮断したタブの退避先ページ。
///
/// 再読み込みでは Service Worker がキャッシュからアプリシェルを返してしまい、
/// ネットワークを遮断していても画面が出続ける（X は PWA なのでこれに該当する）。
/// そのためタブごと別の URL へ飛ばす。その行き先がこのページ。
///
/// 元の URL は fragment に載せて表示するので、解除後に戻れる。
enum BlockedPage {

    /// ページの設置先。ユーザー領域なので書き込みに権限が要らない。
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Pomoblock/\(AppConstants.blockedPageFileName)")
    }

    /// ページを設置し、その URL を返す。失敗した場合は nil。
    static func ensureInstalled() -> URL? {
        let url = fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try html.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// 元の URL を fragment に載せた退避先を組み立てる。
    static func destination(for originalURL: String, pageURL: URL) -> String {
        let encoded = originalURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return pageURL.absoluteString + "#" + encoded
    }

    /// 退避先ページの中身。外部リソースを持たない自己完結の HTML。
    private static let html = """
    <!doctype html>
    <html lang="ja">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>ブロック中 - Pomoblock</title>
    <style>
      :root {
        color-scheme: light dark;
        --bg: #f6f6f7;
        --fg: #1c1c1e;
        --muted: #6b6b70;
        --card: #ffffff;
        --border: #e2e2e5;
        --accent: #c0392b;
      }
      @media (prefers-color-scheme: dark) {
        :root {
          --bg: #161618;
          --fg: #f2f2f4;
          --muted: #9a9aa0;
          --card: #202024;
          --border: #313136;
          --accent: #ff6b5a;
        }
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
        background: var(--bg);
        color: var(--fg);
        font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", sans-serif;
      }
      .card {
        width: 100%;
        max-width: 520px;
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 14px;
        padding: 32px;
      }
      .badge {
        display: inline-block;
        font-size: 12px;
        font-weight: 600;
        letter-spacing: .04em;
        color: var(--accent);
        border: 1px solid var(--accent);
        border-radius: 999px;
        padding: 3px 10px;
        margin-bottom: 18px;
      }
      h1 { font-size: 21px; margin: 0 0 10px; }
      p { margin: 0 0 18px; color: var(--muted); font-size: 14px; line-height: 1.7; }
      .url {
        display: block;
        background: var(--bg);
        border: 1px solid var(--border);
        border-radius: 8px;
        padding: 12px 14px;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 13px;
        word-break: break-all;
        margin-bottom: 14px;
      }
      button {
        font: inherit;
        font-size: 13px;
        padding: 7px 14px;
        border-radius: 7px;
        border: 1px solid var(--border);
        background: var(--bg);
        color: var(--fg);
        cursor: pointer;
      }
      button:hover { border-color: var(--muted); }
      .hint { font-size: 12px; margin: 14px 0 0; }
    </style>
    </head>
    <body>
      <div class="card">
        <span class="badge">POMOBLOCK</span>
        <h1>作業中のためブロックしています</h1>
        <p>休憩フェーズに入ると自動で解除されます。元の URL は控えてあります。</p>
        <code class="url" id="original">(URL なし)</code>
        <button id="copy">URL をコピー</button>
        <p class="hint">このページは Pomoblock が表示しています。タブを閉じても構いません。</p>
      </div>
    <script>
      // 元の URL は fragment に percent-encoding で載っている
      const raw = location.hash.slice(1);
      const original = raw ? decodeURIComponent(raw) : "";
      const field = document.getElementById("original");
      if (original) { field.textContent = original; }
      document.getElementById("copy").addEventListener("click", async () => {
        if (!original) { return; }
        try {
          await navigator.clipboard.writeText(original);
          const button = document.getElementById("copy");
          button.textContent = "コピーしました";
          setTimeout(() => { button.textContent = "URL をコピー"; }, 1500);
        } catch (error) {
          // クリップボードが使えない場合は選択させる
          getSelection().selectAllChildren(field);
        }
      });
    </script>
    </body>
    </html>
    """
}

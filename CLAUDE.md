# CLAUDE.md

このリポジトリで開発を行う際の共通ルール。

---

## ドキュメント構成

| ファイル | 用途 |
|---------|------|
| `doc/spec.md` | 決定済みの仕様。実装の根拠はここを参照 |
| `doc/pending.md` | 未決定事項・仕様化待ちの課題 |
| `doc/progress.md` | 実装進捗。完了時は ✅ にして概要を記入 |
| `doc/ideas.md` | 採用前の構想・アイデア |

仕様変更・機能追加を行ったら、該当ドキュメントも合わせて更新する。

---

## git ルール

### ブランチ構成

```
master
  └─ develop         ← 検証ブランチ
       └─ feature/*  ← 機能開発ブランチ
```

- `feature/*` は `develop` から切り、完成後に `develop` へマージ
- `develop` で動作確認が取れたら `master` へマージ

### コミットメッセージ

```
feat:     新機能
fix:      バグ修正
refactor: リファクタリング
revert:   変更の取り消し
docs:     ドキュメント変更のみ
```

---

## コーディング規約

### 命名規則

| 種別 | 規則 | 例 |
|------|------|----|
| RemoteEvent | `RE_` プレフィックス | `RE_GameStateChanged` |
| BindableEvent | `BE_` プレフィックス | `BE_BuildBoard` |
| クライアントスクリプト | `.client.lua` | `HUDController.client.lua` |
| サーバースクリプト | `.server.lua` | `GameManager.server.lua` |

### UI

- サイズ・位置は原則 `UDim2.fromScale()` を使用（絶対ピクセル値は使わない）
- モバイル判定: `UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled`
- PC/モバイルでサイズを分岐する場合は `isMobile and X or Y` のインライン三項で記述

### イベント

- RemoteEvent は `ReplicatedStorage/RemoteEvents` フォルダに格納
- BindableEvent は `ServerScriptService/ServerEvents` フォルダに格納
- クライアント → サーバーのイベントはサーバー側で受信者の権限チェックを必ず行う

---

## プロジェクト構成

```
src/
├── server/   → ServerScriptService
├── client/   → StarterPlayerScripts
└── shared/   → ReplicatedStorage
```

マップ座標定数（`BOARD_CENTER_X` 等）はマップ変更時に複数ファイルの更新が必要。  
変更箇所は `doc/spec.md` の「3.2 マップ変更時の修正箇所」を参照。

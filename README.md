# numbers

Roblox マルチプレイナンプレゲーム

巨大なナンプレ盤面を複数人で協力してクリアするRobloxゲーム。  
プレイヤーはアバターを操作して数字ブロックを拾い、盤面に配置していく。

---

## リポジトリ情報

| 項目 | 内容 |
|------|------|
| リポジトリ名 | [numbers-game](https://github.com/shinji0214/numbers-game) |
| エンジン | Roblox |
| 言語 | Lua (Luau) |
| ビルドツール | [Rojo](https://rojo.space/) 7.6.1 |
| パッケージ管理 | [Rokit](https://github.com/rojo-rbx/rokit) |

---

## 開発環境のセットアップ

### 必要なもの
- [Roblox Studio](https://www.roblox.com/create)
- [Rokit](https://github.com/rojo-rbx/rokit)
- Rojo Plugin（Roblox Studio 内のプラグイン）

### 手順

```bash
# リポジトリをクローン
git clone https://github.com/shinji0214/numbers-game.git
cd numbers

# rokit で rojo をインストール
rokit install

# rojo サーバーを起動
rojo serve
```

Roblox Studio で Rojo プラグインを開き、`localhost:34872` に接続する。

---

## プロジェクト構成

```
numbers/
├── default.project.json       # Rojo プロジェクト設定
├── rokit.toml                 # Rokit ツール設定
├── doc/                       # ドキュメント
│   ├── spec.md                # ゲーム仕様書（決定済み）
│   ├── pending.md             # 未決定事項
│   ├── progress.md            # 実装進捗
│   └── ideas.md               # 構想・アイデア
└── src/
    ├── server/                # ServerScriptService
    │   ├── GameManager.server.lua       # 盤面生成・正解判定・スコア
    │   ├── BlockManager.server.lua      # ブロックスポーン・拾う・リスポーン
    │   ├── ScoreManager.server.lua      # クリア時ボーナス集計
    │   └── GameStateManager.server.lua  # ゲーム状態管理（Lobby/InGame/Result）
    ├── client/                # StarterPlayerScripts
    │   ├── PlayerController.client.lua   # ブロック拾う・置く・捨てる操作
    │   ├── HUDController.client.lua      # スコア・コンボ・アクションボタン・結果画面
    │   ├── CameraController.client.lua   # 俯瞰カメラ切替
    │   ├── MarkerController.client.lua   # マーカー設置
    │   └── LobbyController.client.lua    # ロビーUI・難易度選択・暗転フェード
    └── shared/                # ReplicatedStorage
        └── SudokuModule.lua   # ナンプレ生成・正解判定
```

---

## ゲーム仕様（概要）

詳細は [doc/spec.md](./doc/spec.md) を参照。

| 項目 | 内容 |
|------|------|
| 想定人数 | 8〜16人（CPU追加可） |
| 1ゲーム時間 | 5〜10分 |
| 難易度 | Easy / Normal / Hard（変形盤面） |
| 操作 | E キーでブロックを拾う・置く、Q キーで捨てる、V キーで俯瞰カメラ |
| マップ | Map 1（盤面中心 `-4307, 1862, 1923`） |

---

## ブランチ運用ルール

```
master
  └─ develop         ← 検証ブランチ
       └─ feature/*  ← 機能開発ブランチ
```

| ブランチ | 役割 |
|---------|------|
| `master` | リリース済みの安定版 |
| `develop` | 検証・統合ブランチ。動作確認はここで行う |
| `feature/*` | 機能ごとの開発ブランチ。`develop` から切り、完成後に `develop` へマージ |

### 開発フロー

```bash
# 1. develop から機能ブランチを作成
git checkout develop
git checkout -b feature/機能名

# 2. 実装・コミット
git add .
git commit -m "feat: 〇〇を実装"

# 3. develop にマージして検証
git checkout develop
git merge feature/機能名
git push

# 4. 検証OKなら master にマージ
git checkout master
git merge develop
git push
```

### コミットメッセージ規則

| プレフィックス | 用途 |
|--------------|------|
| `feat:` | 新機能 |
| `fix:` | バグ修正 |
| `refactor:` | リファクタリング |
| `revert:` | 変更の取り消し |
| `docs:` | ドキュメント変更 |

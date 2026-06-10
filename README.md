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
- Rojo Plugin（Roblox Studio内のプラグイン）

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
├── default.project.json    # Rojo プロジェクト設定
├── rokit.toml              # Rokit ツール設定
├── roblox_sudoku_spec.md   # ゲーム仕様書
└── src/
    ├── server/             # ServerScriptService
    │   ├── GameManager.server.lua   # 盤面生成・配置処理・スコア・クリア判定
    │   ├── BlockManager.server.lua  # ブロックスポーン・拾う・消費・リスポーン
    │   └── ScoreManager.server.lua  # クリア時ボーナス集計（未実装）
    ├── client/             # StarterPlayerScripts
    │   ├── PlayerController.client.lua   # ブロック拾う・置く操作
    │   ├── CameraController.client.lua   # 俯瞰カメラ切替
    │   └── MarkerController.client.lua   # マーカー設置
    ├── shared/             # ReplicatedStorage
    │   └── SudokuModule.lua   # ナンプレ生成・正解判定
    └── gui/                # StarterGui
        └── HUD.lua            # スコア・コンボ表示（未実装）
```

---

## ゲーム仕様（概要）

詳細は [roblox_sudoku_spec.md](./roblox_sudoku_spec.md) を参照。

| 項目 | 内容 |
|------|------|
| 想定人数 | 8〜16人（CPU追加可） |
| 1ゲーム時間 | 5〜10分 |
| 難易度 | Easy / Normal / Hard（変形盤面） |
| 操作 | E キーでブロックを拾う・置く、V キーで俯瞰カメラ |

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

---

## 開発状況

### 実装済み
- [x] ナンプレ生成・正解判定（SudokuModule）
- [x] 盤面の3D生成・描画
- [x] ブロックスポーン・拾う・消費・リスポーン
- [x] 本置きロジック（正解判定・ロック・上書き）
- [x] スパム制限・ペナルティ
- [x] コンボボーナス付きスコア加算
- [x] 俯瞰カメラ切替
- [x] マーカー機能

### 未実装
- [ ] ScoreManager（クリア時ボーナス集計）
- [ ] HUD（スコア・コンボ画面表示）
- [ ] クリア演出・結果画面
- [ ] ロビー・マッチング画面
- [ ] コレクション・バッジ報酬

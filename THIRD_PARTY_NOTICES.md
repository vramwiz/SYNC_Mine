# ライセンスと使用コンポーネント

MINE（SYNC_MINE）: Copyright (c) 2026 VRAMの魔術師

本体のソースコードは GNU General Public License v3.0（GPL-3.0）です。全文は [LICENSE](LICENSE) を参照してください。

## 個別のMITライセンス

| 部品・参照元 | 著作権表示 | ライセンス全文 |
| --- | --- | --- |
| ColorPicker | Copyright (c) 2025 vramwiz | [MIT License](Source/Lib/ColorPicker/LICENSE) |
| SYNC_RhythmShooter / RhythmControls | Copyright (c) 2026 VRAMの魔術師 | [MIT License](Source/Lib/UI/LICENSE.RhythmControls.txt) |

各MITライセンス本文を配布ZIPにも同梱しています。

## 移植元

- **SYNC_Nicomea** — Delphi プロジェクト、ビルド後イベント、AviUtl2 SDK 型定義、フィルターテーブル登録処理、設定画面の基盤をコピーして最小構成にしています。
- **SYNC_MusicStudio** — `SYNC_MusicStudio_DarkTheme.pas` による VCL 設定画面の暗色配色を引き継いでいます。
- **Syncroh2 / SYNC_Lyrics** — `PluginFilterTable.pas` の元となるフィルターテーブル登録処理。由来はユニット先頭にも記載しています。

- **AviUtl2PluginLib** — 既存の `VectorRenderer`、`VectorRendererData`、`VectorRendererImageList`、RTTI保存基盤、キャラアイコンリソースを相対参照して再利用しています。
- **SYNC_RhythmShooter / RhythmControls** — MITライセンス。標準の操作を維持した暗色スライダーと所有者描画ボタンの実装方式を `SYNC_MINE_DarkControls.pas` へ取り入れています。
- **ColorPicker（vramwiz） / SYNC_Nicomea** — Nicomeaで使用するHSV変換・色相バー・彩度明度エリアをコピーしています。カラーピッカーのMITライセンス本文を [Source/Lib/ColorPicker/LICENSE](Source/Lib/ColorPicker/LICENSE) に保持しています。

設定画面とビルドには Delphi / VCL、描画にはWindows標準のGDI+、ホストとの連携には AviUtl2 のフィルタープラグイン API を使用します。

コピー元のライセンス本文を [LICENSE](LICENSE) に保持しています。

キャラアイコンは既存の `SerifCharaVectorResource.RES` から生成しています。画像・写真・キャラクターなどの素材には各素材の利用条件が適用されます。

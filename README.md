# 命の砂時計

自分の意思で暮らす人々を見守る、Godot 4.7.2の3D人生シミュレーション。現在は、複数室の家、自然な全身動作、人物の背景、出生から死去までの生活を土台から作り直している。

開発の正本は[8段階のロードマップ](docs/development-roadmap.md)。段階1「家族が一日暮らせる家」は未完了。[現在の状態と未確認点](docs/verification/current-status.md)を確認してから作業する。

## 開発を再開する

作業ブランチは `codex/life-foundation-rebuild`、現行PRは [#30](https://github.com/hayatok/hourglass_of_life/pull/30)。別セッション用の[開始プロンプト](docs/session-start.txt)を用意している。

最初に `AGENTS.md`、ロードマップ、現在の状態、[実装契約](docs/design/foundation-implementation.md)を読む。必要になったソースだけを調べ、過去のログや検証結果をまとめて読み込まない。

## 新しい生活基盤を起動する

```sh
godot --headless --editor --path . --import --quit
godot --path . res://game/foundation/foundation_world.tscn
```

`godot` はインストールした実行ファイルに読み替える。macOSの配置例は `/Applications/Godot.app/Contents/MacOS/Godot`。

新基盤は `game/foundation/` と `data/foundation/`。既定の `game/scenes/main.tscn` は旧12人の町なので、新基盤の動作確認と混同しない。開発セーブの下位互換は維持しない。既存の利用者セーブは整理の対象外とする。

ローカルで残す配布物は `builds/foundation-preview-20261105-r3/hourglass-of-life-foundation-preview-20261105-macOS.zip` の1件。これは以前に短い実機確認をしたプレビューで、現在の途中実装や新しい渚モデルを含まない。

## 設計と素材

- [家族の一日と生活設備](docs/design/life-foundation.md)
- [街並みの造形方針](docs/design/town-art-direction.md)
- [人物・衣服の方向](docs/design/family-visual-direction.md)
- [統計と生活史](docs/life-course-evidence.md)
- [渚の制作仕様](assets/models/foundation-family/CH_Nagisa/asset-brief.md)
- [CMU動作原本と再生成方法](assets/motion-sources/cmu/README.md)

原本・制作マスター・制作入力は `assets/` に保持する。生成ログやレンダーはGit管理せず、必要な範囲を再生成する。Pythonの素材制作環境は `tools/setup_asset_tools.sh` で用意する。

## 検証

[検証の方針](docs/verification/README.md)に従う。実際の動作・状態変化・接触・描画・保存再開を根拠にし、識別用SHAやハッシュをテストに数えない。

```sh
python3 -m unittest discover -s tests -p 'test_cmu_*.py'
python3 tools/verify_game.py --checks home_navigation household_day
```

現在の基盤統合は未受入であり、全検証が通る状態とはしていない。対象に関係する確認を先に行い、その後に実ゲームで一連の生活を確認する。過去の成功記録を現在の品質へ引き継がない。

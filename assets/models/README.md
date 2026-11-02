# 3Dモデルの制作資料

画像資料は `assets/artwork/v02-jrpg/`、編集用のBlenderファイルと検証はこのフォルダ、ゲームへ渡すGLBは `game/assets/models/` に置く。このフォルダの `.gdignore` により、原画や中間ファイルをゲームへ自動で取り込まない。

現在は[渚のモデル](CH_Nagisa/README.md)を代表例として制作中。8人と町全体の完成を意味しない。輪郭、素材、骨と表情、動き、書き出し、Godotでの動作を順に確認する。制作中のモデルでも、実際の町で使って問題を見つけられるようにする。

数値計測・比較画像のPython環境は、リポジトリのルートで `bash tools/setup_asset_tools.sh` を実行して準備する。Blender本体のPythonから動かす工程にはこの仮想環境を使わない。Blender 5.2.1、Godot 4.7.2で確認している。

`CH_Nagisa/build/mesh_helpers.py` は、ローカルの `blender-image-to-3d` スキルに付属する `assets/build_template.py` をコピーした制作補助。元スキルのライセンス表記はMIT。各工程と原画、モデル、パレットはこのプロジェクト向けに制作した。ファルコムのモデル、テクスチャ、モーション、音楽は含まない。

# 3Dモデルの制作資料

画像資料は `assets/artwork/v02-jrpg/`、編集用のBlenderファイルと検証はこのフォルダ、ゲームへ渡すGLBは `game/assets/models/` に置く。このフォルダの `.gdignore` により、原画や中間ファイルをゲームへ自動で取り込まない。

現在は[渚](CH_Nagisa/README.md)、[亮](CH_Ryo/README.md)、[凛](CH_Rin/README.md)、[成長後の凛](CH_RinAdult/README.md)をGodotの町へ取り込んでいる。住人は3人分で、8人と町全体の完成を意味しない。造形の最終受け入れは継続中。制作途中でも実際の町で使い、体格ごとの動きや衣服の問題を見つける。

骨と表情の名前、素材と書き出しの契約を共通にし、体格・顔・髪・衣服を人物ごとに制作する。[共通工程](common/README.md)は原画の輪郭、身長、頭身、肩幅、腕の長さ、立ち幅を形状と骨の両方へ反映する。寸法はゲーム用の設計値であり、人間の統計の推定値ではない。

数値計測・比較画像のPython環境は、リポジトリのルートで `bash tools/setup_asset_tools.sh` を実行して準備する。Blender本体のPythonから動かす工程にはこの仮想環境を使わない。Blender 5.2.1、Godot 4.7.2で確認している。

`CH_Nagisa/build/mesh_helpers.py` は、ローカルの `blender-image-to-3d` スキルに付属する `assets/build_template.py` をコピーした制作補助。元スキルのライセンス表記はMIT。各工程と原画、モデル、パレットはこのプロジェクト向けに制作した。ファルコムのモデル、テクスチャ、モーション、音楽は含まない。

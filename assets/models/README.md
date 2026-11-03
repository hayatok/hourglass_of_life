# 3Dモデルの制作資料

画像資料は `assets/artwork/v02-jrpg/`、編集用のBlenderファイルと検証はこのフォルダ、ゲームへ渡すGLBは `game/assets/models/` に置く。このフォルダの `.gdignore` により、原画や中間ファイルをゲームへ自動で取り込まない。

現在は住人8人全員と成長後の凛をGodotの町へ取り込んでいる。[渚](CH_Nagisa/README.md)、[亮](CH_Ryo/README.md)、[凛](CH_Rin/README.md)、[成長後の凛](CH_RinAdult/README.md)、[修](CH_Osamu/README.md)、[文](CH_Fumi/README.md)、[真帆](CH_Maho/README.md)、[律](CH_Ritsu/README.md)、[葵](CH_Aoi/README.md)に原画比較と機能検査を記録する。造形の最終受け入れと町の制作は継続中。制作途中でも実際の町で使い、体格ごとの動きや衣服の問題を見つける。

骨と表情の名前、素材と書き出しの契約を共通にし、体格・顔・髪・衣服を人物ごとに制作する。[共通工程](common/README.md)は原画の輪郭、身長、頭身、肩幅、腕の長さ、立ち幅を形状と骨の両方へ反映する。寸法はゲーム用の設計値であり、人間の統計の推定値ではない。

[家具と小物10点](PR_LifeFurniture/README.md)は `game/assets/furniture/` へ渡す。人物の手や足と家具の接触位置はGodotの保存シーンに置き、住人の体格に合わせて位置と姿勢を調整する。人物と家具の造形の最終受け入れは継続中。

数値計測・比較画像のPython環境は、リポジトリのルートで `bash tools/setup_asset_tools.sh` を実行して準備する。Blender本体のPythonから動かす工程にはこの仮想環境を使わない。Blender 5.2.1、Godot 4.7.2で確認している。

`CH_Nagisa/build/mesh_helpers.py` は、ローカルの `blender-image-to-3d` スキルに付属する `assets/build_template.py` をコピーした制作補助。元スキルのライセンス表記はMIT。各工程と原画、モデル、パレットはこのプロジェクト向けに制作した。ファルコムのモデル、テクスチャ、モーション、音楽は含まない。

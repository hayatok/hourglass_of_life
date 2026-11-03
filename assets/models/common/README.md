# 人物モデルの共通工程

渚で用意した骨・表情・素材・GLBの工程を、残り7人と成長後の凛の体格と衣装にも適用する。35本の骨と6表情の名前を共通にし、人物の識別を色替えだけに頼らない。

`pipeline.py` は各人物の `profile.json` と番号付き工程を読み込み、その人物のフォルダへ編集用ファイルと書き出しを保存する。渚の番号付きスクリプトをリグ・素材・書き出しのテンプレートとして使い、`resident_forms.py` が別の髪、顔、シャツ、オーバーオール、脚や靴を制作する。`cast_forms.py` は前掛け、カーディガンと長いスカート、ニット、フード付き上着、眼鏡、カメラ、ヘッドホン、リュックを制作する。カメラなどの硬い物は胸へ固定し、長いスカートは腰・太腿・すねへ加重して着席時にも裾が下がるようにする。

原画の正面をマット化して、疎な高さの輪郭を衣服・脚のロフトに使う。髪の細い先端、顔の奥行き、隠れた人体、素材の反応、動きは推定。側面の腕が下がり、正面では開いているため、同じ姿勢を仮定して三方向の全身輪郭を合格扱いにしない。

体格の変換は `CH_Nagisa/build/dimensions.py` に集約した。身長と頭の大きさ、肩幅、腕の長さ、腕の開き、立ち幅、つま先の向きを、形状と休止姿勢の骨・表情・ソケットへ同じ規則で反映する。中央の腰や地面の根元を左右へ割らず、変換前へ戻した各頂点との誤差も検査する。寸法と加齢表現は架空の人物の制作設定であり、生物学的な予測ではない。

```sh
bash tools/setup_asset_tools.sh
builds/asset-tools/bin/python tools/prepare_resident_assets.py
# 以降はBLENDERを実行ファイルへ置き換える。各人物で同じ順番。
BLENDER --background --python-exit-code 1 --python assets/models/CH_Ryo/build/02_blockout.py
BLENDER --background --python-exit-code 1 --python assets/models/CH_Ryo/build/03_forms.py
BLENDER --background --python-exit-code 1 --python assets/models/CH_Ryo/build/04_topology.py
BLENDER --background --python-exit-code 1 --python assets/models/CH_Ryo/build/05_materials.py
BLENDER --background --python-exit-code 1 --python assets/models/CH_Ryo/build/06_rig.py
BLENDER --background --python-exit-code 1 --python assets/models/CH_Ryo/build/08_animation.py
BLENDER --background --python-exit-code 1 --python assets/models/CH_Ryo/build/08_check_animation.py
BLENDER --background --python-exit-code 1 --python assets/models/CH_Ryo/build/09_export.py
BLENDER --background --python-exit-code 1 --python assets/models/CH_Ryo/build/09_check_import.py
builds/asset-tools/bin/python tools/install_resident_models.py
python3 tools/verify_game.py --gpu
```

校正・比較・検査・書き出しには `blender-image-to-3d` スキルの補助を使う。別の場所へ置いた場合は `BLENDER_ASSET_SKILL` にそのルートを設定する。`prepare_resident_assets.py` は原画、マット、測定値、profile、工程の入口を再作成する。手で編集した内容は先に別名保存し、維持する変更を共通工程かprofileへ記録する。

原画との最終比較が残るモデルも、機能の検査に合格した制作途中の状態で町へ渡している。輪郭、顔の似方、布と体、家具や道具との接触を完成扱いにしない。`tools/install_resident_models.py` が確認するのは、動き・表情・LODの再読み込みと寸法の契約であり、造形の最終承認ではない。

複数人の番号付き工程は `python3 tools/build_resident_assets.py --names Osamu Fumi Maho Ritsu Aoi --stages 02 03` のように明示して実行できる。依存する工程は人物ごとに順番に実行し、失敗時は停止する。生ログは `builds/asset-build/` に残す。比較画像は asset-tools のPythonで `tools/review_resident_assets.py --phase 03 Osamu Fumi Maho Ritsu Aoi` を実行して作る。02と03は原画の実寸の窓へ合わせた正面比較も保存する。横向きの腕の姿勢が異なる側面を、同じ姿勢の寸法検査とは扱わない。

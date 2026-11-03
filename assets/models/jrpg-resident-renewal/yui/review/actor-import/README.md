# 結衣の制作段階: 実actorへの接続

新しい個別GLBを実際の `ResidentAvatar` とキャラクターsceneへ接続した。外見scale1、36骨（元の35骨と `DEF-skirt_middle`）、9動作、個別UV眼layoutを使う。GLBの形状・UV・skin・動作はこの接続作業では変更していない。

この確認は独立stageで明示的にclipを再生したものである。初期状態から本人データを複製して使い、シミュレーションの時間は進めていない。自律行動や町での家具接触・睡眠・食事・保存再開の受入れとは区別する。

確認した挙動:

- 頭と両手の有限な位置、9clipの読み込み、walk/talk/workでの実際の骨の移動。
- 36骨・skin bindと実際のLOD三角形。LOD0→1→2→0で骨・ポーズ・再生時刻・所有material・非ゼロの眼値を継続する。
- 追加middle骨が座位/rest/eatで立位から約1.419rad回転し、2866頂点の実weightを持つ。`pose-sit_talk.png` でも裾が座位へ動くことを確認した。
- 実sleepで閉眼し、idleへ戻ると開眼、疲労でTiredEyes値が変わる。実GPUの開眼・閉眼・疲れ目・斜め閉眼画像で目を確認した。
- 新rigからHaru/Tomoと同じ画角・背景の肖像を生成し、Godotへ再importした。

実capabilityは `TEXTURE_EYES` / `2chart` / `compress`。Blink/TiredEyesだけが有効であり、Smile・口/顎の変形・リップシンク・新atlasの白髪化は未対応。

headlessとGPUは同じactor機能44/44。画像8枚の出力成功は `artifacts` に別記し、機能件数へ加算しない。SHAやfingerprintを合否・件数に使っていない。`headless.log` / `gpu.log` にERRORはない。

再現コマンド（プロジェクトルートから、他の重い制作処理と時間を分けて実行）:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script assets/models/jrpg-resident-renewal/tomo/build/check_actor_import.gd -- --resident=yui
/Applications/Godot.app/Contents/MacOS/Godot --path . --script assets/models/jrpg-resident-renewal/tomo/build/check_actor_import.gd -- --resident=yui --portrait
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
```

結衣の後ろ髪と枕/寝床の接触はこの家具なしstageでは確認していない。実町の睡眠で別途見る必要がある。

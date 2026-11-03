# 智の制作段階: 実actorへの接続

智の新しい35骨・9動作のモデルを、実際の `ResidentAvatar` とキャラクターsceneを通して読み込んだ。身長は1.70m、外見scaleは1、測定した歩行clip速度は2.13660552m/s。以前の色見本による塗替えを無効にし、個別UVの2chart/compress方式でBlinkとTiredEyesを接続した。GLBの形状・UV・skin・動作はこの接続作業では変更していない。

この確認は制作用の独立stageである。seed711/12人の初期状態から本人データを複製し、原点のactorで明示的にclipを再生した。シミュレーションの時刻を進めていないため、自律行動、町での家具接触、保存復帰、自然な会話・制作の受入れ結果ではない。それらは町の検証で別に確認する。

確認した挙動:

- 頭と両手の骨が有限な別位置へ解決され、実際のwalk/talk/work clipで動く。
- 9clipを実際に読み込める。LOD0→1→2→0でskin bindを保ち、同じ骨・再生時刻・ポーズ・所有materialを継続する。
- 非ゼロのBlink/TiredEyes値がLOD後も残る。sleepで閉眼し、idleへ戻ると開眼、疲労でTiredEyes値が変わる。
- 実GPU画像で正面の開眼・閉眼・疲れ目、斜めの閉眼を表示した。白目の残りや眼以外の塗りの崩れは今回の画像では見られない。口の表情は元atlasのまま。
- 新rigからHUD用肖像を作成し、Haruの現肖像と同じ画角・背景で整合させた。

`checks-headless.json` / `checks-gpu.json` は同じ39/39のactor機能確認。stage画像6枚と肖像1枚の出力成功は、検査件数とは別の `artifacts` に記録した。初回GPUログの46件は画像書込7件を含む旧集計として保持し、末尾に区分を追記した。SHAや画像fingerprintの照合は実施せず、検査件数にも含めていない。ログにERRORはない。

再現コマンド（プロジェクトルートから、他の重い制作処理と時間を分けて実行）:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script assets/models/jrpg-resident-renewal/tomo/build/check_actor_import.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --script assets/models/jrpg-resident-renewal/tomo/build/check_actor_import.gd -- --portrait
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --import
```

`headless.log` / `gpu.log` / `portrait-import.log` とJSONがこのstageの記録。Smile・口や顎の変形・リップシンク・新atlasの白髪化は未対応で、実capabilityはBlink/TiredEyesの2つだけである。

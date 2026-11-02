# 命の砂時計

自分の意思で暮らす住人たちに、小さなきっかけを渡す3D人生シミュレーション。

プレイヤーは町の暮らしを観察し、場所を整え、予定を提案し、迷っている人を少し後押しする。住人は仕事、家庭、趣味、人付き合いに自分の時間を使い、その経験から次の行動を選ぶ。

Godot 4.7.2で開発する3D人生シミュレーション。v0.1で日常と働きかけ、v0.2で関係と記憶を接続し、v0.3では仕事と家庭の生活条件を実装した。8人が日課と欲求から動き、交流、日時のある約束、実際の行動から生まれる習慣を積み重ねる。働いた時間による収入、家の用事、世話の交代、本人の目標を進める共同制作も暮らしにつながる。

人物と町は仮モデル。加齢と継承、JRPG調の完成用モデル、音と演出、一連の進行の仕上げは後続版で実装する。

## 起動と操作

Godot 4.7.2で `project.godot` を開き、プロジェクトを実行する。macOS向けの配布物はGitHubのリリースへ版ごとに保存する。

- 人物一覧または町の人をクリックすると、事情や予定、関係、記憶を見られる。
- 下部から休息、本人の目標、相手との交流を提案できる。本人が予定や疲れから返答する。
- 相手を選んで手助けや共同制作を相談できる。手助けは実際の合流後から生活の負担を分け、制作は一緒に作業した時間から目標が進む。「暮らし」タブで家計、家の用事、仕事、世話の時間を見られる。
- ベンチを置くと、広場で過ごせる場所が増える。使用するかは住人が選ぶ。
- WASDでカメラ移動、右ドラッグで回転、ホイールでズーム。人物への追従も選べる。
- Spaceで一時停止、Escapeでメニュー。メニューから保存と再開ができる。

保存先はGodotの `user://life-save.json`。macOSでは `~/Library/Application Support/Godot/app_userdata/命の砂時計/` に置かれる。新しい保存がない場合にはv0.1の `life-save-v01.json` も読み込める。

## 開発と検証

[GitHub](https://github.com/hayatok/hourglass_of_life)のIssueとMilestoneで、[版ごとの中心となる遊び](docs/development-roadmap.md)を管理する。[メニュー・HUD・動きの設計](docs/interface-and-animation.md)も参照。

```sh
godot --headless --editor --import --path .
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_social_life.gd
godot --headless --path . --script tests/test_work_family.gd
godot --path . --script tests/test_scene.gd
```

`godot` はGodot実行ファイルのパスに読み替える。最後の確認はGPUを使用し、タイトル、会話、記憶、約束、共同制作と暮らしの画面を `docs/verification/v0.3/` へ保存する。Godotのシーンエディタで編集した `.tscn` と、保存されたAnimationPlayerのクリップを実行時に使用する。初期シーンの作成補助は `tools/build_scenes.gd` に残しているが、再実行すると後の版の編集を上書きする。

## 制作方針

家の中まで見える3Dの箱庭と、日本のJRPGを参考にしたアニメ調3Dの人間キャラクターを採用する。大人は6頭身前後、子どもは4〜4.5頭身を制作時の目安とする。視線、姿勢、身振り、座る場所から、人物の気持ちや関係が伝わることを重視する。

歴史資料、公的統計、行動科学の知見を、生活の条件と行動の仕組みに反映する。統計の平均値、研究上の知見、ゲーム用の仮設定を区別する。

## 設計資料

- [ゲーム企画](docs/game-design.md)
- [キャラクター行動仕様](docs/character-spec.md)
- [調査資料と仕様への反映](docs/research-notes.md)
- [行動モデルの設定案](data/behavior-model.json)
- [試作に登場する8人の設定案](data/residents.json)
- [町 人物 建物 家具のJRPG調アートワーク](assets/artwork/v02-jrpg/README.md)
- [初期アートワーク](assets/artwork/v01/README.md)

## 最初の試作

3世帯8人が暮らす町に、住宅、工房、パン屋兼喫茶店、広場を置く。仕事や学校への町外移動も生活時間に含める。

最初に確かめるのは、住人が自律的に暮らすこと、働きかけへの返答に理由があること、その結果を3Dの動きから読み取れること。長期の加齢や世代交代は、この日常が成立したあとに組み込む。

設定ファイルは実装への入力案であり、実測に合わせて調整した行動モデルではない。採点式、係数、架空の人物設定はゲーム用の設計値。

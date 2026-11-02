# 命の砂時計

自分の意思で暮らす住人たちに、小さなきっかけを渡す3D人生シミュレーション。

プレイヤーは町の暮らしを観察し、場所を整え、予定を提案し、迷っている人を少し後押しする。住人は仕事、家庭、趣味、人付き合いに自分の時間を使い、その経験から次の行動を選ぶ。

Godot 4.7.2で開発する3D人生シミュレーション。v0.1で日常と働きかけ、v0.2で関係と記憶、v0.3で仕事と家庭を接続し、v0.4では年月と人生の変化を実装した。8人が自分の予定、欲求、責任、関係から暮らし、働いた時間による家計、家の用事、世話の交代、共同制作を積み重ねる。

最初の3年を見守ると、その町で起きたことを振り返れる。その後も、卒業と転居、成長に伴う役割の変更、働き方の変更、別れを経て暮らしが続く。完成した取り組みの記録は3Dの町に置かれ、別の人が実際に読んで、自分の取り組みの参考にする。全員の生涯を見届けた後には、残された記録を読み返せる。

v0.5の開発ブランチでは、渚のJRPG調モデル、表情と動きを制作し、実際の町へ取り込んでいる。[人物モデルの制作確認](docs/verification/v0.5/README.md)を参照。残りの人物と町、家具との位置合わせ、音と演出、導入と一連の進行の仕上げは未完了。

## 起動と操作

Godot 4.7.2で `project.godot` を開き、プロジェクトを実行する。macOS向けの配布物はGitHubのリリースへ版ごとに保存する。

- 人物一覧または町の人をクリックすると、事情や予定、関係、記憶を見られる。
- 下部から休息、本人の目標、相手との交流を提案できる。本人が予定や疲れから返答する。
- 相手を選んで手助けや共同制作を相談できる。手助けは実際の合流後から生活の負担を分け、制作は一緒に作業した時間から目標が進む。「暮らし」タブで家計、家の用事、仕事、世話の時間を見られる。
- ベンチを置くと、広場で過ごせる場所が増える。使用するかは住人が選ぶ。
- WASDでカメラ移動、右ドラッグで回転、ホイールでズーム。人物への追従も選べる。
- Spaceで一時停止、Escapeでメニュー。メニューから保存と再開ができる。
- ×0.5でゆっくり観察し、×30で年月を早く見届けられる。早送りでも移動と参加を省略しない。「町の記録」で、実際の節目と残された物を振り返れる。

保存先はGodotの `user://life-save.json`。macOSでは `~/Library/Application Support/Godot/app_userdata/命の砂時計/` に置かれる。新しい保存がない場合にはv0.1の `life-save-v01.json` も読み込める。

## 開発と検証

[GitHub](https://github.com/hayatok/hourglass_of_life)のIssueとMilestoneで、[版ごとの中心となる遊び](docs/development-roadmap.md)を管理する。[メニュー・HUD・動きの設計](docs/interface-and-animation.md)も参照。

```sh
godot --headless --editor --import --path .
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_social_life.gd
godot --headless --path . --script tests/test_work_family.gd
godot --headless --path . --script tests/test_life_course.gd
godot --path . --script tests/test_scene.gd
godot --path . --script tests/test_character_model.gd
```

`godot` はGodot実行ファイルのパスに読み替える。シーン全体の確認はGPUを使用し、操作、共同制作、3年の振り返り、全員の生涯を見届けた画面まで `docs/verification/v0.5/integration/` へ保存する。人物の確認は `docs/verification/v0.5/nagisa/` へ保存する。Godotのシーンエディタで編集した `.tscn` と、保存されたAnimationPlayerのクリップを実行時に使用する。初期シーンの作成補助は `tools/build_scenes.gd` に残しているが、再実行すると後の版の編集を上書きする。

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

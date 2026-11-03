# 命の砂時計

自分の意思で暮らす住人たちに、小さなきっかけを渡す3D人生シミュレーション。

プレイヤーは町の暮らしを観察し、場所を整え、予定を提案し、迷っている人を少し後押しする。住人は仕事、家庭、趣味、人付き合いに自分の時間を使い、その経験から次の行動を選ぶ。

Godot 4.7.2で開発する3D人生シミュレーション。v0.1で日常と働きかけ、v0.2で関係と記憶、v0.3で仕事と家庭を接続し、v0.4では年月と人生の変化を実装した。現在の新規開始は12人。住人が自分の予定、欲求、責任、関係から暮らし、働いた時間による家計、家の用事、世話の交代、共同制作を積み重ねる。

最初の3年を見守ると、その町で起きたことを振り返れる。その後も、卒業と転居、成長に伴う役割の変更、働き方の変更、別れを経て暮らしが続く。完成した取り組みの記録は3Dの町に置かれ、別の人が実際に読んで、自分の取り組みの参考にする。全員の生涯を見届けた後には、残された記録を読み返せる。

v0.5の開発ブランチでは、8人全員のJRPG調モデルと、成長後の凛、表情と動きを実際の町へ取り込んでいる。年齢が進むと凛の体格が切り替わり、髪色も変わる。家具10点と予約する席・作業場所を接続し、着席、カップを使う食事、子どもの踏み台、専用の寝床を使用する。[人物モデル](docs/verification/v0.5/README.md)と[家具・動作の制作確認](docs/verification/v0.5/activities/README.md)を参照。人物と町の造形、道具ごとの細かな操作や衣服との重なり、音と演出、導入と一連の進行の仕上げは未完了。

v0.6の開発では共同活動6種類を人物の組合せから独立した定義へ移した。住人は関心、技能、本人が知る相手の情報、実際に空いている場所と時間から、自分で共同作業や会話を相談する。暮らしの負担が大きいときは、信頼する知人へ手助けを頼む。

約束には本人の食事・休息と往復の時間を見込み、それぞれが準備して移動する。都合が変われば双方が同意したときだけ日時を相談し直す。実際の会話では、話し手が知る過去の情報から相手の関心や願いに合う相談先を教える。聞いただけでは技能を得ず、一緒に作業した経験から技能と状況別の期待を更新する。

住人一覧・人物詳細・履歴は畳めるようにし、人物追従では近くへ寄って見る。人物画面では現在の相手、紹介のきっかけ、次の約束、直近の結果を確認できる。[制作と検証の範囲](docs/verification/v0.6/README.md)を参照。[12人の段階検証](docs/verification/v0.8/README.md)を人口拡張から前倒しした。16人・24人への増員、複数人の集まり、経験から変わる人生、表現全体の仕上げは引き続き開発する。

## 起動と操作

Godot 4.7.2で `project.godot` を開き、プロジェクトを実行する。macOS向けの配布物はGitHubのリリースへ版ごとに保存する。

- 人物一覧または町の人をクリックすると、事情や予定、関係、記憶を見られる。
- 下部から休息、本人の目標、相手との交流を提案できる。本人が予定や疲れから返答する。
- 相手を選んで手助けや共同制作を相談できる。手助けは実際の合流後から生活の負担を分け、制作は一緒に作業した時間から目標が進む。「暮らし」タブで家計、家の用事、仕事、世話の時間を見られる。
- ベンチを置くと、広場で過ごせる場所が増える。使用するかは住人が選ぶ。
- WASDでカメラ移動、右ドラッグで回転、ホイールでズーム。人物への追従も選べる。
- Spaceで一時停止、Escapeでメニュー。メニューから保存と再開ができる。
- ×0.5でゆっくり観察し、×30で年月を早く見届けられる。早送りでも移動と参加を省略しない。「町の記録」で、実際の節目と残された物を振り返れる。
- 「住人」「人物」「履歴」で画面を畳める。進行速度は上部の速度メニューで変更する。

保存先はGodotの `user://life-save.json`。macOSでは `~/Library/Application Support/Godot/app_userdata/命の砂時計/` に置かれる。開発中は版をまたぐ保存互換を維持せず、現行版の保存・再開と再現を確認する。

## 開発と検証

[GitHub](https://github.com/hayatok/hourglass_of_life)のIssueとMilestoneで、[版ごとの中心となる遊び](docs/development-roadmap.md)を管理する。[メニュー・HUD・動きの設計](docs/interface-and-animation.md)も参照。

```sh
godot --headless --editor --import --path .
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_social_life.gd
godot --headless --path . --script tests/test_work_family.gd
godot --headless --path . --script tests/test_life_course.gd
godot --headless --path . --script tests/test_cognition.gd
godot --headless --path . --script tests/test_resident_activities.gd
godot --headless --path . --script tests/test_autonomy.gd
godot --path . --script tests/test_observation_hud.gd
godot --path . --script tests/test_scene.gd
godot --path . --script tests/test_character_model.gd
godot --path . --script tests/test_resident_models.gd
godot --path . --script tests/test_activity_furniture.gd
```

`godot` はGodot実行ファイルのパスに読み替える。シーン全体の確認はGPUを使用し、操作、共同制作、3年の振り返り、全員の生涯を見届けた画面まで `docs/verification/v0.6/integration/` へ保存する。人物の確認は `docs/verification/v0.5/nagisa/` へ保存する。Godotのシーンエディタで編集した `.tscn` と、保存されたAnimationPlayerのクリップを実行時に使用する。初期シーンの作成補助は `tools/build_scenes.gd` に残しているが、再実行すると後の版の編集を上書きする。

通常の新規開始は初期乱数を変える。開発時に同じ開始条件を使う場合は、`godot --path . -- --world-seed=71103` のように指定する。保存には初期seedと現在の乱数状態、知識、経験、進行中の計画を含める。

`python3 tools/verify_game.py --gpu` で、エンジンの終了コード・エラーログ・各テストの完了表示も照合できる。必要に応じて `--godot` に実行ファイルを指定する。亮・凛・成長後の姿と加齢の描画は `docs/verification/v0.5/cast/`、ローカルの実行ログは `builds/verification/` へ保存する。

## 制作方針

家の中まで見える3Dの箱庭と、日本のJRPGを参考にしたアニメ調3Dの人間キャラクターを採用する。大人は6頭身前後、子どもは4〜4.5頭身を制作時の目安とする。視線、姿勢、身振り、座る場所から、人物の気持ちや関係が伝わることを重視する。

歴史資料、公的統計、行動科学の知見を、生活の条件と行動の仕組みに反映する。統計の平均値、研究上の知見、ゲーム用の仮設定を区別する。

## 設計資料

- [ゲーム企画](docs/game-design.md)
- [キャラクター行動仕様](docs/character-spec.md)
- [調査資料と仕様への反映](docs/research-notes.md)
- [行動モデルの設定案](data/behavior-model.json)
- [住民12人の設定](data/residents.json)
- [町 人物 建物 家具のJRPG調アートワーク](assets/artwork/v02-jrpg/README.md)
- [JRPG調の立体表現の追加アートワーク](assets/artwork/v03-render-target/README.md)
- [初期アートワーク](assets/artwork/v01/README.md)

## 最初の試作

3世帯8人が暮らす町に、住宅、工房、パン屋兼喫茶店、広場を置く。仕事や学校への町外移動も生活時間に含める。

最初に確かめるのは、住人が自律的に暮らすこと、働きかけへの返答に理由があること、その結果を3Dの動きから読み取れること。長期の加齢や世代交代は、この日常が成立したあとに組み込む。

設定ファイルは実装への入力案であり、実測に合わせて調整した行動モデルではない。採点式、係数、架空の人物設定はゲーム用の設計値。

# 住民モデル更新の参照画像

晴の採用案と同じ線・セル塗り・頭身で制作した、残り11人と成長後の凛の全身参照。画像生成は組み込みimagegenを使用し、各ファイルに実際のプロンプトを添える。参照元と素材の識別情報は [references.json](references.json) に記録する。SHAや画素ハッシュは品質の合否や検査件数に使わない。

## 共通の造形

- アニメの輪郭線と段階のある陰影を使う。顔、髪の房、衣服の輪郭が町のカメラでも読める形にする。
- 成人はおおむね6頭身。凛の子ども姿は4〜4.25頭身、成長後は6頭身を目安にする。
- 年齢、髪型、服の配色、仕事や趣味の持ち物を人物の手がかりとして保つ。全年齢を同じ若い顔にそろえない。
- 正面全身のAポーズを原型の入力にする。背面、奥行き、実寸、隠れた衣服の構造は制作時の推定として記録する。

## 制作状況

| 人物 | 参照画像 | 更新状況 |
|---|---|---|
| 咲 | [画像](saki-concept-v1.png) | 専用body・36骨・9動作・3LOD。閉眼/疲れ目は3chart。実町の人物動作を部分受入れ |
| 智 | [画像](tomo-concept-v1.png) | 専用body・35骨・9動作・3LOD。閉眼/疲れ目は2chart。実町の人物動作を部分受入れ |
| 結衣 | [画像](yui-concept-v1.png) | 専用body・36骨・9動作・3LOD。閉眼/疲れ目は2chart。実町の人物動作を部分受入れ |
| 葵 | [画像](aoi-concept-v1.png) | 未生成 |
| 真帆 | [画像](maho-concept-v1.png) | 未生成 |
| 渚 | [画像](nagisa-concept-v1.png) | 未生成 |
| 亮 | [画像](ryo-concept-v1.png) | 未生成 |
| 修 | [画像](osamu-concept-v1.png) | 未生成 |
| 文 | [画像](fumi-concept-v1.png) | 未生成 |
| 律 | [画像](ritsu-concept-v1.png) | 未生成 |
| 凛 | [画像](rin-concept-v1.png) | 未生成 |
| 凛（成長後） | [画像](rin_adult-concept-v1.png) | 未生成 |

晴は [先行制作の記録](../cute-cast-pilot/README.md) と [実ゲームの検証](../../../docs/verification/v0.5/haru-jrpg-gameplay/) で管理する。

咲・智・結衣は、Tripoで各30credits、計90creditsを使って生成したrawを保持し、その後ローカルで専用の骨・skin・9動作・LODと個別UVの眼を接続した。元の生成条件、credit、rawの内容は各 `generation.json` に履歴として残す。上表の残り8人と成長後の凛について、この更新用3Dの新規生成・置換はまだ行っていない。

制作の編集用正本は [咲](../../models/jrpg-resident-renewal/source/saki/CH_Saki_AnimationMaster.blend)、[智](../../models/jrpg-resident-renewal/source/tomo/CH_Tomo_AnimationMaster.blend)、[結衣](../../models/jrpg-resident-renewal/source/yui/CH_Yui_AnimationMaster.blend) のAnimationMaster。ゲームで使う納品物は `game/assets/models/{saki,tomo,yui}/` と各sceneで管理する。各 `exports/` は再生成できるbody用の作業出力であり、現在の顔設定を含むゲーム側の正本とは区別する。

[実町の人物動作の記録](../../../docs/verification/v0.5/jrpg-renewal-gameplay/README.md)では、通常の12人の町をseed711で進め、歩行、会話の頭向きと手振り、自然に成立した共同制作と技能変化、食事、本人の寝床での睡眠・閉眼・再開眼、制作中の保存再開を確認した。headless112件・GPU115件は失敗0。保存した29画像はartifactsとして別記し、機能件数へ加算していない。これはエージェントによる人物動作の部分受入れで、人によるUI試遊や面白さの評価ではない。

残る項目:

- 顔はBlink/TiredEyesの2つだけ。6制御の表情、Smileや口・顎の変形、リップシンクは未完。
- 新atlasでの髪の加齢、足滑りの解消、活動ごとの道具と指先の操作は未完。
- 衣服・後ろ髪と寝具の接触は全姿勢で解決していない。結衣の髪と枕は重なり、髪や枕の変形はない。
- 夜の暗さ、朝の肌の白飛び、混雑時の身体の重なりが残る。
- 人によるUI試遊、プレイヤーの目的の伝わりやすさ、ゲームとしての面白さは未受入れ。UIは別途全面見直しを進める。

参照画像や静止原型、人物動作の検査だけで住民更新の全体を完了扱いにしない。

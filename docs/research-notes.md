# 命の砂時計の調査資料と仕様への反映

確認日 2026年11月3日

現代日本を参考にした架空の町を設計するため、公的な生活時間統計、生活制度の歴史、性格や動機づけ、習慣、対人関係に関する原著論文と著者側の解説を確認した。

公的な集計値は生活の条件を比較する材料、観察研究は関連の候補、理論は人物の状態を分けて考える材料として使う。研究から、架空の住人の性格値や行動確率を直接推定することはしない。以下の「仕様への反映」はゲーム用の設計判断を示す。

## 公的統計

### R01 社会生活基本調査の生活時間

資料は総務省統計局「令和3年社会生活基本調査 生活時間及び生活行動に関する結果 結果の概要」。2021年の調査結果で、概要の公表は2022年8月31日。

[結果の概要 PDF](https://www.stat.go.jp/data/shakai/2021/pdf/gaiyoua.pdf)の冊子2ページ表1-1、4〜5ページ表2-2と前後の説明を確認した。10歳以上の週全体の一日平均は睡眠7時間54分、仕事3時間28分。6歳未満の子どもがいる「夫婦と子供の世帯」の家事関連時間は夫1時間54分、妻7時間28分。家事関連には家事、介護・看護、育児、買い物を含む。

仕様への反映は睡眠、仕事、家事、交流、移動を別々に計上し、世帯内の責任が自由時間に影響するようにすること。仕事3時間28分は非就業者や休日も含む集計で、就業日の勤務時間には使わない。男女差を生得的な意欲や得意不得意へ変換しない。

2021年は感染症対策の影響を受けた時期。全体平均だけで現代の暮らしを再現したと判断せず、同資料の2016年との比較や、条件別の表と合わせて使う。

### R02 社会生活基本調査の調査対象と統計表

[調査の概要](https://www.stat.go.jp/data/shakai/2021/gaiyou.html)、[結果と利用上の注意](https://www.stat.go.jp/data/shakai/2021/kekka.htm)、[e-Statの主要統計表](https://www.e-stat.go.jp/stat-search/files?layout=datalist&lid=000001298496&page=1)を確認した。

調査は約9万1千世帯の10歳以上約19万人を対象とし、生活時間は2021年10月16〜24日のうち指定された連続2日間について調べている。統計表は総平均時間、行動者平均時間、行動者率を区別し、平日・土曜・日曜、就業状態、ライフステージなどでも分かれる。

仕様への反映は比較対象の年齢、曜日、就業状態、責任を保存すること。表1-1〜1-4、2-1〜2-4、5-1、7、12-1・12-2を今後の調整で参照する。個人の一日の予定分布や、子どもの生活時間は、これらの集計表だけから復元しない。

## 生活制度の歴史

### R03 週の労働時間の変化

[大阪労働局の説明](https://jsite.mhlw.go.jp/osaka-roudoukyoku/hourei_seido_tetsuzuki/roudoukijun_keiyaku/hourei_seido/jikan2/info.html)の「週40時間制の全面実施は平成9年4月から」を確認した。従来の週48時間から1988年4月以降に段階的に短縮され、1997年4月に一部の特例を除いて週40時間制が全面実施されたと説明されている。

仕様への反映は勤務日、拘束時間、休日、時間の融通を、職場側の条件として性格から分けること。過去の働き方を持つ人物の生活歴にも利用する。法定時間を、その時代の全員の実労働時間として扱わない。この資料は制度の沿革の参照に用いる。

### R04 学校週5日制

文部科学省の[平成14年度からの学習指導要領の説明](https://www.mext.go.jp/a_menu/shotou/cs/1320944.htm)と、当時の[学校施設に関する報告](https://www.mext.go.jp/b_menu/shingi/chousa/shotou/016/toushin/990701.htm)を確認した。後者は2002年度からの完全学校週5日制の導入を説明している。

仕様への反映は学校の予定と保護者の勤務を別に管理すること。子どもに休日があっても、保護者が同時に休めるとは限らない。育った時代の違いを生活歴に持たせる場合も、学習意欲や人柄を世代で決定しない。

## 行動科学

### R05 自律性と動機づけ

Ryan, R. M., & Deci, E. L. 2000. Self-Determination Theory and the Facilitation of Intrinsic Motivation, Social Development, and Well-Being. American Psychologist, 55, 68–78.

[著者側で公開されている論文](https://selfdeterminationtheory.org/SDT/documents/2000_RyanDeci_SDT.pdf)の冒頭と理論の説明を確認した。自己決定理論は自律性、有能感、関係性の欲求と、それを支える社会的な条件を重視する。

仕様への反映は自分で選んだ感覚、上達の実感、人とのつながりを別々に扱い、住人が提案を断る余地を持つこと。この理論からゲームの得点式や三つの欲求の係数は導けない。

### R06 性格を連続した傾向で表す

Soto, C. J., & John, O. P. 2017. The Next Big Five Inventory BFI-2. Journal of Personality and Social Psychology, 113, 117–143. DOI 10.1037/pspp0000096.

[著者のBerkeley Personality Labによる説明](https://www.ocf.berkeley.edu/~johnlab/bfi.html)で、外向性、協調性、勤勉性、否定的情動性、開放性の五領域を確認した。今回は領域の考え方と書誌を参照し、論文全文の検討は行っていない。

仕様への反映は性格を連続値の組として表し、同じ性格でも行動が変わる余地を持たせること。BFI-2の質問項目、採点法、個人の診断をゲームへ組み込まない。ゲームの値は架空の人物用に独自設定する。

### R07 一人の中にも行動の幅がある

Fleeson, W. 2001. Toward a structure- and process-integrated view of personality: traits as density distribution of states. Journal of Personality and Social Psychology, 80, 1011–1027. DOI 10.1037/0022-3514.80.6.1011.

[原著抄録](https://pubmed.ncbi.nlm.nih.gov/11414368/)を確認した。2〜3週間の日常を調べた三つの経験サンプリング研究で、個人内の行動の変動と、個人差の中心傾向の安定性を報告している。

仕様への反映は恒常的な傾向と、その場の役割、疲労、相手への慣れを分けること。職場と家での行動差の具体的な計算は設計判断であり、この抄録から各場面の係数は得られない。

### R08 習慣と手掛かり

Lally, P., van Jaarsveld, C. H. M., Potts, H. W. W., & Wardle, J. 2010. How are habits formed: Modelling habit formation in the real world. European Journal of Social Psychology, 40, 998–1009. DOI 10.1002/ejsp.674.

[出版社の原著抄録](https://onlinelibrary.wiley.com/doi/abs/10.1002/ejsp.674)を確認した。96人が同じ文脈で行う行動を選び、12週間記録した。82人が分析に十分なデータを提供し、習慣化の個人差や、一回の実行機会を逃しても過程への影響が大きくなかったことを報告している。

仕様への反映は手掛かりと行動の組で習慣を保存し、強まりを徐々に小さくすること。一回の欠席で全消去しない。食事・飲水・活動の研究を、あらゆる習慣の確定法則へ広げず、ゲーム内の日数にもそのまま換算しない。

### R09 一緒に過ごした時間と友情

Hall, J. A. 2019. How many hours does it take to make a friend? Journal of Social and Personal Relationships, 36, 1278–1296. DOI 10.1177/0265407518761225. オンライン初出は2018年。

[原著論文](https://journals.sagepub.com/doi/pdf/10.1177/0265407518761225)の抄録、方法、考察を確認した。転居した成人355人と大学新入生112人の調査で、共有時間、活動や会話の内容、関係の親密さの関連を扱う。

仕様への反映は同じ場所にいる時間と、本人たちが関わる時間を分け、共有した内容を記録すること。観察研究であり、仲がよいから一緒にいるという方向もある。「一定時間で必ず友達になる」という閾値や、日本の全世代に共通の時間数には変換しない。

### R10 話すことと相手の応答

Laurenceau, J. P., Barrett, L. F., & Pietromonaco, P. R. 1998. Intimacy as an interpersonal process: the importance of self-disclosure, partner disclosure, and perceived partner responsiveness in interpersonal exchanges. Journal of Personality and Social Psychology, 74, 1238–1251. DOI 10.1037/0022-3514.74.5.1238.

[原著抄録](https://pubmed.ncbi.nlm.nih.gov/9599440/)を確認した。1週間または2週間の交流直後の日誌を使った二研究で、自己開示、相手の開示、相手の応答への受け止めと、親密さの関連を扱う。

仕様への反映は話した内容だけでなく、聞き手の応答と話し手の受け止めを保存すること。自己開示を増やせば誰とでも親しくなるという攻略にはしない。信頼の数値や約束の修復手順は、この研究から直接得たものではない。

### R11 時間の区切りと目標

Carstensen, L. L. 2021. Socioemotional Selectivity Theory: The Role of Perceived Endings in Human Motivation. The Gerontologist, 61, 1188–1196. DOI 10.1093/geront/gnab116.

[原著抄録](https://pubmed.ncbi.nlm.nih.gov/34718558/)と、著者の[Stanford Life-span Development Laboratoryの説明](https://lifespan.stanford.edu/research)を確認した。社会情動的選択性理論は年齢そのもの以上に、残された時間や終わりの知覚と、目標の優先順位との関係を扱う。

仕様への反映は転居、卒業、退職など、本人が知る区切りに応じて目標を再検討すること。本人に内部の死亡予定日を知らせず、高齢者にも探索や挑戦を残す。ゲーム上の締切効果の強さは独自に調整する。

### R12 知人を介した情報

Granovetter, M. S. 1973. The Strength of Weak Ties. American Journal of Sociology, 78, 1360–1380. DOI 10.1086/225469.

[著者所属大学の書誌と要旨](https://sociology.stanford.edu/publications/strength-weak-ties)を確認した。小さな関係と大きな社会構造をつなぐ、情報や機会の伝わり方に関する理論を扱う。[原著PDF](https://snap.stanford.edu/class/cs224w-readings/granovetter73weakties.pdf)も参照先として併記する。

仕様への反映は親友以外の知人にも別の集まりの情報を持ってくる役割を与えること。情報の内容、出所、相手が知っている範囲を保持する。知人が多いほど必ず就職や人生が成功するという規則にはしない。

### R13 弱いつながりの効果の条件

Rajkumar, K., Saint-Jacques, G., Bojinov, I., Brynjolfsson, E., & Aral, S. 2022. A causal test of the strength of weak ties. Science, 377, 1304–1310. DOI 10.1126/science.abl4476.

[研究機関が公開する原著PDF](https://ide.mit.edu/wp-content/uploads/2022/09/abl4476.pdf)の抄録と研究の説明を確認した。LinkedInの推薦に関する実験で、関係の弱さと仕事の伝播は単純な比例関係ではなく、指標や産業による違いも扱われている。

仕様への反映は関係の強さ一つで情報の価値を決めず、異なる集まりへの接点と、情報の適合性を持たせること。オンラインの労働市場の結果を、小さな町の家族、恋愛、幸福へ一般化しない。

## 生成エージェントの設計研究

以下は2026年11月3日に追加した調査。人間を対象とする行動研究と、AIエージェントの振る舞いを評価する研究を区別する。ゲームへ採用する方式は今後検証する。

### R14 記憶・振り返り・計画を持つ生成エージェント

Park, J. S., O'Brien, J. C., Cai, C. J., Morris, M. R., Liang, P., & Bernstein, M. S. 2023. Generative Agents: Interactive Simulacra of Human Behavior. UIST 2023. DOI 10.1145/3586183.3606763.

[原著v2](https://arxiv.org/html/2304.03442v2)の抄録、7.2節、8.2節を確認した。経験の記憶、振り返り、計画を組み合わせ、25体のエージェントの町で情報の伝播や集まりへの調整を示している。一方、記憶や場所の扱いの誤り、短い評価期間、実行資源の負担も報告している。2023年の実装に関する結果であり、現在のモデルや本作の性能・費用を示すものではない。

仕様への反映は経験を次の判断へ取り出すこと、本人が知る情報を区別すること、住人発の誘いや情報伝播を扱うこと。AIエージェントがもっともらしく見えるという評価を、人間の行動確率や長期のゲームの面白さの証拠には使わない。採用箇所は[行動仕様の拡張計画](character-spec.md#自律行動と登場人物の拡張計画)に記す。

### R15 行動候補と世界の成立判定を分ける構成

Vezhnevets, A. S., et al. 2023. Generative agent-based modeling with actions grounded in physical, social, or digital space using Concordia. arXiv:2312.03664v2.

[原著v2](https://arxiv.org/html/2312.03664v2)の抄録と1節を確認した。記憶を用いるエージェントが行動を提案し、Game Masterが環境側で実行と効果を扱う構成を示す。モデル内の結果を現実の人間社会へ一般化するには、用途に応じた検証が必要だとも論じている。

仕様への反映は計画の候補を出す処理と、時間・場所・資源・同意を検査して事実を更新する処理を分けること。本作では既存の生活シミュレーションを最終の実行側に置く。Concordiaの導入や自由文による世界更新を決定したものではない。

## 約束と援助の判断

### R16 約束と信頼の修復

Schweitzer, M. E., Hershey, J. C., & Bradlow, E. T. 2006. Promises and lies: Restoring violated trust. Organizational Behavior and Human Decision Processes, 101, 1–19. DOI 10.1016/j.obhdp.2006.05.005.

[著者所属大学が公開する原著稿PDF](https://knowledge.wharton.upenn.edu/wp-content/uploads/2013/09/1321.pdf)の抄録と実験方法を確認した。金銭を使う実験室の信頼ゲームで、後に観察された行動と約束、過去の欺きによって信頼回復の経過が異なった。

仕様への反映は約束、日程変更、その後の実際の履行を分けて記録すること。将来の予定に合意しただけでは共有経験や信頼を増やさない。通常の日程変更を欺きと同一視しない。今後、同じ中断に対して代案の有無、その後の履行・再中断を変えて比較する。予約変更そのものの研究ではなく、回復の計算式や期間は本作の仮説となる。

### R17 援助する本人の自律性

Weinstein, N., & Ryan, R. M. 2010. When helping helps: Autonomous motivation for prosocial behavior and its influence on well-being for the helper and recipient. Journal of Personality and Social Psychology, 98, 222–244. DOI 10.1037/a0016984.

[原著抄録](https://pubmed.ncbi.nlm.nih.gov/20085397/)を確認した。日誌と実験を含む四研究で、自律的な援助動機による援助者・受け手双方への利益を報告している。全文の方法と対象集団の詳細は今回検討していない。

仕様への反映は、支援する住人が自分の予定、食事、休息、関係から納得して引き受ける余地を残すこと。`resident_support_plans.gd`の相談先は本人が知る関係から選び、`work_family.gd`が相手自身の事情と安全な引継ぎを検査する。同じ関係でも余裕の有無、実際に得た自由時間、引き受けた側の負担を変えて比較する。辞退の効果、家事交代の条件、疲労や空腹の係数をこの研究から得たとは扱わない。

## 欲求と行動の拡張

### R18 動機・能力・機会を分ける

Michie, S., van Stralen, M. M., & West, R. 2011. The behaviour change wheel: A new method for characterising and designing behaviour change interventions. Implementation Science, 6, 42. DOI 10.1186/1748-5908-6-42。

[原著本文](https://link.springer.com/article/10.1186/1748-5908-6-42)の抄録とCOM-Bの説明を2026年11月3日に確認した。行動への動機、能力、機会を相互に影響する要素として分け、動機には計画・評価だけでなく習慣や感情なども含める。健康行動の介入枠組みを検討した論文であり、19の既存枠組みの整理と、たばこ・肥満対策での分類への適用を扱う。

本作では[欲求と行動の設計](needs-and-behavior-design.md)で、動機があっても技能、場所、時間、相手の意思や責任によって実行できる行動が違うこと、実行後の経験が次の動機と機会を変えることを分ける参考にする。行動を単一の欲求値だけから選ばせない。欲求の種類、成人の私的な動機、充足量、選択係数、面白さの有効性はこの論文から導かず、ゲーム用の仮説と比較・試遊の対象として残す。

## 継続調査から実装へ渡す手順

調査は[開発計画](development-roadmap.md)の各段階で継続する。次に調べる対象を、現在の行動が単調になる場面や、人らしい理由を読めない場面から選ぶ。

| 記録するもの | 内容 |
|---|---|
| 出典と条件 | URL、著者、公開年または版、確認日、対象集団、状況、調査方法、本文を確認できた範囲 |
| 根拠と仮説 | 観測された関連、因果を扱える範囲、理論、AIによる生成例を区別し、本作で試したい関係を記す |
| 実装への対応 | どの行動定義、知識、期待、習慣、関係更新を変えるか。係数はゲーム用の値として記す |
| 比較と判断 | 初期条件、seed、変更前後、成立しなかった例、試遊での理解や関心、採用・見直しの理由 |

既存のR07の性格と状況、R08の習慣、R10の対人応答、R12・R13の情報伝播を、行動と経験更新を作る最初の候補とする。今回R07の[原著抄録](https://pubmed.ncbi.nlm.nih.gov/11414368/)も再確認した。同じ人の中でも日常の行動が変動することを、固定的な性格ラベルだけで行動を決めない設計の参考にする。

公開された生活事例や体験談は、見落としていた行動や状況を探す材料として扱う。その人の事情を保持し、投稿の多さから一般的な頻度や性格を推定しない。ネットで得た内容の要約と、検証を経て採用した行動定義を区別する。実装先と比較記録がそろって初めて「思考ルーチンへ反映した」と記録する。

## 設定値の扱い

行動モデルの設定ファイルでは公的な観測値をempirical_referencesに、ゲーム用の係数をgame_parametersに分ける。R番号は参照先を示し、その係数が論文で実証されたことを意味しない。

行動選択の重み、提案の上乗せ、習慣の増分、関係の更新幅、頭身、時間圧縮、初期住人8人の値は、すべてゲーム用の仮設定。効果の大きさ、楽しさ、人物らしさは実装と試遊で確かめる。

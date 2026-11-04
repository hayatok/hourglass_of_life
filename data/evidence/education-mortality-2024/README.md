# 教育制度と年齢別死亡の独立 source pack

2026年11月5日取得。既存 `life-course` pack の就業・家族介護に対し、**初等教育への理論上の入学年齢**と**日本の2024年期間生命表**を追加した。G4用の校正資料であり、ゲームには接続していない。出生・疾病発症・回復・中退の個人遷移は含まない。

| ファイル | 内容 |
| --- | --- |
| `raw/` | 公式xlsx、公式APIの未加工JSON、出典・定義・利用条件。10応答、1,024,705 bytes（約0.98 MiB） |
| `catalog.json` | 一次源、配信者、年・国・性・年齢・区間・分母・単位・欠測・利用条件・採用できない用途 |
| `retrieval.json` | URL、実取得時刻、サイズ、取得失敗の区別。初回8応答の時刻は成功後のファイル書込時刻から回収したと明記 |
| `observations.json` | 生命表212行と教育制度18点。原セル・原数値文字列・JSON座標を保持 |
| `validate.py` / `test_validate.py` | 既存 importer から独立した stdlib validator と12の意味検証 |

230観測を230件のゲーム検査とは数えない。SHA・ハッシュ照合は行わず、原値・区間・定義・分母と派生結果の一致を検証する。`.gdignore` で research 素材を Godot import から除外している。

## 生命表をどう読んだか

厚生労働省「令和6年簡易生命表」、2025年7月25日公表。[公式xlsx](https://www.mhlw.go.jp/toukei/saikin/hw/life/life24/xls/life24-12.xlsx)の男女各106行を採用。日本における日本人が対象で、2024年の死亡状況が変わらないと仮定した期間生命表である。2024年人口推計と死亡概数、2023〜2024年の出生数に基づく。[基礎資料・対象](https://www.mhlw.go.jp/toukei/saikin/hw/life/life24/dl/life24-01.pdf)

- `qx` は、ちょうど年齢xまで生存した生命表上の人が、指定区間中に死亡する条件付き確率。人口千対の粗死亡率ではない。
- 0〜104歳行の区間は1年。105歳行は **105歳以上の開放区間、n=∞**。`qx=1`を「105歳の一年間に必ず死去する」と読まない。
- 乳児の週・月の8小区間は、0歳年区間と重複するため正規化から除外し、原xlsxに残した。
- `lx` の出発点100,000は仮想出生集団。実観測人数ではない。`dx`・人年も生命表上の量。原表の定常人口 `Lx` / `Tx` は「人」と表章されるが、その期間の積分量を正規化metadataでは人年として説明し、両方の表記をcatalogへ保持した。
- 平均余命は固定した死亡状況での期待値であり、死去年齢の予定表ではない。[関数の定義](https://www.mhlw.go.jp/toukei/saikin/hw/life/life24/dl/life24-08.pdf)

元の「…」はnullとして保存する。今回の選択に欠測はないが、無印の空セルや非有限値はデータ形式の変化として拒否する。掲載値の丸めを考慮して生存数・死亡数・人年の整合を調べる。日・分のhazardや発症率は生成しない。

## 教育制度をどう読んだか

UNESCO UISの2026年2月版を一次源とする、World Bank WDI公式配信 [SE.PRM.AGES](https://data.worldbank.org/indicator/SE.PRM.AGES)。JPN / FIN / FRAの2019〜2024学年18点を取得。WDI応答の更新日は2026年10月8日。理論上の初等教育入学年齢は日本・フランス6歳、フィンランド7歳だった。

公式の標準年齢から始め、留年・飛び級なく全日制で進む場合の制度値であり、実際に入学した子の平均年齢や就学率ではない。学校年が暦年をまたぐ場合は終了年を参照する。分母は該当せず、単位は年齢の「年」。義務教育・就学前教育の開始年齢、本人の発達・習得・卒業とは区別する。[定義・方法・ライセンス](https://databank.worldbank.org/metadataglossary/world-development-indicators/series/SE.PRM.AGES)

APIの `value:null` は欠測のまま残し、前後年から補完しない。`obs_status` と空のAPI `unit` も保存し、Yearsという単位は公式glossaryから付与した。

## 利用条件

厚労省資料は [PDL1.0に基づく同省の条件](https://www.mhlw.go.jp/chosakuken/)を確認。出典URLと加工したことを示す。政府がゲーム向け判断を制作・推奨したとは表示しない。原ファイルの別の権利指定、ロゴ等は対象外。

教育系列は **このWDI指標の公式metadataがCC BY4.0と指定**していることを確認。[WDIデータ条件](https://data.worldbank.org/summary-terms-of-use)のWorld Bank / UISの出典、再配布時の同じ出典義務、非推奨表示、追加の調停・仲裁条件も残す。UIS全データやWorld Bankの一般Webコンテンツの条件へ一律に広げない。具体的な出典文は `catalog.json` に保存した。

World Bankの指標landingのHTML保存はtimeoutした。公式ページは別途web toolで読んだが、取得できた原JSONと混同せず `retrieval.json` に失敗を残した。公式glossaryとデータ条件のHTMLは実保存できた。

## ローカル検証

```sh
python3 data/evidence/education-mortality-2024/validate.py
python3 data/evidence/education-mortality-2024/test_validate.py
```

両方ともネットワーク・追加パッケージ・Godot・Blender不要。更新を確認して採用するときだけ `validate.py --build` を使う。原データを再取得しただけで、採用済みの観測を自動で置換しない。

G4への接続先と残る不足は [採用メモ](../../../docs/design/education-mortality-evidence.md) に記す。

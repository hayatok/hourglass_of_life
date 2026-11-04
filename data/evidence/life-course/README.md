# 人生の出来事の校正用データ v1

2026年11月5日（日本時間）取得。一次配布3本から4系列・108観測を選択した。うち6観測は元資料の欠測であり、`null` のまま残している。これはデータ整備の範囲であり、G4の人生連鎖・実ゲーム校正・人の試遊は未完了。

| ファイル | 内容 |
|---|---|
| `catalog.json` | 取得URL、版、一次定義、地域・母集団、欠測、利用条件、採用できない用途 |
| `retrieval.json` | 実取得のUTC時刻、配信URL、サイズ、HTTP情報。識別記録であり検査件数ではない |
| `raw/` | 未加工の配布xlsx 2本とCSV 1本。合計1,667,658 bytes、約1.59 MiB |
| `observations.json` | 実値、年・地域・年齢・性別・分母・単位・セル/CSV座標、明示した介護の派生値 |
| `calibration-cases.json` | 三つの人生連鎖に対する比較条件と画面上の受入条件。未実行の設計 |

## 採用した系列

- **母親の就業**：OECD LMF1.2の2019・2020・2021年、日本・フランス・スウェーデン・韓国の末子年齢別就業状態。日本は15歳以上の「世帯の最も若い母」の就業状態、仏・瑞は15～64歳の女性、韓国は15～54歳の既婚女性であり、同じ分母ではない。韓国の子の区分は0～6・7～12・13～17歳、他の3か国は0～2・3～5・6～14歳。元の年と欠測を保ち、2020年のスウェーデンを2021年値へ置換しない。出典：[OECD配布xlsx](https://webfs.oecd.org/els-com/Family_Database/LMF_1_2_Maternal_Employment.xlsx)。
- **入離職**：厚生労働省2024年雇用動向調査の2023・2024年、全体・一般・パートの入職、離職、転職入職の年間総流量。分母は対象事業所の年初常用労働者数であり、失業者数ではない。一般は正社員と同義ではなく、常用5人未満の店や自営業への直用もできない。[2023年と2024年には母集団の更新による比較上の注意](https://www.mhlw.go.jp/toukei/itiran/roudou/koyou/doukou/25-2/dl/sankou.pdf)がある。
- **転職後の賃金**：同じ図表の増加・不変・減少の構成。対象は前職が雇用者で、調査時にも在籍している転職入職者。自営業からの転職や既に退職した入職者は含まない。不詳を分母から落とさず、3分類を100%へ再配分しない。出典：[厚労省配布xlsx](https://www.mhlw.go.jp/toukei/itiran/roudou/koyou/doukou/25-2/dl/zuhyo.xlsx)、表6注1・2。
- **家族介護の負担**：2022年国民生活基礎調査の介護票第82表。認定された在宅の要支援・要介護者について、同居の主な介護者の時間カテゴリを扱う。元単位は「介護を要する者数10万対」。45,865を実人数と読まない。要介護度別の条件付き割合は、同じ列の総数で割った派生値として別フィールドに保存する。「不詳」も残す。出典：[e-Stat CSV](https://www.e-stat.go.jp/stat-search/file-download?statInfId=000040071983&fileKind=1)、[概況IV・図28](https://www.mhlw.go.jp/toukei/saikin/hw/k-tyosa/k-tyosa22/dl/05.pdf)。

## 再取得と検証

Python標準ライブラリのみ。API key、ログイン、追加パッケージ、Godot、Blenderは不要。リポジトリルートで実行する。

```sh
python3 tools/evidence/life_course_data.py --validate
python3 tools/evidence/test_life_course_data.py
```

ネットワークから取り直す場合：

```sh
python3 tools/evidence/life_course_data.py --fetch --validate
```

`--fetch` は1ファイル2 MB以下の3本だけを取得する。全入力の値・列名・単位を読めた後でrawを置き換え、採用済みの観測JSONは書き換えない。原資料に変更があれば、`--validate` は数値・定義の差で失敗する。更新内容を確認して採用するときだけ、`--build --validate` で観測を再生成する。rawのSHA照合は行わない。

xlsxはZIP/XMLからセルを読み、日本語のふりがな用XMLを値へ混ぜない。CSVは実バイトに合わせてcp932で読む（今回のHTTPヘッダーはUTF-8表記だが、実ファイルはcp932）。元の数値文字列を残し、数値は小数6桁までの正規化だけを行う。欠測の補完・補間はしない。rawは`.gdignore`でGodot importから除外する。統計CSVを翻訳表として読み込ませず、ゲーム側は必要な項目を採用した別contextから接続する。

検証は、原資料の値と分母・単位・列の意味、国別の実年齢区分、欠測と不詳の区別、介護カテゴリ合計と派生式、入力変更の拒否を調べる。12のPython回帰テストはこれらの取込処理を対象とし、108観測を108件のゲーム検査として数えない。

## 利用条件と出典

OECD (2023), *OECD Family Database, LMF1.2 Maternal employment*, national sources specified in workbook, [source](https://webfs.oecd.org/els-com/Family_Database/LMF_1_2_Maternal_Employment.xlsx), accessed 2026-11-05. データ利用は[OECD利用条件のData節](https://www.oecd.org/en/about/terms-conditions.html)に従う。2023年の原資料を一律にCC BY 4.0とは表示しない。選択・正規化と架空町への解釈は本プロジェクトによるもので、OECDの見解・推奨を表さない。再配布時にも出典とこの区別を引き継ぐ。

厚生労働省「令和6年雇用動向調査」「令和4年国民生活基礎調査」を選択・加工して作成。[厚生労働省のPDL1.0に基づく利用条件](https://www.mhlw.go.jp/chosakuken/)と[e-Stat利用規約](https://www.e-stat.go.jp/terms-of-use)を確認した。ロゴ・写真・個人票を採用していない。政府が作ったゲーム向けパラメータとは表示しない。

未取得の個人遷移、回復過程、実装手順と比較条件は [life-course-data.md](../../../docs/design/life-course-data.md) に記す。

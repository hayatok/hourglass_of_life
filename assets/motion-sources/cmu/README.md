# CMU everyday-motion source candidates

CMU Graphics Lab の[公式カタログ、subject 79](https://mocap.cs.cmu.edu/search.php?subjectnumber=79)から、家事に必要な5件と同一人物の校正骨格だけを取得した。サイト全体を収集していない。数値は元のCRLFを保持する。

| Trial | カタログ上の動作 | 元のfps |
|---|---|---|
| 79_10 | 玉ねぎを刻む | 60 |
| 79_13 | 生地を混ぜる | 60 |
| 79_23 | 上着を着る | 60 |
| 79_25 | 重い箱を動かす | 60 |
| 79_42 | スープを食べる | 60 |

[利用条件](https://mocap.cs.cmu.edu/)は製品への組込みを認め、データそのものの販売を禁じている。プロジェクトで次の謝辞を表示する。

> The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217.

元の指・親指のチャンネルは実収録ではないため使わない。手足先にはノイズがあり、接触や滑りを別に検証する必要がある。道具や台との接触、人物モデルへの転送、自然さの受入を引き継がない。

[公式形式説明](https://mocap.cs.cmu.edu/info.php)に従い、ASFの長さは `0.0254 / units.length` を掛けてmへ換算する。AMCにfpsは含まれないため、公式カタログの60fpsを別に記録する。角度のチャンネル順序と校正axisを保持し、指・親指を除いた入力を `cmu_source.py` で読み取る。これは入力の前処理であり、再生可能なゲームアニメーションではない。

先に全身を正しく再生し、切る・混ぜる・食べる・運ぶ動作の重心とタイミングを比較する。その後、家族の体格へ転送し、手・足・道具・台の差だけを接触制御で補う。台所の物の所在と実作業の成立条件はゲーム側が管理する。

取得URLと元ファイル寸法は `source-record.json`、変換・形式の検証は `tests/test_cmu_source.py`。識別情報を動作テストの合否に使わない。

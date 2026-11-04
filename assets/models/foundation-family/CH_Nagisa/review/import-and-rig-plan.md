# 新しい渚原型の選択とリグ計画

参照は `ref/turnaround-v1.png`。身長は制作上の 1.65 m、頭身は画像実測の 6.50 を使う。課金・生成・外部アップロードはこの計画に含めない。Tripo 原型が得られた場合も、現 blockout と同じ画像・尺度・カメラで比較してから採用する。

## 原型を受け取ったときに調べること

1. 受領した GLB をそのまま `source/` に保持し、モデルの実寸、軸、原点、mesh / primitive / material 数、三角形、texture サイズ、skin / morph の有無を記録する。表示上の「30k」は実三角形の代わりにしない。
2. 別の制作コピーで floor root / Z up / -Y forward を合わせ、crown-to-ground を 1.65 m にそろえる。均等拡大縮小後の object scale を適用する。肩、頭、手足を部分的に変える前の状態も残す。
3. 正面・側面・背面を world 登録して silhouette を測る。現参考の正面と背面は A-pose、側面は腕を下げた別 pose なので、その差を記録する。bounding-box 正規化だけの比較では採否を決めない。
4. 顔、髪、袖、袖口、手、前掛けの表裏、長ズボンの股・膝・裾、靴を clay と material の両方で見る。見た目の陰影が texture の描き込みだけか、形として存在するかを区別する。64 / 128 px でも母親の顔・bob・前掛け・健康な脚が読めることを求める。
5. 採用原型の表面形が良くても、手指の融合、閉じた股、衣服間の橋、背面 slit 欠損、面の裏返り、過密・伸長三角形、UV の顔の面積不足は修正する。眼球や口を皮膚から無理に押し出して作らない。

採用基準は blockout IoU 0.85 / 幅誤差 0.05H / 主要比率 5%以内、その後 forms IoU 0.90 / 幅誤差 0.03H / 比率 2%以内。画像に無い部分は推定として残す。生成原型の採用そのものを完成・rig 成功・ゲーム内品質の証拠にしない。

## 形を保ちつつ分ける部品

| 部品 | 分離・変形の方針 |
| --- | --- |
| 顔・耳・首 | 頬と顎を連続させ、目蓋・口の周りに変形用 loop。首との境界を blouse / hair で隠すだけで穴を放置しない |
| 眼球・虹彩・眉 | lid と別の表面。視線移動で顔を引っ張らず、Blink は目蓋を閉じる。瞳の volume を潰さない |
| 髪・clip | bob の大きな輪郭を保ち、前髪と後ろ髪の重なりを作る。基本 head 固定。細い飛び毛を大量に増やさない |
| blouse と袖・cuff | shoulder / elbow の曲げ位置に十分な面。cuff から腕が出る実際の開口を作る |
| 前掛け bib / straps / belt | 胴の皮膚とは分離。胸・腰へ追従しつつ blouse と交差しない。pocket と bow は実厚を持つ |
| 前掛けの下半分 | 前一枚・後ろ二枚の slit を維持。waist 固定から裾へ weight を滑らかに変える。座りで脚を貫通する硬い cone にしない |
| 腕・手 | 掌と 5 指を分けられる topology。爪・指間の texture だけで 5 指があると見なさない |
| 長ズボン | 左右の脚と股を確保し、loose な太さを保つ。膝に曲げ loop、裾と靴のすき間を見直す |
| 靴・sole | 足と toe に合わせる。sole は接地基準。lacing detail より足幅と歩行時の volume を優先 |

## 骨と接触の準備

`ref/joint-plan.json` と `reference-rig-plan.png` は画像由来の **暫定配置**。まだ bound rig ではない。既存 35 骨の名前と階層を維持し、旧モデルの細い脚や短い肩の座標をコピーしない。肩・肘・手首の投影は画像実測、深さ・股・膝・finger 軸は推定なので、採用 mesh と合わせて修正する。

各 mesh は同じ DEF skeleton に bind、最大 4 influence、正規化、未割当 vertex なし。頬・首・肩・肘・股・膝の順に joint placement → topology → weights を直す。hair は head、革靴は foot / toe、apron は腰と garment bone の役割を分ける。hidden body は authoring 用 HIGH に残し、不要な貫通部を runtime へ一括 export しない。

実寸の椅子で着座・起立、bed で横臥、歩行最大 stride、90 / 180 度転回、膝曲げ、台所の前方 reach、両手持ち、指の皿・布把持を pose sheet へ残す。apron / trousers / hips の交差、指の collapse、sole の浮き・床刺さり、手元 socket を実物付きで確認する。現時点では、いずれも未実施。

Godot へ渡す GLB は Y up へ exporter が変換する。runtime で改めて身長・floor contact・35 骨・形態 key・material / texture を調べる。旧 motion が同じ骨名で読み込めても、そのまま新体格に正しいとは判断せず、root 側の retarget と実描画確認に接続する。

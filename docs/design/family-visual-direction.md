# 家族モデルの制作基準

小川家の3人から、温かいJRPGの人物造形へ更新する。顔・髪・体の厚み・衣服の重なりを実ゲームの大きさでも読めるようにし、細い円柱状の手足と単純な衣服を置き換える。体格、服装、歩行、座る・立つ・家事を一緒に成立させてから他の住民へ広げる。

渚の基準画は [turnaround-v1.png](../../assets/models/foundation-family/CH_Nagisa/ref/turnaround-v1.png)。2026年11月5日、組み込み image_gen で生成。これは制作の参照画像で、ゲーム内モデルやモーションの完成を表さない。画像に写る比率を測り、プロンプトに書いた頭身を実測値として扱わない。

## 生成プロンプト

```text
Use case: stylized-concept. Asset type: canonical character turnaround for rebuilding a Godot life simulation game character, Nagisa Ogawa, a 36-year-old Japanese woman, baker and mother. Create one polished wide character model sheet containing front, right side, and back of THE SAME character, all full body, same scale and ground line, neutral relaxed A pose, arms 25 degrees out, hands separate from body. Art direction: charming warm classic Japanese town JRPG, early Trails in the Sky atmosphere translated into refined 3D game art; original character, not any franchise character or costume. Mature friendly mother, not teenager. Approximately five heads tall, 1.65m, believable rounded shoulders, a solid and balanced torso, healthy thighs and calves, compact comfortable shoes; appealing face and expressive large brown eyes that read at 128-pixel gameplay height. Chestnut brown gently layered bob at jawline, small side hair clip. Sage green short-sleeve collared blouse with rolled cuffs, muted terracotta apron with practical chest bib and two pockets, ivory loose straight full-length work trousers visibly cover both legs, brown low leather shoes. Soft fabric folds and real garment layering, natural elbows/knees and hands, no needle limbs, no faceted tube hair, no random straps or fantasy equipment. Neutral cream background, diffuse studio lighting, no dramatic cast shadows, clean orthographic views, high-quality shaded 3D-style render with softly painted texture detail. The exact same hairstyle, face, garments, proportions and colors across all views. Keep all of the figure and both soles visible, generous separation between views. No lettering, no logo, no watermark, no props. This is a modelling reference, not a screenshot or UI mockup.
```

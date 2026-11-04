"""Crop the three authored views at the same pixel scale; remove only the paper and floor shadow."""
from pathlib import Path
import json
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / 'ref/turnaround.png').convert('RGB')
views = {'front': (150, 0, 650, 887), 'side': (650, 0, 1150, 887),
         'back': (1120, 0, 1620, 887)}
report = {}
for name, box in views.items():
    image = source.crop(box)
    rgb = np.asarray(image).astype(float)
    # The reference paper is warm, near-white and low-chroma. Include pale skin and trousers.
    chroma = rgb.max(2) - rgb.min(2)
    mask = (rgb.min(2) < 183) | (chroma > 27)
    mask[830:] &= (chroma[830:] > 27) | (rgb[830:].min(2) < 110)
    mask[860:] = False  # floor shadow is not part of the human
    labels, count = ndimage.label(mask)
    sizes = np.bincount(labels.ravel()); sizes[0] = 0
    mask = labels == sizes.argmax()
    mask = ndimage.binary_fill_holes(mask)
    rgba = image.convert('RGBA'); rgba.putalpha(Image.fromarray((mask * 255).astype('uint8')))
    rgba.save(ROOT / f'ref/{name}.png')
    ys, xs = np.where(mask)
    report[name] = {'crop': box, 'bounds': [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
                    'axis_col': {'front':249, 'side':222, 'back':254}[name], 'ground_row':858,
                    'm_per_px':1.65/830}
    if name == 'front':
        for y in [35,50,70,100,130,150,170,190,220,260,300,340,380,420,460,500,540,580,620,660,700,740,780,820,850]:
            indices=np.where(mask[y])[0]
            groups=np.split(indices,np.where(np.diff(indices)>1)[0]+1)
            print(y, [(int(a[0])+150,int(a[-1])+150) for a in groups if len(a)>1])
(ROOT / 'ref/calibration.json').write_text(json.dumps(report, indent=2))

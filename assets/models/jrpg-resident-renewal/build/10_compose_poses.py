"""Compose already rendered pose evidence without another renderer process."""
from pathlib import Path
from PIL import Image,ImageDraw
import json,sys
ROOT=Path(__file__).resolve().parents[1]
ident=sys.argv[1];folder=ROOT/ident/'review/poses';data=json.loads((folder/'poses.json').read_text())
sheet=Image.new('RGB',(960,696),(39,39,43));draw=ImageDraw.Draw(sheet)
strip=Image.new('RGB',(len(data['poses'])*112,156),(55,55,59));sd=ImageDraw.Draw(strip)
for i,row in enumerate(data['poses']):
 x=(i%3)*320;y=(i//3)*232
 draw.text((x+6,y+4),row['label'],fill='white')
 for k,angle in enumerate(['front','threequarter']):
  im=Image.open(folder/f'{row["label"]}-{angle}.png').convert('RGBA');im.thumbnail((156,204));sheet.paste(im,(x+k*160+(160-im.width)//2,y+24),im)
 im=Image.open(folder/f'{row["label"]}-threequarter.png').convert('RGBA');box=im.getbbox();im=im.crop(box);im.thumbnail((108,128));strip.paste(im,(i*112+(112-im.width)//2,20+(128-im.height)),im);sd.text((i*112+3,3),row['label'][:17],fill='white')
sheet.save(folder/'extreme-pose-sheet.png');strip.save(folder/'gameplay128-pose-strip.png')
print(folder/'extreme-pose-sheet.png')

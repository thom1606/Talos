# Requires Python 3 and Pillow. Tests the compiled production image tool.
from PIL import Image, ImageOps
import subprocess, json, hashlib, sys, tempfile, atexit, shutil
from pathlib import Path
root=Path(tempfile.mkdtemp(prefix='talos-redact-test-'))
atexit.register(shutil.rmtree, root)
tool=Path(sys.argv[1]).resolve()
image=Image.new('RGBA',(120,80),(255,255,255,255)); image.paste((255,0,0,255),(0,0,60,40)); image.paste((0,0,255,255),(60,40,120,80)); image.putpixel((119,0),(0,0,0,0)); image.save(root/'input.png')
rects=[dict(x=5,y=7,width=20,height=11),dict(x=90,y=60,width=30,height=20)]
def redact(input,output,rects,fmt='png'):
 return subprocess.run([str(tool),str(input),str(output),'redact',json.dumps(rects),fmt],capture_output=True)
before=hashlib.sha256((root/'input.png').read_bytes()).digest()
assert redact(root/'input.png',root/'out.png',rects).returncode==0
out=Image.open(root/'out.png').convert('RGBA')
for y in range(80):
 for x in range(120):
  masked=any(r['x']<=x<r['x']+r['width'] and r['y']<=y<r['y']+r['height'] for r in rects)
  assert out.getpixel((x,y))==((0,0,0,255) if masked else image.getpixel((x,y))), (x,y,out.getpixel((x,y)))
assert hashlib.sha256((root/'input.png').read_bytes()).digest()==before
assert redact(root/'input.png',root/'invalid.png',[dict(x=119,y=0,width=2,height=1)]).returncode!=0
assert not (root/'invalid.png').exists()
assert redact(root/'input.png',root/'out.jpg',rects,'jpg').returncode==0
assert Image.open(root/'out.jpg').getpixel((119,0))[0]>240
exif=Image.Exif(); exif[274]=6
image.convert('RGB').save(root/'rotated.jpg',exif=exif)
assert redact(root/'rotated.jpg',root/'rotated-out.png',[dict(x=0,y=0,width=10,height=20)]).returncode==0
rotated=Image.open(root/'rotated-out.png').convert('RGB'); expected=ImageOps.exif_transpose(Image.open(root/'rotated.jpg')).convert('RGB')
assert rotated.size==(80,120)
assert rotated.getpixel((4,6))==(0,0,0)
for p in [(30,30),(60,80)]: assert all(abs(a-b)<4 for a,b in zip(rotated.getpixel(p),expected.getpixel(p)))
subprocess.run([str(tool),str(root/'input.png'),str(root/'crop.png'),'2','3','40','30','png'],check=True)
assert Image.open(root/'crop.png').size==(40,30)
print('PASS: exact black pixels, multiple blocks, edge bounds, alpha, JPEG, EXIF rotation, original preservation, crop regression')

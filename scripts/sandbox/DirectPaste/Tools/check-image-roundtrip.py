#!/usr/bin/env python3
"""Pillow oracle for an offline AppKit fixture roundtrip, not event delivery.
Usage: Python with Pillow check-image-roundtrip.py OUTPUT_DIRECTORY
Creates only new synthetic files. Never accesses any clipboard.
"""
import hashlib, json, pathlib, subprocess, sys
from PIL import Image, ImageCms
root = pathlib.Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=False)
cases = {}
# Include partially transparent non-primary colors and low alpha. PNG uses
# straight alpha; compare decoded pixels, not encoding/metadata bytes.
cases['alpha-palette'] = (16, 16, [(r,g,b,a) for a in [0,1,2,16,64,127,128,192,254,255] for r,g,b in [(255,0,0),(0,255,0),(0,0,255),(23,101,207),(255,255,255),(0,0,0)]], False)
cases['odd-stride'] = (17, 9, [(x*13%256,y*29%256,(x+y)*17%256,255) for y in range(9) for x in range(17)], False)
cases['large-rgba'] = (1024, 768, [(x%256,y%256,(x+y)%256,[0,64,128,192,255][(x+y)%5]) for y in range(768) for x in range(1024)], False)
cases['srgb-tagged'] = (32, 16, [(x*7%256,y*13%256,(x+y)*9%256,255) for y in range(16) for x in range(32)], True)
profile = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
for name,(w,h,pixels,tagged) in cases.items():
    image=Image.new('RGBA',(w,h)); image.putdata((pixels*((w*h+len(pixels)-1)//len(pixels)))[:w*h])
    image.save(root/(name+'.png'), **({'icc_profile':profile} if tagged else {}))
(root/'cases.json').write_text(json.dumps(list(cases)))
source=pathlib.Path(__file__).with_name('image-roundtrip.swift')
run=subprocess.run(['swift',str(source),str(root)],text=True,capture_output=True)
(root/'appkit.log').write_text(run.stdout+run.stderr)
if run.returncode: raise SystemExit(run.returncode)
results=[]
for name in cases:
    src=Image.open(root/(name+'.png')); dst=Image.open(root/(name+'.stored.png'))
    a=list(src.convert('RGBA').get_flattened_data()); b=list(dst.convert('RGBA').get_flattened_data())
    same_size=src.size==dst.size
    differences=sum(x!=y for x,y in zip(a,b)) if same_size else None
    max_error=max((abs(u-v) for x,y in zip(a,b) for u,v in zip(x,y)),default=0)
    result={'case':name,'size':list(src.size),'storedSize':list(dst.size),'exactRGBA':same_size and a==b,'differentPixels':differences,'maxChannelError':max_error,'sourceHasICC':bool(src.info.get('icc_profile')),'storedHasICC':bool(dst.info.get('icc_profile')),'profilePreserved':not src.info.get('icc_profile') or src.info.get('icc_profile')==dst.info.get('icc_profile'),'sourceSHA256':hashlib.sha256((root/(name+'.png')).read_bytes()).hexdigest(),'storedSHA256':hashlib.sha256((root/(name+'.stored.png')).read_bytes()).hexdigest()}
    results.append(result)
(root/'results.json').write_text(json.dumps({'scope':'Offline actual NSTextStorage attachment, no sandbox/event/standard-paste acceptance','results':results},indent=2)+'\n')
print(json.dumps(results,indent=2))
raise SystemExit(0 if all(r['exactRGBA'] and r['profilePreserved'] for r in results) else 1)

#!/usr/bin/env python3
"""Diagnose the known sRGB sample only; never infer arbitrary ICC equivalence."""
import io,json,pathlib,sys
from PIL import Image,ImageCms
root=pathlib.Path(sys.argv[1])
src=Image.open(root/'srgb-tagged.png');dst=Image.open(root/'stage.png')
a=src.convert('RGBA');b=dst.convert('RGBA')
source_profile=ImageCms.ImageCmsProfile(io.BytesIO(src.info['icc_profile']))
# The Swift diagnostic exports the profile AppKit resolves from the PNG's
# explicit sRGB metadata. Do not silently assume an untagged image is sRGB.
assert dst.info.get('srgb') == 0, dst.info
resolved=ImageCms.ImageCmsProfile(str(root/'png.icc'))
common=ImageCms.createProfile('sRGB')
x=ImageCms.profileToProfile(a,source_profile,common,outputMode='RGBA',renderingIntent=ImageCms.Intent.RELATIVE_COLORIMETRIC)
y=ImageCms.profileToProfile(b,resolved,common,outputMode='RGBA',renderingIntent=ImageCms.Intent.RELATIVE_COLORIMETRIC)
pa=list(x.get_flattened_data());pb=list(y.get_flattened_data())
result={'scope':'Known opaque sRGB sample, explicit relative-colorimetric Pillow conversion to common sRGB; not wide gamut or rendered UI','sourceICCBytes':len(src.info['icc_profile']),'exportHasEmbeddedICC':bool(dst.info.get('icc_profile')),'exportSRGBIntent':dst.info.get('srgb'),'exportGamma':dst.info.get('gamma'),'inputEqualsTIFFProfile':(root/'input.icc').read_bytes()==(root/'tiff.icc').read_bytes(),'rawRGBAEqual':a.tobytes()==b.tobytes(),'normalizedRGBAEqual':pa==pb,'normalizedMaxChannelError':max(abs(u-v) for aa,bb in zip(pa,pb) for u,v in zip(aa,bb))}
(root/'profile-equivalence.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
assert result['inputEqualsTIFFProfile'] and result['rawRGBAEqual'] and result['normalizedRGBAEqual']

#!/usr/bin/env python3
"""Guard the UIKit-to-SwiftUI launch handoff against layout/color drift."""
from pathlib import Path
import json
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
storyboard = ET.parse(root / 'App/CinematicLaunchScreen.storyboard')
view = storyboard.find('.//viewController/view')
images = view.findall('./subviews/imageView')
assert len(images) == 1 and not view.findall('./subviews/label'), 'Launch must use one fixed lockup, with no separate text label'
image = images[0]
assert image.attrib['image'] == 'CinematicLaunch'
constraints = {c.attrib.get('firstAttribute'): c.attrib.get('constant') for c in image.findall('./constraints/constraint')}
assert constraints['width'] == '232' and constraints['height'] == '280'
for axis in ['centerX', 'centerY']:
    matches = [c for c in view.findall('./constraints/constraint') if c.attrib.get('firstItem') == image.attrib['id'] and c.attrib.get('firstAttribute') == axis]
    assert len(matches) == 1 and matches[0].attrib.get('secondItem') == view.attrib['id']
    assert float(matches[0].attrib.get('constant', '0')) == 0, 'Both launch views must center on the full screen'
source = (root / 'App/LaunchLoadingView.swift').read_text()
assert 'Image("CinematicLaunch")' in source and '.renderingMode(.original)' in source
assert '.frame(width: 232, height: 280)' in source and '.ignoresSafeArea()' in source
assert 'Text(' not in source and 'AniNextWordmark()' not in source, 'Do not replace fixed wordmark outlines with live text'
assert 'AniNextBrand.background' in source
color = view.find('./color[@key="backgroundColor"]')
assert [float(color.attrib[x]) for x in ['red', 'green', 'blue']] == [1, 0.9725490196, 0.9294117647]
asset = root / 'App/Assets.xcassets/CinematicLaunch.imageset'
manifest = json.loads((asset / 'Contents.json').read_text())
assert manifest['properties']['template-rendering-intent'] == 'original'
assert manifest['properties']['preserves-vector-representation'] is True
assert len(manifest['images']) == 1, 'Light and dark appearances must use the same colors'
pdf = (asset / manifest['images'][0]['filename']).read_bytes()
assert pdf.startswith(b'%PDF-') and re.search(rb'/MediaBox\s*\[\s*0\s+0\s+232\s+280\s*\]', pdf)
print('Launch handoff verified: shared fixed artwork, geometry, colors and full-screen centering')

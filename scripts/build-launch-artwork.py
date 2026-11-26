#!/usr/bin/env python3
"""Build the fixed AniNext launch lockup used by UIKit and SwiftUI.

Requires reportlab and fonttools. Letter outlines prevent runtime font changes.
The existing approved logo pixels are embedded unchanged; no font ships in app.
"""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.basePen import BasePen
from reportlab.pdfgen import canvas
import argparse

class OutlinePen(BasePen):
    def __init__(self, glyphs, path):
        super().__init__(glyphs); self.path = path
    def _moveTo(self, point): self.path.moveTo(*point)
    def _lineTo(self, point): self.path.lineTo(*point)
    def _curveToOne(self, a, b, c): self.path.curveTo(*a, *b, *c)
    def _closePath(self): self.path.close()
    def _endPath(self): pass

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--font', default='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf')
args = parser.parse_args()
font = TTFont(args.font)
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()
scale = 36 / font['head'].unitsPerEm
tracking = -1.1
word = 'AniNext'
width = sum(glyphs[cmap[ord(c)]].width * scale for c in word) + tracking * (len(word) - 1)
output = root / 'App/Assets.xcassets/CinematicLaunch.imageset/AniNextLaunch.pdf'
pdf = canvas.Canvas(str(output), pagesize=(232, 280), invariant=1, pageCompression=1)
pdf.setTitle('AniNext launch artwork')
pdf.drawImage(str(root / 'App/Assets.xcassets/AniNextLogo.imageset/AniNextLogo.png'), 0, 48, width=232, height=232, mask='auto')
x = (232 - width) / 2
for index, char in enumerate(word):
    pdf.saveState()
    pdf.translate(x, 8)
    pdf.scale(scale, scale)
    pdf.setFillColorRGB(*(tuple(v / 255 for v in ((177, 102, 250) if index < 3 else (49, 14, 76)))))
    pen = OutlinePen(glyphs, pdf.beginPath())
    glyphs[cmap[ord(char)]].draw(pen)
    pdf.drawPath(pen.path, fill=1, stroke=0)
    pdf.restoreState()
    x += glyphs[cmap[ord(char)]].width * scale + tracking
pdf.showPage()
pdf.save()
print(output)

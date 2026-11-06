"""Build the TapeIcons fonts: clothing icons that neither SF Symbols nor Phosphor draw.

The source icons are stroke drawings on a 24-unit grid from Lucide Lab (ISC), Hugeicons (MIT)
and Iconoven (MIT), kept in Scripts/extra-icons. Every icon is re-stroked at Phosphor's widths
(1.5 regular, 2.25 bold) so the three sources look like one family and match Phosphor.

  python3 build_extra_icons.py <fonts dir> <symbols.json> [--download]

--download fetches any missing SVGs from api.iconify.design first.
Needs: pip install fonttools picosvg
"""
import json, os, re, sys, urllib.request
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path
from picosvg.svg import SVG
import pathops

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE_DIR = os.path.join(HERE, 'extra-icons')

# name in the app, source set, source name, search words
ICONS = [
    ('boxer-briefs', 'lucide-lab', 'shorts-boxer', 'boxers boxer briefs underwear trunks'),
    ('boxer-shorts', 'hugeicons', 'boxer', 'boxers boxer shorts underwear'),
    ('briefs', 'iconoven', 'underwear', 'briefs underwear underpants knickers panties'),
    ('underpants', 'hugeicons', 'underpants-01', 'underpants underwear briefs trunks'),
    ('sweater', 'lucide-lab', 'sweater', 'sweater jumper pullover knit knitwear wool'),
    ('jumper', 'hugeicons', 'jumpers', 'jumper sweater pullover sweatshirt'),
    ('cardigan', 'hugeicons', 'cardigan', 'cardigan sweater knit buttons'),
    ('holiday-sweater', 'iconoven', 'holiday-sweater', 'christmas sweater jumper knit'),
    ('long-sleeve-shirt', 'lucide-lab', 'shirt-long-sleeve', 'long sleeve shirt top'),
    ('v-neck', 'lucide-lab', 'shirt-t-v-neck', 'v neck t shirt tee top'),
    ('folded-shirt', 'lucide-lab', 'shirt-folded-buttons', 'shirt folded button dress shirt'),
    ('polo-shirt', 'iconoven', 'polo-shirt', 'polo shirt top'),
    ('blouse', 'iconoven', 'blouse', 'blouse top shirt'),
    ('vest', 'lucide-lab', 'vest', 'vest waistcoat gilet'),
    ('jeans', 'iconoven', 'jeans', 'jeans denim pants trousers slacks'),
    ('joggers', 'hugeicons', 'jogger-pants', 'joggers sweatpants track pants'),
    ('leggings', 'iconoven', 'leggings', 'leggings tights'),
    ('shorts', 'lucide-lab', 'shorts', 'shorts'),
    ('skirt', 'lucide-lab', 'skirt', 'skirt'),
    ('jumpsuit', 'iconoven', 'jumpsuit', 'jumpsuit overalls onesie'),
    ('pajamas', 'iconoven', 'pajamas', 'pajamas pyjamas sleepwear nightwear'),
    ('sports-bra', 'lucide-lab', 'bra-sports', 'bra sports bra underwear'),
    ('swim-trunks', 'iconoven', 'swim-trunks', 'swim trunks swimwear swimming shorts'),
    ('swimsuit', 'iconoven', 'swimsuit', 'swimsuit swimwear bathing suit'),
    ('bikini', 'iconoven', 'bikini', 'bikini swimwear'),
    ('jacket', 'lucide-lab', 'jacket', 'jacket coat outerwear'),
    ('track-jacket', 'lucide-lab', 'jacket-sports', 'track jacket zip sports'),
    ('bomber-jacket', 'iconoven', 'bomber-jacket', 'bomber jacket outerwear'),
    ('coat', 'iconoven', 'coat', 'coat winter outerwear'),
    ('trench-coat', 'iconoven', 'trench-coat', 'trench coat mac outerwear'),
    ('raincoat', 'iconoven', 'raincoat', 'raincoat rain jacket waterproof'),
    ('scarf', 'lucide-lab', 'scarf', 'scarf winter wool'),
    ('mittens', 'iconoven', 'mittens', 'mittens mitts gloves winter'),
    ('gloves', 'hugeicons', 'glove', 'gloves glove winter'),
    ('work-gloves', 'iconoven', 'work-gloves', 'work gloves garden'),
    ('socks', 'lucide-lab', 'socks', 'socks sock'),
    ('baby-socks', 'iconoven', 'baby-socks', 'baby socks kids'),
    ('tie', 'hugeicons', 'tie', 'tie necktie'),
    ('bow-tie', 'lucide-lab', 'tie-bow', 'bow tie'),
    ('beanie', 'lucide-lab', 'hat-beanie', 'beanie hat winter wool'),
    ('bucket-hat', 'iconoven', 'bucket-hat', 'bucket hat'),
    ('sun-hat', 'iconoven', 'sun-hat', 'sun hat straw'),
    ('top-hat', 'lucide-lab', 'hat-top', 'top hat'),
    ('swim-cap', 'hugeicons', 'swimming-cap', 'swim cap swimming'),
    ('iron', 'iconoven', 'iron-clothes', 'iron ironing laundry'),
    ('coat-rack', 'iconoven', 'coat-rack', 'coat rack stand hallway'),
]

WEIGHTS = {'Regular': 1.5, 'Bold': 2.25}
UPEM, ASCENT, DESCENT = 1024, 960, -64  # Phosphor's metrics, so both fonts share one layout rule
FIRST_CODE = 0xE000


def source_path(icon_set, name):
    return os.path.join(SOURCE_DIR, f'{icon_set}__{name}.svg')


def download():
    os.makedirs(SOURCE_DIR, exist_ok=True)
    for _, icon_set, name, _ in ICONS:
        path = source_path(icon_set, name)
        if not os.path.exists(path):
            request = urllib.request.Request(f'https://api.iconify.design/{icon_set}/{name}.svg',
                                             headers={'User-Agent': 'tape-icon-builder'})
            with urllib.request.urlopen(request) as r:
                open(path, 'wb').write(r.read())


def outline(svg_text, stroke_width):
    """The icon's strokes, expanded at `stroke_width` and merged into one filled shape."""
    svg_text = re.sub(r'stroke-width="[\d.]+"', f'stroke-width="{stroke_width}"', svg_text)
    svg_text = svg_text.replace('width="1em" height="1em" ', '').replace('currentColor', 'black')
    pico = SVG.fromstring(svg_text).topicosvg()
    merged = pathops.Path()
    for shape in pico.shapes():
        part = pathops.Path()
        parse_path(shape.as_path().d, part.getPen())
        merged = pathops.op(merged, part, pathops.PathOp.UNION, fix_winding=True)
    return merged


def build_font(weight, stroke_width, out_dir):
    names = ['.notdef'] + [f'icon{i}' for i in range(len(ICONS))]
    fb = FontBuilder(UPEM, isTTF=False)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({FIRST_CODE + i: f'icon{i}' for i in range(len(ICONS))})
    scale = UPEM / 24
    charstrings = {'.notdef': T2CharStringPen(UPEM, None).getCharString()}
    for i, (_, icon_set, name, _) in enumerate(ICONS):
        pen = T2CharStringPen(UPEM, None)
        shape = outline(open(source_path(icon_set, name)).read(), stroke_width)
        # SVG y runs down from the top of the 24-unit box; font y runs up from the baseline.
        shape.draw(TransformPen(pen, (scale, 0, 0, -scale, 0, ASCENT)))
        charstrings[f'icon{i}'] = pen.getCharString()
    ps_name = f'TapeIcons-{weight}'
    fb.setupCFF(ps_name, {'FullName': ps_name}, charstrings, {})
    fb.setupHorizontalMetrics({n: (UPEM, 0) for n in names})
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    fb.setupNameTable({'familyName': 'TapeIcons', 'styleName': weight, 'psName': ps_name})
    fb.setupOS2(sTypoAscender=ASCENT, sTypoDescender=DESCENT, usWinAscent=ASCENT, usWinDescent=-DESCENT)
    fb.setupPost()
    fb.save(os.path.join(out_dir, f'{ps_name}.otf'))


def update_catalog(symbols_path):
    data = json.load(open(symbols_path))
    data['symbols'] = [s for s in data['symbols'] if not s['n'].startswith('tp:')]
    data['symbols'] += [
        {'n': f'tp:{name}', 'k': f"{name.replace('-', ' ')} {words} clothes clothing",
         'c': ['clothing'], 'p': [FIRST_CODE + i, FIRST_CODE + i]}
        for i, (name, _, _, words) in enumerate(ICONS)
    ]
    json.dump(data, open(symbols_path, 'w'), separators=(',', ':'))


if __name__ == '__main__':
    fonts_dir, symbols_path = sys.argv[1], sys.argv[2]
    if '--download' in sys.argv:
        download()
    for weight, width in WEIGHTS.items():
        build_font(weight, width, fonts_dir)
    update_catalog(symbols_path)
    print(f'{len(ICONS)} icons built in {len(WEIGHTS)} weights')

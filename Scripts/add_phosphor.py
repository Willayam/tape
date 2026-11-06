"""Merge Phosphor icons and the Clothing category into symbols.json.

Run gen_symbols.py first, then:
  python3 add_phosphor.py <symbols.json> <@phosphor-icons/web package dir> <@phosphor-icons/core package dir>

Phosphor icons get the name prefix "ph:". Fill variants end in ".fill", like SF Symbols.
"p" holds codepoints: [regular, bold] for outline icons, [fill] for fill icons.
"""
import json, re, sys

symbols_path, web, core = sys.argv[1:4]
data = json.load(open(symbols_path))
data['symbols'] = [s for s in data['symbols'] if not s['n'].startswith('ph:')]
data['categories'] = [c for c in data['categories'] if c['key'] != 'clothing']

def codes(weight, suffix):
    selection = json.load(open(f'{web}/src/{weight}/selection.json'))
    out = {}
    for icon in selection['icons']:
        name = icon['properties']['name']
        if suffix and name.endswith(suffix):
            name = name[:-len(suffix)]
        out[name] = icon['properties']['code']
    return out

regular, bold, fill = codes('regular', ''), codes('bold', '-bold'), codes('fill', '-fill')

source = open(f'{core}/dist/index.mjs').read()
entry = re.compile(
    r'name: "([^"]+)",\s*pascal_name: "[^"]*",\s*(?:alias: \{[^}]*\},\s*)?'
    r'categories: \[([^\]]*)\],\s*figma_category: [^,]+,\s*tags: \[([^\]]*)\]', re.S)

# Phosphor category -> SF Symbols category key, so the picker's chips cover both libraries.
category_map = {
    'OBJECTS': 'objectsandtools', 'COMMERCE': 'commerce', 'FINANCE': 'commerce', 'HEALTH': 'health',
    'MAP': 'maps', 'NATURE': 'nature', 'WEATHER': 'weather', 'MEDIA': 'media', 'PEOPLE': 'human',
    'COMMUNICATION': 'communication', 'OFFICE': 'objectsandtools', 'GAMES': 'gaming',
    'SYSTEM': 'devices', 'DEVELOPMENT': 'devices', 'EDITOR': 'textformatting', 'DESIGN': 'editing',
    'ARROWS': 'arrows',
}

clothing_words = {'clothes', 'clothing', 'apparel', 'fashion', 'wardrobe'}
clothing_sf = [
    'tshirt', 'tshirt.fill', 'jacket', 'jacket.fill', 'hanger', 'shoe', 'shoe.fill', 'shoe.2', 'shoe.2.fill',
    'hat.cap', 'hat.cap.fill', 'hat.widebrim', 'hat.widebrim.fill', 'graduationcap', 'graduationcap.fill',
    'eyeglasses', 'sunglasses', 'sunglasses.fill', 'handbag', 'handbag.fill', 'bag', 'bag.fill',
    'backpack', 'backpack.fill', 'suitcase', 'suitcase.fill', 'washer', 'washer.fill', 'dryer', 'dryer.fill',
    'crown', 'crown.fill', 'comb', 'comb.fill',
]
clothing_ph = [
    't-shirt', 'shirt-folded', 'pants', 'dress', 'hoodie', 'sock', 'sneaker', 'sneaker-move', 'boot',
    'high-heel', 'baseball-cap', 'belt', 'coat-hanger', 'handbag', 'handbag-simple', 'backpack', 'watch',
    'sunglasses', 'eyeglasses', 'washing-machine', 'baby', 'dresser', 'crown', 'crown-simple', 'suitcase',
    'suitcase-simple', 'umbrella', 'umbrella-simple',
]

added = []
for m in entry.finditer(source):
    name = m.group(1)
    groups = re.findall(r'e\.([A-Z]+)', m.group(2))
    if 'BRAND' in groups or name not in regular or name not in bold or name not in fill:
        continue
    tags = [t for t in re.findall(r'"([^"]*)"', m.group(3)) if not t.startswith('*')]
    words = ' '.join([name.replace('-', ' ')] + tags).lower()
    cats = sorted({category_map[g] for g in groups if g in category_map})
    if name in clothing_ph or clothing_words & set(words.split()):
        cats.append('clothing')
        words += ' clothes clothing'
    added.append({'n': f'ph:{name}', 'k': words, 'c': cats, 'p': [regular[name], bold[name]]})
    added.append({'n': f'ph:{name}.fill', 'k': words + ' fill', 'c': cats, 'p': [fill[name]]})

for s in data['symbols']:
    if s['n'] in clothing_sf:
        s['c'] = sorted(set(s['c']) | {'clothing'})
        s['k'] = (s['k'] + ' clothes clothing').strip()

data['symbols'] += added
data['categories'].insert(0, {'key': 'clothing', 'icon': 'tshirt'})

json.dump(data, open(symbols_path, 'w'), separators=(',', ':'))
print(f"{len(added)} Phosphor icons added, {sum('clothing' in s['c'] for s in data['symbols'])} in Clothing")

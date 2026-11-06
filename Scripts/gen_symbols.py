"""Build the SF Symbols part of symbols.json from the copy macOS ships.

  python3 gen_symbols.py <symbols.json>

It keeps symbols available on iOS and macOS 26 and skips Apple's restricted ones.
Run add_phosphor.py and build_extra_icons.py afterwards to add the other icon sets.
"""
import plistlib, json, re, sys
R='/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/'
load=lambda f: plistlib.load(open(R+f,'rb'))
avail=load('name_availability.plist')['symbols']
search=load('symbol_search.plist')
cats=load('symbol_categories.plist')
order=load('symbol_order.plist')
catlist=load('categories.plist')
restricted=set()
for line in open(R+'symbol_restrictions.strings', encoding='utf-16' if open(R+'symbol_restrictions.strings','rb').read(2) in (b'\xff\xfe',b'\xfe\xff') else 'utf-8', errors='ignore'):
    m=re.match(r'\s*"([^"]+)"\s*=',line)
    if m: restricted.add(m.group(1))
if not restricted:
    try: restricted=set(plistlib.load(open(R+'symbol_restrictions.strings','rb')).keys())
    except Exception as e: print('restrictions parse failed',e,file=sys.stderr)
skip={'whatsnew','multicolor','variable','draw','all'}
out=[]
for n in order:
    y=avail.get(n)
    if y is None or int(y.split('.')[0])>2025 or n in restricted: continue
    c=[x for x in cats.get(n,[]) if x not in skip]
    out.append({'n':n,'k':' '.join(search.get(n,[])),'c':c})
categories=[c for c in catlist if c['key'] not in skip]
json.dump({'categories':categories,'symbols':out},open(sys.argv[1],'w'),separators=(',',':'))
print(len(order),'->',len(out),'restricted',len(restricted))

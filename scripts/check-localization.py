#!/usr/bin/env python3
"""Audit the single xcstrings source, references, placeholders, and English copy."""
from pathlib import Path
import json,re,sys
root=Path(__file__).resolve().parents[1]
source=root/'Sources/UniversePhoto'
catalog=json.loads((source/'Resources/Localizable.xcstrings').read_text())
errors=[]
strings=catalog['strings']
placeholder=re.compile(r'%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.\d+)?(?:ll|l|z)?[@diufgcs%]')
for key,entry in strings.items():
    localized=entry.get('localizations',{})
    if set(localized)!={'en','de'}:errors.append(f'{key}: language coverage')
    values={lang:value.get('stringUnit',{}).get('value','') for lang,value in localized.items()}
    if values.get('en')!=key:errors.append(f'{key}: English source differs')
    if not values.get('de','').strip():errors.append(f'{key}: German is empty')
    if placeholder.findall(values.get('en',''))!=placeholder.findall(values.get('de','')):errors.append(f'{key}: format placeholders differ')
    if re.search(r'\b(Ebenen|Pinsel|Rückgängig|Deckkraft|Leinwand|Sprache|Dunkel|Hell|Wiederherstellung|Ungültig|Speichern|Schließen)\b',values.get('en','')):errors.append(f'{key}: German word in English copy')
reference=re.compile(r'(?:\bL|\bLF|\bLC|LocalizedText\.string|\.checkpoint|\.mutateLayer|StudioError\.message)\("((?:[^"\\]|\\.)*)"')
for file in source.glob('*.swift'):
    if file.name=='RenderingEngine.swift':continue # unchanged engine errors are localized by the error boundary
    for key in reference.findall(file.read_text()):
        if key not in strings:errors.append(f'{file.name}: missing {key}')
if errors:
    print('\n'.join(errors));sys.exit(1)
print(f'Localization audit passed: {len(strings)} complete en/de entries; source keys and placeholders match.')

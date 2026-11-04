#!/usr/bin/env python3
"""Independent, offline source/definition validator; Python stdlib only.

No game importer is called or changed. No daily/minute/person hazard is derived.
Use --build once after explicitly adopting reviewed raw sources; default is
read-only validation against the committed normalized observations.
"""
from pathlib import Path
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from zipfile import ZipFile
from xml.etree import ElementTree as ET
import argparse
import json
import math

ROOT = Path(__file__).resolve().parent
NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
REL = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'
YEARS = set(range(2019, 2025))
COUNTRIES = {'JPN', 'FIN', 'FRA'}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def number(raw, places=None):
    if raw == '…':
        return None
    require(isinstance(raw, str) and raw.strip() != '', 'Unmarked empty numeric source cell')
    try:
        value = Decimal(raw)
    except InvalidOperation as exc:
        raise ValueError('Invalid numeric source value: ' + repr(raw)) from exc
    require(value.is_finite(), 'Nonfinite source value')
    if places is not None:
        value = value.quantize(Decimal(1).scaleb(-places), rounding=ROUND_HALF_UP)
    return int(value) if places == 0 else float(value)


def visible_text(node):
    # Japanese Excel furigana is a phonetic annotation, not part of the value.
    tag = node.tag.rsplit('}', 1)[-1]
    if tag == 'rPh':
        return ''
    if tag == 't':
        return node.text or ''
    return ''.join(visible_text(child) for child in node)


def workbook(file):
    with ZipFile(file) as archive:
        strings = [visible_text(item) for item in ET.fromstring(archive.read('xl/sharedStrings.xml'))]
        relationships = {item.attrib['Id']: item.attrib['Target'] for item in ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))}
        book = ET.fromstring(archive.read('xl/workbook.xml'))
        tables = {}
        for sheet in book.findall('s:sheets/s:sheet', NS):
            target = relationships[sheet.attrib[REL]]
            path = target.lstrip('/') if target.startswith('/') else 'xl/' + target
            cells = {}
            for cell in ET.fromstring(archive.read(path)).findall('.//s:sheetData/s:row/s:c', NS):
                value = cell.find('s:v', NS)
                text = value.text if value is not None else ''
                if cell.get('t') == 's' and text:
                    text = strings[int(text)]
                elif cell.get('t') == 'inlineStr':
                    text = visible_text(cell)
                if text != '':
                    cells[cell.attrib['r']] = text
            tables[sheet.attrib['name']] = cells
        return tables


def mortality(file):
    tables = workbook(file)
    expected = {'male': '令和６年簡易生命表（男）', 'female': '令和６年簡易生命表（女）'}
    require(set(tables) == set(expected.values()), 'Unexpected life-table year/sex sheets')
    observations = []
    for sex, name in expected.items():
        cells = tables[name]
        require(cells['C3'] == '死亡率' and cells['C4'] == 'nqx' and cells['D4'] == 'lx' and cells['E4'] == 'ndx', 'Life-table variable definitions changed')
        note = cells['B122']
        require('n=1年(x=0～104年)' in note and 'n=∞(x=105年)' in note, 'Annual/open-ended intervals changed')
        rows = []
        for age in range(106):
            row = age + 14
            require(cells.get('B' + str(row)) == str(age) + '年', 'Annual age row missing or shifted')
            raw = {key: cells.get(column + str(row), '') for key, column in [('qx', 'C'), ('lx', 'D'), ('dx', 'E'), ('Lx', 'F'), ('Tx', 'G'), ('ex', 'H')]}
            values = {key: number(value, 5 if key == 'qx' else 2 if key == 'ex' else 0) for key, value in raw.items()}
            require(values['qx'] is None or 0 <= values['qx'] <= 1, 'qx outside probability scale')
            require(all(values[key] is None or values[key] >= 0 for key in values), 'Negative life-table value')
            rows.append({
                'source_id': 'mhlw_abridged_life_2024', 'country': 'JPN', 'year': 2024,
                'population': 'Japanese nationals in Japan; period life table',
                'sex_source_category': sex, 'age_exact_years': age,
                'interval_years': None if age == 105 else 1,
                'interval_open_ended': age == 105,
                'qx_denominator': 'life-table survivors at exact age x; conditional on reaching x',
                'qx_unit': 'probability_0_to_1_over_the_named_interval',
                'lx_unit': 'hypothetical_survivors_from_100000_births_not_observed_people',
                'values': values, 'raw_values': raw,
                'missing': [key for key, value in values.items() if value is None],
                'source_sheet': name, 'source_row': row,
                'source_cells': {key: column + str(row) for key, column in [('qx', 'C'), ('lx', 'D'), ('dx', 'E'), ('Lx', 'F'), ('Tx', 'G'), ('ex', 'H')]},
            })
        require(rows[0]['values']['lx'] == 100000, 'The hypothetical life-table radix changed')
        require(rows[-1]['values']['qx'] == 1 and rows[-1]['interval_open_ended'], 'The open final interval was confused with a one-year death certainty')
        # Rounded published columns can differ by one hypothetical person.
        for current, following in zip(rows, rows[1:]):
            a, b = current['values'], following['values']
            if all(a[k] is not None for k in ['lx', 'dx']) and b['lx'] is not None:
                require(abs(a['lx'] - a['dx'] - b['lx']) <= 1, 'Survivor/death identity is inconsistent beyond published rounding')
            if a['qx'] is not None and a['lx'] and a['dx'] is not None:
                require(abs(a['qx'] - a['dx'] / a['lx']) <= 1.5 / a['lx'] + .00001, 'qx denominator/scale inconsistent with life-table counts')
            if a['Tx'] is not None and a['Lx'] is not None and b['Tx'] is not None:
                require(abs(a['Tx'] - a['Lx'] - b['Tx']) <= 1, 'Person-year identity inconsistent beyond rounding')
        observations.extend(rows)
    return observations


def education(payload, metadata):
    require(isinstance(payload, list) and len(payload) == 2 and isinstance(payload[0], dict) and isinstance(payload[1], list), 'Not a World Bank API envelope')
    info, records = payload
    require(info.get('pages') == 1 and info.get('total') == 18 and len(records) == 18, 'Incomplete API page/country/year selection')
    require(isinstance(metadata, list) and len(metadata) == 2 and len(metadata[1]) == 1, 'Missing indicator metadata')
    definition = metadata[1][0]
    require(definition['id'] == 'SE.PRM.AGES' and 'without repeating or skipping a grade' in definition['sourceNote'], 'The theoretical primary-entry definition changed')
    require('UNESCO' in definition['sourceOrganization'] and '2026-02' in definition['sourceOrganization'], 'Unexpected education source/release')
    observations = []
    seen = set()
    for index, item in enumerate(records):
        require(item.get('indicator', {}).get('id') == 'SE.PRM.AGES', 'Wrong school indicator')
        country, year = item.get('countryiso3code'), int(item.get('date', -1))
        require(country in COUNTRIES and year in YEARS and (country, year) not in seen, 'Unexpected/duplicate country-year')
        seen.add((country, year))
        value = item.get('value')
        require(value is None or type(value) in (int, float) and math.isfinite(value) and 0 < value < 20, 'Invalid school starting age')
        observations.append({
            'source_id': 'uis_wdi_primary_age_2026_02', 'indicator': 'SE.PRM.AGES',
            'country': country, 'country_label': item['country']['value'], 'school_reference_year': year,
            'value': value, 'unit': 'years_of_age', 'denominator': None,
            'denominator_note': 'Theoretical education-system entry age; not a ratio, population prevalence or individual enrollment probability',
            'missing_reason': 'source_null' if value is None else None,
            'source_observation_status': item.get('obs_status'), 'source_unit_field': item.get('unit'),
            'source_json_pointer': '/1/' + str(index),
        })
    require(seen == {(country, year) for country in COUNTRIES for year in YEARS}, 'Country-year grid incomplete')
    return sorted(observations, key=lambda item: (item['country'], item['school_reference_year'])), info['lastupdated']


def build(root=ROOT):
    education_rows, updated = education(json.loads((root / 'raw/uis-wdi-primary-age-2019-2024.json').read_text()), json.loads((root / 'raw/uis-wdi-primary-age-metadata.json').read_text()))
    return {
        'schema': 1, 'status': 'calibration_source_snapshot_not_runtime',
        'mortality': {'source_id': 'mhlw_abridged_life_2024', 'basis_period': '2024-01-01/2024-12-31',
                      'excluded_neonatal_rows_per_sex': 8, 'reason_for_exclusion': 'Week/month subdivisions overlap the selected annual age-zero row; raw workbook retains them',
                      'observations': mortality(root / 'raw/mhlw-life2024.xlsx')},
        'education': {'source_id': 'uis_wdi_primary_age_2026_02', 'wdi_last_updated': updated,
                      'observations': education_rows},
        'runtime_conversion': None,
    }


def validate(root=ROOT):
    rebuilt = build(root)
    saved = json.loads((root / 'observations.json').read_text())
    require(saved == rebuilt, 'Saved observations differ from actual source values, intervals or definitions; review before rebuilding')
    catalog = json.loads((root / 'catalog.json').read_text())
    require(catalog['runtime_connected'] is False and len(catalog['sources']) == 2, 'Research status/scope changed')
    for source in catalog['sources']:
        require(source['license']['id'] and source['license']['url'] and source['definition'] and source['missing_policy'], 'Missing source conditions')
    retrieval = json.loads((root / 'retrieval.json').read_text())
    for source in retrieval['files']:
        file = root / source['file']
        require(file.exists() and file.stat().st_size > 0 and source['url'].startswith('https://'), 'Missing retrieved original source')
    require((root / '.gdignore').exists(), 'Research sources must not be imported as runtime assets')
    return {'mortality_rows': len(rebuilt['mortality']['observations']), 'education_rows': len(rebuilt['education']['observations']), 'runtime_connected': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true', help='Explicitly rebuild normalized observations from the reviewed local raw sources')
    args = parser.parse_args()
    if args.build:
        (ROOT / 'observations.json').write_text(json.dumps(build(), ensure_ascii=False, indent=2) + '\n')
    result = validate()
    print('Education/mortality source validation: PASS ' + json.dumps(result, ensure_ascii=False))

"""Small source semantics regressions, not game or demographic fit tests."""
from pathlib import Path
from copy import deepcopy
from io import BytesIO
from tempfile import TemporaryDirectory
from zipfile import ZipFile, ZIP_DEFLATED
from xml.etree import ElementTree as ET
import json
import shutil
import unittest
import validate as evidence

ROOT = Path(__file__).resolve().parent


def changed_cell(cell_id, value):
    output = BytesIO()
    with ZipFile(ROOT / 'raw/mhlw-life2024.xlsx') as source, ZipFile(output, 'w', ZIP_DEFLATED) as target:
        for item in source.infolist():
            body = source.read(item.filename)
            if item.filename == 'xl/worksheets/sheet1.xml':
                tree = ET.fromstring(body)
                cell = next(c for c in tree.findall('.//s:c', evidence.NS) if c.attrib['r'] == cell_id)
                for child in list(cell):
                    cell.remove(child)
                cell.set('t', 'inlineStr')
                strings = ET.SubElement(cell, '{' + evidence.NS['s'] + '}is')
                ET.SubElement(strings, '{' + evidence.NS['s'] + '}t').text = value
                body = ET.tostring(tree)
            target.writestr(item, body)
    output.seek(0)
    return output


class SourceSemantics(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = evidence.build()
        cls.school = json.loads((ROOT / 'raw/uis-wdi-primary-age-2019-2024.json').read_text())
        cls.metadata = json.loads((ROOT / 'raw/uis-wdi-primary-age-metadata.json').read_text())

    def test_actual_sources_match_adopted_values(self):
        self.assertEqual(evidence.validate()['mortality_rows'], 212)
        self.assertEqual(evidence.validate()['education_rows'], 18)

    def test_neonatal_subintervals_not_double_counted(self):
        rows = self.pack['mortality']['observations']
        self.assertEqual(sum(row['age_exact_years'] == 0 for row in rows), 2)
        self.assertEqual({row['interval_years'] for row in rows if row['age_exact_years'] < 105}, {1})
        self.assertEqual(self.pack['mortality']['excluded_neonatal_rows_per_sex'], 8)

    def test_open_age105_not_a_one_year_death_rule(self):
        rows = [row for row in self.pack['mortality']['observations'] if row['age_exact_years'] == 105]
        self.assertTrue(all(row['interval_years'] is None and row['interval_open_ended'] and row['values']['qx'] == 1 for row in rows))
        self.assertTrue(all(row['values']['ex'] > 0 for row in rows))

    def test_life_table_radix_not_population_count(self):
        first = self.pack['mortality']['observations'][0]
        self.assertEqual(first['values']['lx'], 100000)
        self.assertIn('hypothetical', first['lx_unit'])
        self.assertEqual(first['qx_unit'], 'probability_0_to_1_over_the_named_interval')

    def test_marked_missing_mortality_stays_null(self):
        rows = evidence.mortality(changed_cell('C20', '…'))
        self.assertIsNone(rows[6]['values']['qx'])
        self.assertEqual(rows[6]['raw_values']['qx'], '…')
        self.assertEqual(rows[6]['missing'], ['qx'])

    def test_invalid_blank_and_nonfinite_values_rejected(self):
        for raw in ['', 'NaN', 'Infinity']:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                evidence.number(raw)

    def test_wrong_interval_or_variable_rejected(self):
        with self.assertRaises(ValueError):
            evidence.mortality(changed_cell('B14', '0週'))
        with self.assertRaises(ValueError):
            evidence.mortality(changed_cell('C3', '人口千対の粗死亡率'))

    def test_wrong_probability_denominator_rejected(self):
        with self.assertRaises(ValueError):
            evidence.mortality(changed_cell('C14', '0.182'))

    def test_school_age_is_institutional_not_a_ratio(self):
        rows = self.pack['education']['observations']
        self.assertEqual({row['country'] for row in rows}, {'JPN', 'FIN', 'FRA'})
        self.assertTrue(all(row['denominator'] is None and row['unit'] == 'years_of_age' for row in rows))
        self.assertEqual({row['value'] for row in rows if row['country'] == 'FIN'}, {7})
        self.assertEqual({row['value'] for row in rows if row['country'] == 'JPN'}, {6})

    def test_null_school_age_never_filled_from_neighbour(self):
        source = deepcopy(self.school)
        source[1][0]['value'] = None
        rows, _ = evidence.education(source, self.metadata)
        match = next(row for row in rows if row['country'] == 'FIN' and row['school_reference_year'] == 2024)
        self.assertIsNone(match['value'])
        self.assertEqual(match['missing_reason'], 'source_null')

    def test_other_indicator_or_incomplete_page_rejected(self):
        source = deepcopy(self.school);source[1][0]['indicator']['id'] = 'SE.PRM.CMPT.ZS'
        with self.assertRaises(ValueError):
            evidence.education(source, self.metadata)
        source = deepcopy(self.school);source[0]['pages'] = 2
        with self.assertRaises(ValueError):
            evidence.education(source, self.metadata)

    def test_changed_saved_values_fail_actual_source_validation(self):
        with TemporaryDirectory() as directory:
            candidate = Path(directory) / 'pack'
            shutil.copytree(ROOT, candidate, ignore=shutil.ignore_patterns('__pycache__'))
            file = candidate / 'observations.json'
            document = json.loads(file.read_text())
            document['education']['observations'][0]['value'] += 1
            file.write_text(json.dumps(document))
            with self.assertRaises(ValueError):
                evidence.validate(candidate)


if __name__ == '__main__':
    unittest.main(verbosity=2)

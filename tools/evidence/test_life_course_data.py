#!/usr/bin/env python3
"""Offline semantic regression checks for the adopted statistical fixture."""
import copy
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

sys.dont_write_bytecode=True
import life_course_data as data


class LifeCourseDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog=data.read_json(data.PACK/"catalog.json")
        cls.payloads=data.load_payloads(cls.catalog,data.PACK/"raw")
        cls.fixture=data.extract(cls.catalog,cls.payloads)

    def observation(self, identity):
        return next(o for s in self.fixture["series"] for o in s["observations"] if o["id"]==identity)

    def test_adopted_values_and_definitions_match_primary_data(self):
        data.validate_adopted(data.read_json(data.PACK/"observations.json"),self.fixture)

    def test_missing_is_not_zero_or_latest_year_substitution(self):
        self.assertIsNone(self.observation("maternal.JPN.2020.0-2")["value"])
        self.assertIsNone(self.observation("maternal.SWE.2021.0-2")["value"])
        self.assertGreater(self.observation("maternal.SWE.2020.0-2")["value"],0)
        self.assertIsNone(data.numeric("..",("..",)))
        self.assertEqual(data.numeric("0"),0)

    def test_national_cohorts_and_actual_child_bands_are_retained(self):
        japan=self.observation("maternal.JPN.2021.0-2")
        korea=self.observation("maternal.KOR.2021.0-6")
        france=self.observation("maternal.FRA.2021.0-2")
        self.assertEqual(japan["population_unit"],"households_classified_by_youngest_mother")
        self.assertIsNone(japan["age"]["maximum"])
        self.assertEqual(korea["marital_scope"],"married only")
        self.assertNotEqual(korea["youngest_child_age"],france["youngest_child_age"])

    def test_care_standardized_values_and_conditional_denominator(self):
        actual=self.observation("care.2022.care_5.almost_all_day")
        self.assertEqual(actual["value"],1821)
        self.assertEqual(actual["grade_total_per_100000"],2885)
        self.assertAlmostEqual(actual["derived_conditional_percent"],1821/2885*100,places=5)
        self.assertEqual(actual["population_unit"],"standardized_composition_not_actual_person_count")
        self.assertGreater(self.observation("care.2022.care_5.unknown")["value"],0)

    def test_missing_definition_and_incorrect_unit_are_rejected(self):
        broken=copy.deepcopy(self.fixture);broken["series"][0]["observations"][0].pop("age")
        with self.assertRaises(data.DataError):data.validate(broken)
        broken=copy.deepcopy(self.fixture);broken["series"][-1]["unit"]="persons"
        with self.assertRaises(data.DataError):data.validate(broken)
        broken=copy.deepcopy(self.fixture);broken["series"][0]["individual_transition_probability"]=True
        with self.assertRaises(data.DataError):data.validate(broken)
        broken=copy.deepcopy(self.fixture);broken["series"][0]["observations"][0]["age"]["minimum"]=-1
        with self.assertRaises(data.DataError):data.validate(broken)

    def test_modified_adopted_value_is_detected_by_actual_numeric_comparison(self):
        broken=copy.deepcopy(self.fixture);broken["series"][0]["observations"][0]["value"]+=1
        with self.assertRaises(data.DataError):data.validate_adopted(broken,self.fixture)

    def test_unknown_care_bucket_and_denominator_cannot_disappear(self):
        broken=copy.deepcopy(self.fixture)
        broken["series"][-1]["observations"]=[o for o in broken["series"][-1]["observations"] if o["care_time_category"]!="unknown"]
        with self.assertRaises(data.DataError):data.validate(broken)
        broken=copy.deepcopy(self.fixture);broken["series"][-1]["observations"][1]["grade_total_per_100000"]+=1
        with self.assertRaises(data.DataError):data.validate(broken)

    def test_nonfinite_values_rejected_and_gross_flows_not_probabilities(self):
        for text in ["NaN","Infinity","-Infinity"]:
            with self.assertRaises(data.DataError):data.numeric(text)
        broken=copy.deepcopy(self.fixture);broken["series"][1]["observations"][0]["value"]=120
        data.validate(broken)  # gross annual establishment turnover may exceed 100%
        broken["series"][0]["observations"][0]["value"]=120
        with self.assertRaises(data.DataError):data.validate(broken)

    def test_source_label_change_rejected_before_wrong_column_is_adopted(self):
        original=zipfile.ZipFile(io.BytesIO(self.payloads["mhlw_employment_2024"]))
        output=io.BytesIO()
        with zipfile.ZipFile(output,"w") as replacement:
            for item in original.infolist():
                payload=original.read(item.filename)
                if item.filename=="xl/worksheets/sheet2.xml":
                    root=ET.fromstring(payload)
                    cell=root.find(".//m:c[@r='E4']",data.NS)
                    for child in list(cell):cell.remove(child)
                    cell.set("t","inlineStr")
                    inline=ET.SubElement(cell,"{"+data.NS["m"]+"}is")
                    ET.SubElement(inline,"{"+data.NS["m"]+"}t").text="別の率"
                    payload=ET.tostring(root)
                replacement.writestr(item,payload)
        changed=dict(self.payloads);changed["mhlw_employment_2024"]=output.getvalue()
        with self.assertRaises(data.DataError):data.extract(self.catalog,changed)

    def test_wrong_care_unit_rejected_in_raw_download(self):
        changed=dict(self.payloads)
        changed["mhlw_csls_2022_care82"]=changed["mhlw_csls_2022_care82"].replace("介護を要する者数10万対".encode("cp932"),"実人数".encode("cp932"))
        with self.assertRaises(data.DataError):data.extract(self.catalog,changed)

    def test_oversized_fetch_does_not_replace_local_snapshot(self):
        class TooLarge:
            headers={"Content-Length":"2000001"}
            def __enter__(self):return self
            def __exit__(self,*_args):pass
        with tempfile.TemporaryDirectory() as temporary:
            raw=Path(temporary)/"raw";raw.mkdir();sentinel=raw/"keep.txt";sentinel.write_text("current")
            with patch("life_course_data.urllib.request.urlopen",return_value=TooLarge()):
                with self.assertRaises(data.DataError):data.fetch(self.catalog,raw)
            self.assertEqual(sentinel.read_text(),"current")
            self.assertEqual([p.name for p in raw.iterdir()],["keep.txt"])

    def test_design_conditions_reference_actual_series_without_claiming_execution(self):
        cases=data.read_json(data.PACK/"calibration-cases.json")
        self.assertEqual(cases["status"],"design_conditions_not_executed_in_game")
        self.assertEqual(len(cases["cases"]),3)
        actual={s["id"] for s in self.fixture["series"]}
        for case in cases["cases"]:
            self.assertTrue(set(case["source_series"])<=actual)
            self.assertTrue(case["what_the_data_does_not_support"])
            self.assertTrue(case["visible_acceptance"])


if __name__=="__main__":
    unittest.main()

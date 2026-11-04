#!/usr/bin/env python3
"""Fetch a small, pinned primary-source pack and validate actual data/definitions.

Python standard library only. No hashes are used as validation. A changed
upstream value or label must be reviewed explicitly; --fetch never rewrites the
adopted observations. --build performs the deliberate fixture update.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import io
import json
import math
from pathlib import Path
import posixpath
import re
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "data/evidence/life-course"
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
REL_ID = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"
STATUS = "source_fixture_not_connected_to_runtime"


class DataError(ValueError):
    pass


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value):
    """Atomic replacement, so interruption cannot leave half a valid pack."""
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as out:
        temporary = Path(out.name)
        out.write(text)
    temporary.replace(path)


def numeric(raw, missing_tokens=()):
    if raw in missing_tokens:
        return None
    try:
        value = Decimal(str(raw).strip())
    except (InvalidOperation, ValueError):
        raise DataError(f"Not a numeric observation: {raw!r}") from None
    if not value.is_finite():
        raise DataError("Non-finite observations are not permitted")
    # Remove binary spreadsheet roundoff while retaining the original text.
    return round(float(value), 6)


def normalized(text):
    return " ".join(str(text).split())


def xlsx_text(container):
    """Rich text excluding Japanese phonetic guides (rPh), not itertext()."""
    if container is None:
        return ""
    return "".join((child.text or "") if child.tag.endswith("}t") else
                   "".join(t.text or "" for t in child.findall("m:t", NS))
                   if child.tag.endswith("}r") else "" for child in container)


class Workbook:
    def __init__(self, payload: bytes):
        self.archive = zipfile.ZipFile(io.BytesIO(payload))
        if sum(info.file_size for info in self.archive.infolist()) > 20_000_000:
            raise DataError("Expanded workbook exceeds this pack's bounded size")
        strings = self.archive.read("xl/sharedStrings.xml")
        self.strings = [xlsx_text(node) for node in ET.fromstring(strings).findall("m:si", NS)]
        relations = {node.get("Id"): node.get("Target") for node in
                     ET.fromstring(self.archive.read("xl/_rels/workbook.xml.rels"))}
        self.paths = {}
        for sheet in ET.fromstring(self.archive.read("xl/workbook.xml")).findall("m:sheets/m:sheet", NS):
            target = relations[sheet.get(REL_ID)]
            path = target.lstrip("/") if target.startswith("/") else posixpath.normpath(posixpath.join("xl", target))
            if not path.startswith("xl/worksheets/"):
                raise DataError("Unexpected workbook relationship")
            self.paths[sheet.get("name")] = path
        self.cache = {}

    def sheet(self, name):
        if name not in self.paths:
            raise DataError(f"Missing worksheet: {name}")
        if name not in self.cache:
            cells = {}
            for node in ET.fromstring(self.archive.read(self.paths[name])).findall(".//m:c", NS):
                value = node.find("m:v", NS)
                raw = value.text if value is not None else xlsx_text(node.find("m:is", NS))
                if node.get("t") == "s":
                    raw = self.strings[int(raw)]
                cells[node.get("r")] = raw if raw is not None else ""
            self.cache[name] = cells
        return self.cache[name]

    def get(self, sheet, cell):
        cells = self.sheet(sheet)
        if cell not in cells:
            raise DataError(f"Missing source cell: {sheet}!{cell}")
        return cells[cell]

    def require(self, sheet, cell, expected):
        actual = self.get(sheet, cell)
        if normalized(actual) != normalized(expected):
            raise DataError(f"Changed definition at {sheet}!{cell}: {actual!r}")


def source_map(catalog):
    if catalog.get("schema_version") != 1 or catalog.get("status") != STATUS:
        raise DataError("Unsupported catalog or runtime-complete claim")
    sources = catalog.get("sources", [])
    if len(sources) != 3 or len({s["id"] for s in sources}) != 3:
        raise DataError("This pack has exactly three declared primary inputs")
    for source in sources:
        for key in ["publisher", "title", "version", "url", "landing_url", "raw_file", "license", "definition_urls", "missing_policy"]:
            if not source.get(key):
                raise DataError(f"Missing source metadata: {source['id']}/{key}")
        if Path(source["raw_file"]).name != source["raw_file"]:
            raise DataError("Raw inputs must be plain filenames")
        limit=source.get("max_bytes")
        if type(limit) is not int or not 1<=limit<=2_000_000:
            raise DataError("The declared download bound must be positive and at most 2 MB")
        parsed = urllib.parse.urlparse(source["url"])
        if parsed.scheme != "https" or parsed.hostname not in ["webfs.oecd.org", "www.mhlw.go.jp", "www.e-stat.go.jp"]:
            raise DataError("Only the adopted official HTTPS sources are fetched")
    return {s["id"]: s for s in sources}


def fetch(catalog, folder: Path):
    sources = source_map(catalog)
    pending = []
    for source in sources.values():
        request = urllib.request.Request(source["url"], headers={"User-Agent": "HourglassOfLife-evidence/1.0 (small public statistics snapshot)"})
        maximum = min(int(source.get("max_bytes", 2_000_000)), 2_000_000)
        with urllib.request.urlopen(request, timeout=30) as response:
            content_length = response.headers.get("Content-Length")
            if content_length and int(content_length) > maximum:
                raise DataError("Source exceeds the declared download limit")
            payload = response.read(maximum + 1)
            if len(payload) > maximum:
                raise DataError("Source exceeds the declared download limit")
            metadata = {"source_id": source["id"], "url": source["url"], "resolved_url": response.geturl(),
                        "retrieved_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                        "bytes": len(payload), "content_type": response.headers.get("Content-Type"),
                        "last_modified": response.headers.get("Last-Modified")}
        pending.append((source, payload, metadata))
    # Parse and validate the whole prospective data pack before any raw input
    # replaces its predecessor. Fetching does not change the adopted fixture.
    extract(catalog, {source["id"]: payload for source, payload, _ in pending})
    folder.mkdir(parents=True, exist_ok=True)
    for source, payload, _ in pending:
        path = folder / source["raw_file"]
        with tempfile.NamedTemporaryFile("wb", dir=folder, delete=False) as out:
            temporary = Path(out.name);out.write(payload)
        temporary.replace(path)
    write_json(folder.parent / "retrieval.json", {"schema_version": 1, "sources": [item[2] for item in pending]})


def maternal(payload, catalog):
    book = Workbook(payload)
    sheet = "MER-Child-Age-15-64"
    book.require(sheet, "A1", "Maternal employment rates by age of youngest child")
    book.require(sheet, "A221", ".. Not available")
    observations = []
    for country in catalog["maternal_cohorts"]:
        first = country["first_group_row"]
        book.require(sheet, "A" + str(first-2), country["source_country_label"])
        for index, band in enumerate(country["youngest_child_bands"]):
            row = first+index
            label = f"Youngest child aged {band[0]}-{band[1]}"
            book.require(sheet, "D" + str(row), label)
            for year, column in [(2019, "Z"), (2020, "AA"), (2021, "AB")]:
                book.require(sheet, column+"4", str(year))
                cell = column+str(row)
                raw = book.get(sheet, cell)
                value = numeric(raw, ("..",))
                observations.append({"id": f"maternal.{country['country']}.{year}.{band[0]}-{band[1]}",
                    "country": country["country"], "year": year, "sex": "female", "age": country["age"],
                    "population_unit": country["population_unit"], "denominator": country["denominator"],
                    "youngest_child_age": {"minimum": band[0], "maximum": band[1]},
                    "marital_scope": country["marital_scope"], "value": value,
                    "missing_reason": "source_not_available_or_suppressed" if value is None else None,
                    "source_location": {"sheet": sheet, "cell": cell, "raw": raw}})
    return {"id": "maternal_employment", "source_id": "oecd_lmf12_2023", "metric": "maternal_employment_rate",
            "measure_kind": "state_share", "unit": "percent", "period": "survey_reference_year",
            "comparison": "Descriptive only; national cohorts, age bands and source years differ. Repeated cross-sections are not maternal return-to-work transitions.",
            "observations": observations}


def employment(payload):
    book = Workbook(payload)
    rates = "表1-2常用労働者の動き（率）"
    changers = "表3-2性・就業形態、職歴別入職率"
    wages = "表6転職入職者の賃金変動状況別割合"
    book.require(rates, "E4", "入職率");book.require(rates, "F4", "離職率")
    book.require(changers, "E4", "転職入職率")
    book.require(wages, "F4", "増加");book.require(wages, "J4", "減少")
    book.require(wages, "B48", "注：　1) 転職入職者のうち前職雇用者で調査時在籍者についてみたものである（自営業からの転職入職者を含まない）。")
    observations = []
    wage_observations = []
    for year, offset, wage_row in [(2024, 0, 7), (2023, 6, 21)]:
        book.require(rates, "B"+str(6+offset), f"令和{'６' if year==2024 else '５'}年（{year}）")
        for group, label, row in [("all", "計", 7+offset), ("general", "一般労働者", 10+offset), ("part_time", "パートタイム労働者", 11+offset)]:
            book.require(rates, "C"+str(row), label)
            for metric, sheet, column in [("hires",rates,"E"),("separations",rates,"F"),("hires_with_job_in_previous_year",changers,"E")]:
                cell = column+str(row);raw = book.get(sheet, cell)
                observations.append({"id":f"employment.{year}.{group}.{metric}","country":"JPN","year":year,
                    "sex":"all_reported","age":{"minimum":None,"maximum":None,"label":"all ages of covered regular employees"},
                    "employment_type":group,"metric":metric,"value":numeric(raw),"missing_reason":None,
                    "population_unit":"establishment_worker_flows","denominator":"regular employees on 1 January of the same year in covered establishments",
                    "comparison_basis":"2023_original_publication_not_benchmark_adjusted" if year==2023 else "2024_benchmark",
                    "source_location":{"sheet":sheet,"cell":cell,"raw":raw}})
        for direction, column in [("increase","F"),("unchanged","I"),("decrease","J")]:
            cell=column+str(wage_row);raw=book.get(wages,cell)
            wage_observations.append({"id":f"wage.{year}.{direction}","country":"JPN","year":year,"sex":"all_reported",
                "age":{"minimum":None,"maximum":None,"label":"all ages of covered job-changing entrants"},
                "direction":direction,"value":numeric(raw),"missing_reason":None,"population_unit":"job_changing_former_employees_still_registered_at_survey",
                "denominator":"job-changing entrants previously employed as workers and still registered at the survey; excludes former self-employed; includes wage-change status not stated",
                "source_location":{"sheet":wages,"cell":cell,"raw":raw}})
    return [{"id":"employment_flows","source_id":"mhlw_employment_2024","measure_kind":"annual_gross_flow_rate",
             "unit":"percent_of_beginning_year_employees","period":"calendar_year","comparison":"2023/2024 benchmark break; do not infer a simple year-on-year trend or individual re-employment probability.","observations":observations},
            {"id":"job_change_wage","source_id":"mhlw_employment_2024","measure_kind":"composition_share","unit":"percent",
             "period":"calendar_year","comparison":"Conditional on former employees who entered and remained registered at the survey; excludes former self-employed and entrants no longer registered. Not all unemployed people. Unstated category remains in denominator.","observations":wage_observations}]


def caregiving(payload):
    rows = list(csv.reader(io.StringIO(payload.decode("cp932"))))
    if len(rows)!=11 or normalized(rows[0][0])!="2022(令和4)年" or rows[0][3]!="介護を要する者数10万対" or "第082表" not in rows[1][0]:
        raise DataError("Changed care table date, denominator, unit, or shape")
    if rows[2][0]!="主な介護者の介護時間" or rows[4][0]!="総数":
        raise DataError("Changed care row definitions")
    columns = [(1,"all","総数"),(3,"support_1","要支援１"),(4,"support_2","要支援２"),(6,"care_1","要介護１"),
               (7,"care_2","要介護２"),(8,"care_3","要介護３"),(9,"care_4","要介護４"),(10,"care_5","要介護５")]
    categories = [(5,"almost_all_day","ほとんど終日"),(6,"about_half_day","半日程度"),(7,"two_to_three_hours","２～３時間程度"),
                  (8,"as_needed","必要なときに手をかす程度"),(9,"other","その他"),(10,"unknown","不詳")]
    observations = []
    for column, grade, label in columns:
        if label not in [rows[2][column],rows[3][column]]:
            raise DataError("Changed care-grade column order")
        total = numeric(rows[4][column])
        if total<=0:
            raise DataError("A conditional care denominator is zero")
        for row, category, label in categories:
            if rows[row][0].strip()!=label:
                raise DataError("Changed care-time category")
            raw=rows[row][column];value=numeric(raw)
            observations.append({"id":f"care.2022.{grade}.{category}","country":"JPN","year":2022,"sex":"all_reported",
                "age":{"minimum":None,"maximum":None,"label":"all reported co-resident main caregivers; recipient is home-based and certified for long-term care/support"},
                "care_grade":grade,"care_time_category":category,"value":value,"missing_reason":None,
                "population_unit":"standardized_composition_not_actual_person_count","denominator":"100000 home-based people certified as needing long-term care or support, across all grades",
                "grade_total_per_100000":total,"derived_conditional_percent":round(value/total*100,6),
                "derivation":"100 * published cell / published co-resident-main-carer total in the same grade column; inputs are rounded",
                "source_location":{"row_1_based":row+1,"column_1_based":column+1,"raw":raw,"denominator_row_1_based":5}})
    return {"id":"care_time","source_id":"mhlw_csls_2022_care82","measure_kind":"standardized_composition","unit":"per_100000_care_recipients",
            "period":"June_2022_survey","comparison":"Not incidence, recovery, care hours, or a count of 45865 real people. Qualitative all-day/half-day categories do not specify exact hours.","observations":observations}


def extract(catalog, payloads):
    sources = source_map(catalog)
    if set(payloads)!=set(sources):
        raise DataError("Every declared primary input must be present")
    series = [maternal(payloads["oecd_lmf12_2023"], catalog)]
    series.extend(employment(payloads["mhlw_employment_2024"]))
    series.append(caregiving(payloads["mhlw_csls_2022_care82"]))
    for record in series:
        record["individual_transition_probability"] = False
    result = {"schema_version":1,"status":STATUS,"generated_by":"tools/evidence/life_course_data.py","rounding":"up to 6 decimal places; original source text retained","series":series}
    validate(result)
    return result


def validate(fixture):
    if fixture.get("schema_version")!=1 or fixture.get("status")!=STATUS:
        raise DataError("Unsupported fixture state")
    seen = set()
    expected_units={"maternal_employment":"percent","employment_flows":"percent_of_beginning_year_employees","job_change_wage":"percent","care_time":"per_100000_care_recipients"}
    expected_measures={"maternal_employment":"state_share","employment_flows":"annual_gross_flow_rate","job_change_wage":"composition_share","care_time":"standardized_composition"}
    series_by_id={series.get("id"):series for series in fixture.get("series",[])}
    if set(series_by_id)!=set(expected_units) or len(fixture["series"])!=len(expected_units):
        raise DataError("Series are missing or duplicated")
    for series in fixture["series"]:
        if series.get("unit")!=expected_units[series["id"]]:
            raise DataError("Unit/measure mismatch")
        if series.get("measure_kind")!=expected_measures[series["id"]] or series.get("individual_transition_probability") is not False:
            raise DataError("A composition or gross flow cannot be relabelled as an individual transition probability")
        for observation in series["observations"]:
            if observation["id"] in seen:
                raise DataError("Duplicated observation")
            seen.add(observation["id"])
            for key in ["age","sex","country","year","denominator","population_unit","source_location"]:
                if not observation.get(key):
                    raise DataError(f"Missing observation definition: {key}")
            age=observation["age"]
            if not isinstance(age,dict) or set(age)!={"minimum","maximum","label"} or not isinstance(age["label"],str) or not age["label"]:
                raise DataError("Age bounds require an explicit cohort label")
            for bound in [age["minimum"],age["maximum"]]:
                if bound is not None and (type(bound) is not int or not 0<=bound<=130):
                    raise DataError("Invalid age bound")
            if age["minimum"] is not None and age["maximum"] is not None and age["minimum"]>age["maximum"]:
                raise DataError("Inverted age cohort")
            if observation["sex"] not in ["female","all_reported"] or observation["country"] not in ["JPN","FRA","SWE","KOR"] or type(observation["year"]) is not int or observation["year"] not in [2019,2020,2021,2022,2023,2024]:
                raise DataError("Unexpected region, year or reported-sex category")
            value=observation.get("value")
            if value is None:
                if observation.get("missing_reason")!="source_not_available_or_suppressed":
                    raise DataError("Missing data cannot silently become zero")
            else:
                ceiling = 100000 if series["id"]=="care_time" else None if series["id"]=="employment_flows" else 100
                # Gross establishment flows can in principle exceed 100%;
                # they are not Bernoulli transition probabilities.
                if isinstance(value,bool) or not isinstance(value,(float,int)) or not math.isfinite(value) or value<0 or (ceiling is not None and value>ceiling):
                    raise DataError("Observation outside its declared measure range")
    care=series_by_id["care_time"]["observations"]
    for grade in {item["care_grade"] for item in care}:
        group=[item for item in care if item["care_grade"]==grade]
        if len(group)!=6 or {item["care_time_category"] for item in group}!={"almost_all_day","about_half_day","two_to_three_hours","as_needed","other","unknown"}:
            raise DataError("Care composition must retain its unknown category")
        total=group[0]["grade_total_per_100000"]
        if any(item["grade_total_per_100000"]!=total for item in group):
            raise DataError("Care observations disagree on their conditional denominator")
        if abs(sum(item["value"] for item in group)-total)>3:
            raise DataError("Care components do not reconcile within published rounding")
        for item in group:
            if abs(item["derived_conditional_percent"]-round(item["value"]/total*100,6))>1e-8:
                raise DataError("Incorrect conditional care denominator")


def load_payloads(catalog, folder):
    return {s["id"]:(folder/s["raw_file"]).read_bytes() for s in source_map(catalog).values()}


def validate_adopted(adopted, extracted):
    validate(adopted)
    if adopted!=extracted:
        raise DataError("Adopted values/definitions differ from current primary extraction; review before --build")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack",type=Path,default=PACK)
    parser.add_argument("--fetch",action="store_true",help="Reacquire the three small primary inputs; does not adopt new values")
    parser.add_argument("--build",action="store_true",help="Explicitly rebuild the adopted observations from the raw inputs")
    parser.add_argument("--validate",action="store_true",help="Compare adopted numeric values and definitions with fresh extraction of local raw files")
    args=parser.parse_args()
    if not (args.fetch or args.build or args.validate): parser.error("Choose --fetch, --build, or --validate")
    catalog=read_json(args.pack/"catalog.json");raw=args.pack/"raw"
    try:
        if args.fetch: fetch(catalog,raw)
        extracted=extract(catalog,load_payloads(catalog,raw))
        if args.build: write_json(args.pack/"observations.json",extracted)
        if args.validate:
            validate_adopted(read_json(args.pack/"observations.json"),extracted)
        print(json.dumps({"status":"validated" if args.validate else "extracted","sources":len(catalog["sources"]),
              "series":len(extracted["series"]),"observations":sum(len(s["observations"]) for s in extracted["series"]),
              "missing_observations":sum(o["value"] is None for s in extracted["series"] for o in s["observations"]),
              "runtime_connected":False},ensure_ascii=False))
    except (DataError, OSError, KeyError, ET.ParseError, zipfile.BadZipFile) as error:
        raise SystemExit(f"Life-course data rejected: {error}") from None


if __name__=="__main__":
    main()

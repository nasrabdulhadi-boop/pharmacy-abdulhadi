#!/usr/bin/env python3
"""Verify/refresh three hand-selected short label excerpts for REVIEW ONLY.

No pharmacy access, source licensing claim, clinical approval or runtime rule activation.
Only NLM's official HTTPS host is used. Full XML stays in memory; at most 25 quoted
words per label are written, with source/version/section/hash for later review.
"""
import argparse
import datetime
import hashlib
import json
import re
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {"s": "urn:hl7-org:v3"}
CASES = [
    {"set_id": "de8b0b67-eb25-4684-83b5-7ad785314227", "ingredient_a": "clopidogrel", "ingredient_b": "omeprazole", "section_prefix": "7.2"},
    {"set_id": "d905dc8d-917f-4ea3-a4ee-a1ecf6967d4e", "ingredient_a": "sildenafil", "ingredient_b": "riociguat", "section_prefix": "4.3"},
    {"set_id": "b98b02bb-2609-49a0-b29f-e5911aa0cbc1", "ingredient_a": "clarithromycin", "ingredient_b": "simvastatin", "section_prefix": "5.4"},
]

def text(node):
    return " ".join(" ".join(node.itertext()).split()) if node is not None else ""

def attribute(node, path, name):
    found = node.find(path, NS)
    return found.get(name) if found is not None else None

def extract_case(xml_bytes, case, retrieved_at):
    if len(xml_bytes) > 5_000_000 or b"<!DOCTYPE" in xml_bytes.upper() or b"<!ENTITY" in xml_bytes.upper():
        raise ValueError("Oversized or unsafe XML")
    root = ET.fromstring(xml_bytes)
    set_id = attribute(root, "s:setId", "root")
    if set_id != case["set_id"]:
        raise ValueError("SPL set ID mismatch")
    matches = []
    for section in root.findall(".//s:section", NS):
        title = text(section.find("s:title", NS))
        if not title.startswith(case["section_prefix"]):
            continue
        body = text(section.find("s:text", NS))
        match = re.search(re.escape(case["quote"]), body, re.IGNORECASE)
        if match:
            matches.append((section, title, match.group(0)))
    if len(matches) != 1:
        raise ValueError("Expected one source section/excerpt match for " + case["ingredient_a"])
    section, title, excerpt = matches[0]
    if len(excerpt.split()) > 25:
        raise ValueError("Excerpt word limit exceeded")
    document_id = attribute(root, "s:id", "root")
    version = attribute(root, "s:versionNumber", "value")
    effective = attribute(root, "s:effectiveTime", "value")
    section_id = attribute(section, "s:id", "root")
    if not all([document_id, version, effective, section_id]):
        raise ValueError("Missing SPL provenance")
    return {
        "source_id": "DailyMed-SPL", "source_record_id": document_id + ":" + section_id,
        "source_version": version, "label_set_id": set_id, "label_document_id": document_id,
        "effective_time": effective, "retrieved_at": retrieved_at,
        "source_url": "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=" + set_id,
        "source_xml_url": "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls/" + set_id + ".xml",
        "source_sha256": hashlib.sha256(xml_bytes).hexdigest(), "section_id": section_id,
        "section_title": title, "ingredient_a": case["ingredient_a"], "ingredient_b": case["ingredient_b"],
        "evidence_kind": "label", "original_text": excerpt, "excerpt_is_not_full_guidance": True,
        "route_names": sorted({x.get("displayName") for x in root.findall(".//s:routeCode", NS) if x.get("displayName")}),
        "license_status": "unknown", "license_reference": None,
        "review_status": "pending", "clinical_approved": False,
        "source_check": "excerpt_matched_primary_spl", "negative_safety_claim_allowed": False,
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--manifest", default=str(Path(__file__).resolve().parents[1] / "docs/CLINICAL_PRIMARY_LABEL_CASES_2026-10-26.json"))
    args = parser.parse_args()
    manifest = json.loads(Path(args.manifest).read_text(encoding="utf-8"))
    if manifest.get("mode") != "primary_label_review_candidates" or manifest.get("clinicalRulesActivated") != 0 or manifest.get("productionEnabled") is not False:
        raise ValueError("Review-only manifest is required")
    retrieved = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds")
    rows = []
    for case in CASES:
        selected = [row for row in manifest["cases"] if row.get("label_set_id") == case["set_id"] and row.get("ingredient_a") == case["ingredient_a"] and row.get("ingredient_b") == case["ingredient_b"]]
        if len(selected) != 1 or not isinstance(selected[0].get("original_text"), str):
            raise ValueError("Exactly one hand-selected excerpt is required")
        case = {**case, "quote": selected[0]["original_text"]}
        url = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls/" + case["set_id"] + ".xml"
        request = urllib.request.Request(url, headers={"User-Agent": "PharmacyClinicalResearch/1.0"})
        with urllib.request.urlopen(request, timeout=20) as response:
            if not response.url.startswith("https://dailymed.nlm.nih.gov/"):
                raise ValueError("Unexpected source redirect")
            rows.append(extract_case(response.read(5_000_001), case, retrieved))
    packet = {"mode": "primary_label_review_candidates", "clinicalRulesActivated": 0, "productionEnabled": False, "cases": rows}
    Path(args.output).write_text(json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": args.output, "source_cases": len(rows), "clinical_rules_activated": 0}))

if __name__ == "__main__":
    main()

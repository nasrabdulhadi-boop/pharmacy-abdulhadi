"""Read public RxNorm identities for research. Never approves aliases or writes to a pharmacy DB."""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

DEFAULT_NAMES = [
    "paracetamol", "diclofenac sodium", "ibuprofen", "amoxicillin",
    "clavulanic acid", "aspirin", "atorvastatin", "metronidazole",
    "azithromycin", "rosuvastatin", "metformin", "amlodipine", "valsartan",
    "dexamethasone", "cefuroxime", "ciprofloxacin", "gentamicin",
]
ROOT = "https://rxnav.nlm.nih.gov/REST/"


def retrieve(path):
    url = ROOT + path
    request = Request(url, headers={"Accept": "application/json"})
    with urlopen(request, timeout=12) as response:
        return json.load(response), url


def collect(names):
    version, version_url = retrieve("version.json")
    rows = []
    for name in names:
        row = {"query": name, "search_mode": "exact_only", "status": "candidate",
               "clinically_approved": False, "properties": []}
        try:
            result, row["query_url"] = retrieve("rxcui.json?" + urlencode({"name": name, "search": 0}))
            row["returned_ids"] = result.get("idGroup", {}).get("rxnormId", [])
            for concept in row["returned_ids"]:
                if not str(concept).isdigit():
                    raise ValueError("Unexpected concept identifier")
                properties, url = retrieve("rxcui/" + concept + "/properties.json")
                row["properties"].append({"source_url": url, "result": properties.get("properties")})
            row["resolution"] = "single_candidate" if len(row["returned_ids"]) == 1 else "requires_review"
        except Exception as error:
            row["resolution"] = "retrieval_failed"
            row["error_type"] = type(error).__name__
        rows.append(row)
        print(name + ": " + row["resolution"], flush=True)
    final_version, _ = retrieve("version.json")
    return {"retrieved_at": datetime.now(timezone.utc).isoformat(), "version_url": version_url,
            "version": version, "version_after": final_version,
            "consistent_version": version == final_version, "records": rows,
            "clinical_rules_activated": 0, "production_enabled": False,
            "notice": "RxNorm identities are not DDI rules, Arabic translations, product composition verification, or clinical approval.",
            "attribution": "This product uses publicly available data from the U.S. National Library of Medicine (NLM), National Institutes of Health, Department of Health and Human Services; NLM is not responsible for the product and does not endorse or recommend this or any other product."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--names", nargs="+", default=DEFAULT_NAMES)
    args = parser.parse_args()
    if len(args.names) > 50:
        parser.error("At most 50 research names per run")
    snapshot = collect(args.names)
    Path(args.output).write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

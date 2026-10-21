#!/usr/bin/env python3
"""Render an existing audit's evidence as a searchable offline matrix and CSV."""
import argparse
import json
from pathlib import Path
from manga_audit.matrix import write_matrix

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("report", type=Path)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
matrix = write_matrix(args.output, json.loads(args.report.read_text()))
print(json.dumps({"rows": len(matrix["rows"]), "statuses": matrix["sourceStatuses"], "output": str(args.output)}))

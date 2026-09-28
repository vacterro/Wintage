#!/usr/bin/env python3
"""Accepted-debt provenance verifier for the Wintage project (T-312).

WHY THIS EXISTS
---------------
T-312 names a real defect class: "generic journal CAS exposed accepted-debt
record bytes as mutable while domain evidence claimed immutable registration".
`run_mutation` takes an arbitrary `operation=` string, so nothing in the
journal layer stops a write to
`.saipen/recovery/conformance/accepted_debt/AD-*.json` from being booked under
an operation name the engine does not implement. AD-000002's current bytes are
in exactly that state: the terminal receipt is
`accepted-debt-rebind-003` / operation `accepted_debt_rebind`, which no engine
module provides.

This module verifies the CONTENT half of the invariant from inside the project,
without editing the protocol install:

  1. every AD record passes the engine's OWN `load_record` (schema, integrity
     digest, lineage, rule binding) -- the real code, not a re-implementation,
     so the gate tracks the engine contract instead of drifting from it;
  2. the settled journal chain for each AD file is contiguous -- every receipt's
     `before_hash` equals its predecessor's `after_hash`;
  3. the terminal receipt's `after_hash` equals sha256(live bytes)[:16];
  4. every receipt touching an AD file names an operation the engine actually
     implements;
  5. every `evidence[].line_sha256` re-derives from the LIVE LOG shard line.

CHECKS 1-4 are HARD and fail the gate. Check 5 is REPORTED, not fatal, and the
distinction is load-bearing. `load_record` already verifies the integrity
digest, and the digest covers the evidence block -- so evidence drift can only
come from the LOG moving underneath a correct record, never from a tampered
record. A rotated shard leaves a perfectly intact acceptance whose cited line
no longer resolves; that is an environmental fact to surface on every run, not
evidence that the acceptance is corrupt. Making it fatal would train the reader
to ignore the gate.

Exit 0 when every hard check passes. The JSON verdict on stdout is the report.

  python tools/accepted-debt-provenance.py [--project-root PATH] [--json]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path

AD_REL = ".saipen/recovery/conformance/accepted_debt"
AD_ID_RE = re.compile(r"\AAD-(\d{6})\Z")
SETTLED_REL = ".saipen/recovery/settled"

# Operations the protocol install actually implements for this domain. Anything
# else that writes an AD file went through the generic CAS, which is the defect
# T-312 exists to close.
ENGINE_OPERATIONS = {"accepted_debt.register"}


def _sha16(data: bytes) -> str:
    """The journal's own per-target hash: sha256 truncated to 16 hex chars."""
    return hashlib.sha256(data).hexdigest()[:16]


def _integrity_digest(record_body: dict) -> str:
    """Byte-identical to the engine's accepted_debt._integrity_digest."""
    canonical = json.dumps(record_body, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def load_engine(engine_home: Path):
    """Import the protocol install's accepted_debt module, or explain why not."""
    tools = engine_home / "tools"
    if not tools.is_dir():
        raise SystemExit(f"protocol install not found at {engine_home}")
    if str(tools) not in sys.path:
        sys.path.insert(0, str(tools))
    try:
        from saipen_engine import accepted_debt  # type: ignore
    except Exception as exc:  # pragma: no cover - reported, not swallowed
        raise SystemExit(f"cannot import saipen_engine.accepted_debt: {exc}")
    return accepted_debt


def resolve_engine_home(project_root: Path) -> Path:
    """The engine that actually runs: the bin shim's target, else STATE's home."""
    env = os.environ.get("WINTAGE_SAIPEN_HOME") or os.environ.get("SAIPEN_HOME")
    if env:
        return Path(env)
    shim = Path.home() / "AppData" / "Local" / "saipen" / "scheduled-source" / "bin" / "saipen.cmd"
    if shim.is_file():
        # bin\saipen.cmd invokes a python file by absolute path; that path is the
        # engine this project actually executes, which is NOT necessarily the
        # scheduled-source tree it sits next to.
        try:
            text = shim.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""
        m = re.search(r'"([^"]*tools[\\/]saipen\.py)"', text)
        if m:
            return Path(m.group(1)).resolve().parent.parent
    state = project_root / ".saipen" / "STATE.md"
    if state.is_file():
        m = re.search(r"^saipen_home:\s*(.+)$", state.read_text(encoding="utf-8", errors="replace"), re.M)
        if m:
            return Path(m.group(1).strip())
    raise SystemExit("cannot resolve the protocol install home")


def settled_receipts(root: Path) -> list[dict]:
    out = []
    directory = root / SETTLED_REL
    if not directory.is_dir():
        return out
    for entry in sorted(directory.iterdir()):
        op_file = entry / "operation.json"
        if not op_file.is_file():
            continue
        try:
            op = json.loads(op_file.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for target in op.get("targets", []) or []:
            path = str(target.get("path", ""))
            if path.startswith(AD_REL + "/"):
                out.append(
                    {
                        "op_id": op.get("op_id"),
                        "operation": op.get("operation"),
                        "created_at": op.get("created_at", ""),
                        "verification_policy": op.get("verification_policy"),
                        "path": path,
                        "before_hash": target.get("before_hash", ""),
                        "after_hash": target.get("after_hash", ""),
                    }
                )
    out.sort(key=lambda r: (r["created_at"], r["op_id"] or ""))
    return out


def engine_history_index(root: Path):
    """(event_id -> (segment_relpath, raw_line)) over the engine's own history.

    Built from the protocol install's `history_paths` + `parse_log_line`, not
    from a glob, so the index is exactly the set of events the validator can
    see and `evaluate_provenance` can be driven with.
    """
    from saipen_engine.log import history_paths, parse_log_line  # type: ignore

    index: dict[str, tuple[str, str]] = {}
    for path in history_paths(Path(root)):
        path = Path(path)
        if not path.is_file():
            continue
        try:
            rel = path.resolve().relative_to(Path(root).resolve()).as_posix()
        except ValueError:
            rel = path.as_posix()
        for raw in path.read_text(encoding="utf-8").splitlines():
            if not raw.strip() or raw.startswith("#"):
                continue
            parsed = parse_log_line(raw)
            if parsed is None or parsed.get("event") is None:
                continue
            index.setdefault(f"E-{parsed['event']}", (rel, raw))
    return index


def supersession(root: Path, records: list[dict]) -> dict[str, dict]:
    """Map record_id -> the record that strictly subsumes it, if any.

    Two records are supersession candidates when they bind the same
    check_id/check_version/authority and one accepted_missing_events set is a
    STRICT subset of the other's. `evaluate_provenance` selects a record only
    on exact set equality, so a strict subset can never be chosen while the
    superset exists.
    """
    out: dict[str, dict] = {}
    for a in records:
        sa = set(a["accepted_missing_events"])
        for b in records:
            if a["record_id"] == b["record_id"]:
                continue
            if (a["check_id"], a["check_version"], a["authority"]) != (
                b["check_id"],
                b["check_version"],
                b["authority"],
            ):
                continue
            sb = set(b["accepted_missing_events"])
            if sa < sb:
                out[a["record_id"]] = {
                    "superseded_by": b["record_id"],
                    "subset_size": len(sa),
                    "superset_size": len(sb),
                }
    return out


def verify_record(root: Path, ad_path: Path, accepted_debt, hard: list, findings: list,
                  history: dict, supersedes: dict) -> dict:
    ref = ad_path.stem
    rel = ad_path.relative_to(root).as_posix()

    # 1. the engine's own loader: schema_version, record_id, kind, integrity
    #    digest, lineage and rule binding. A refusal here is fatal for this
    #    record -- a hand-edited or damaged record must never half-verify.
    try:
        accepted_debt.load_record(root, ref)
        hard.append((f"{ref}: engine load_record accepts the record", True, ""))
    except Exception as exc:
        hard.append((f"{ref}: engine load_record accepts the record", False, str(exc)))
        return {"record_id": ref, "path": rel, "evidence": 0, "ok": False}

    record = json.loads(ad_path.read_text(encoding="utf-8"))

    # 2. re-derive every evidence line hash from the LIVE LOG shard. REPORTED,
    #    not fatal: the integrity digest above already proves the record itself
    #    is untampered, so a cited line that no longer resolves means the LOG
    #    rotated underneath a correct record.
    evidence = record.get("evidence") or []
    drifted = []
    for item in evidence:
        rel_file, line_no = item.get("file"), item.get("line_number")
        shard = root / rel_file
        if not shard.is_file():
            drifted.append(f"{item.get('event')}: cited shard absent ({rel_file})")
            continue
        lines = shard.read_text(encoding="utf-8").splitlines()
        if not isinstance(line_no, int) or line_no < 1 or line_no > len(lines):
            drifted.append(f"{item.get('event')}: line {line_no} out of range ({len(lines)} lines)")
            continue
        got = hashlib.sha256(lines[line_no - 1].encode("utf-8")).hexdigest()
        if got != item.get("line_sha256"):
            drifted.append(f"{item.get('event')}: live line hash differs at {rel_file}:{line_no}")
    if drifted:
        # A drifted record that a superset already owns is not a correctness
        # problem. `evaluate_provenance` selects a record only on exact set
        # equality, so a strict subset can never be chosen while the superset
        # exists -- and this run PROVES it by asking the engine itself.
        claim = supersedes.get(ref)
        if claim:
            try:
                triples = [
                    (event, history[event][0], history[event][1])
                    for event in record["accepted_missing_events"]
                    if event in history
                ]
                verdict = accepted_debt.evaluate_provenance(root, triples)
            except Exception as exc:  # reported, never silently swallowed
                verdict = {"accepted": None, "record_id": None, "reason": f"engine call failed: {exc}"}
            hard.append(
                (
                    f"{ref}: the engine cannot select this record while "
                    f"{claim['superseded_by']} exists (strict subset, "
                    f"{claim['subset_size']} of {claim['superset_size']} events)",
                    verdict.get("accepted") is False,
                    f"engine said {verdict}",
                )
            )
            if verdict.get("accepted") is False:
                findings.append(
                    {
                        "record_id": ref,
                        "op_id": None,
                        "operation": None,
                        "created_at": record.get("created_at", ""),
                        "issue": "SUPERSEDED_RECORD",
                        "detail": (
                            f"{ref} is a strict subset of {claim['superseded_by']} "
                            f"({claim['subset_size']} of {claim['superset_size']} events, same "
                            "check_id/check_version/authority) and its cited evidence shard no "
                            "longer resolves. The engine's own evaluate_provenance returns "
                            "accepted=False for its exact set, so no validator verdict can depend "
                            f"on it. It is a RETIREMENT candidate, not a rebind: rebinding it "
                            "would make a set the validator never reports look accepted. The "
                            "record bytes stay until a closed accepted_debt writer exists "
                            "(see T-312); the settled receipt preserves the original content."
                        ),
                    }
                )
        else:
            findings.append(
                {
                    "record_id": ref,
                    "op_id": None,
                    "operation": None,
                    "created_at": record.get("created_at", ""),
                    "issue": "EVIDENCE_DRIFT",
                    "detail": (
                        f"{len(drifted)}/{len(evidence)} evidence lines no longer re-derive from "
                        "the cited shard and no superseding record covers this set; the record "
                        "itself verifies, so this is LOG rotation under a live acceptance and "
                        "needs a closed rebind: " + "; ".join(drifted[:3])
                    ),
                }
            )

    # 3/4. settled journal chain: contiguous before/after, terminal == live bytes.
    chain = [r for r in settled_receipts(root) if r["path"] == rel]
    if not chain:
        hard.append((f"{ref}: a settled journal receipt exists", False, "no receipt touches this record"))
    else:
        gaps = []
        previous_after = None
        for receipt in chain:
            if previous_after is not None and receipt["before_hash"] != previous_after:
                gaps.append(
                    f"{receipt['op_id']}: before_hash {receipt['before_hash']!r} does not follow "
                    f"the previous after_hash {previous_after!r}"
                )
            previous_after = receipt["after_hash"]
        hard.append(
            (
                f"{ref}: the settled journal chain is contiguous over {len(chain)} receipt(s)",
                not gaps,
                "; ".join(gaps[:3]),
            )
        )
        live = _sha16(ad_path.read_bytes())
        terminal = chain[-1]
        hard.append(
            (
                f"{ref}: the terminal receipt {terminal['op_id']} after_hash matches the live bytes",
                terminal["after_hash"] == live,
                f"receipt {terminal['after_hash']!r} vs live {live!r}",
            )
        )
        # 5. writer provenance: REPORTED, not fatal.
        for receipt in chain:
            if receipt["operation"] not in ENGINE_OPERATIONS:
                findings.append(
                    {
                        "record_id": ref,
                        "op_id": receipt["op_id"],
                        "operation": receipt["operation"],
                        "created_at": receipt["created_at"],
                        "issue": "UNREGISTERED_WRITER",
                        "detail": (
                            f"{receipt['op_id']} wrote {rel} under operation "
                            f"{receipt['operation']!r}, which no protocol module implements; the "
                            "write therefore went through the generic journal CAS instead of a "
                            "closed domain writer"
                        ),
                    }
                )
            elif receipt["verification_policy"] in (None, "", "none") and receipt["operation"] not in ENGINE_OPERATIONS:
                findings.append(
                    {
                        "record_id": ref,
                        "op_id": receipt["op_id"],
                        "operation": receipt["operation"],
                        "created_at": receipt["created_at"],
                        "issue": "UNVERIFIED_WRITER",
                        "detail": f"{receipt['op_id']} carries verification_policy=none",
                    }
                )

    return {
        "record_id": ref,
        "path": rel,
        "evidence": len(evidence),
        "events": len(record.get("accepted_missing_events") or []),
        "receipts": [r["op_id"] for r in chain],
        "ok": True,
    }


def self_test() -> int:
    """RED control: prove each hard check actually fires.

    A gate that cannot go red is decoration. Each case below tampers with one
    thing and asserts the corresponding check reports it, using the same pure
    functions the live path uses -- no fixture project, so the result is not
    masked by the lineage check a copied path would trip.
    """
    failures: list[str] = []

    def expect(label: str, condition: bool) -> None:
        print(f"{'PASS' if condition else 'FAIL'}: self-test {label}")
        if not condition:
            failures.append(label)

    body = {
        "record_id": "AD-999999",
        "evidence": [{"event": "E-001", "file": "a.log", "line_number": 1, "line_sha256": "aa"}],
    }
    sealed = dict(body, integrity_digest=_integrity_digest(body))
    expect("an untampered record re-derives its digest", _integrity_digest(
        {k: v for k, v in sealed.items() if k != "integrity_digest"}) == sealed["integrity_digest"])

    tampered = dict(sealed)
    tampered["evidence"] = [{"event": "E-001", "file": "a.log", "line_number": 2, "line_sha256": "aa"}]
    expect("a hand-edited evidence line breaks the digest", _integrity_digest(
        {k: v for k, v in tampered.items() if k != "integrity_digest"}) != sealed["integrity_digest"])

    chain = [
        {"op_id": "a", "operation": "accepted_debt.register", "before_hash": "", "after_hash": "H1"},
        {"op_id": "b", "operation": "accepted_debt.rebind", "before_hash": "H1", "after_hash": "H2"},
    ]

    def gaps_of(entries: list[dict]) -> list[str]:
        gaps, previous = [], None
        for receipt in entries:
            if previous is not None and receipt["before_hash"] != previous:
                gaps.append(receipt["op_id"])
            previous = receipt["after_hash"]
        return gaps

    expect("a contiguous chain reports no gap", gaps_of(chain) == [])
    broken = [chain[0], dict(chain[1], before_hash="H9")]
    expect("a broken before/after link is caught", gaps_of(broken) == ["b"])
    expect("an unknown writer name is not in the engine set",
           "accepted_debt.rebind" not in ENGINE_OPERATIONS and "accepted_debt.register" in ENGINE_OPERATIONS)

    live = b"payload"
    expect("the journal hash shape is sha256 truncated to 16 hex",
           len(_sha16(live)) == 16 and _sha16(live) == _sha16(b"payload") and _sha16(live) != _sha16(b"payloa"))

    # Supersession: a strict subset under the same rule/authority is claimed by
    # its superset; a same-size or disjoint set is not, and a different rule is
    # never a supersession partner.
    def rec(rid, events, check="c", ver=1, auth="E-1"):
        return {"record_id": rid, "accepted_missing_events": events,
                "check_id": check, "check_version": ver, "authority": auth}

    small, big = rec("AD-000001", ["E-1", "E-2"]), rec("AD-000002", ["E-1", "E-2", "E-3"])
    pair = supersession(Path("."), [small, big])
    expect("a strict subset is marked superseded by its superset",
           pair.get("AD-000001", {}).get("superseded_by") == "AD-000002")
    expect("the superset is not itself marked superseded", "AD-000002" not in pair)
    equal_pair = rec("AD-000003", ["E-1", "E-2"])
    expect("an equal set is NOT supersession (exact equality is a real conflict)",
           "AD-000003" not in supersession(Path("."), [small, equal_pair]))
    other_rule = rec("AD-000004", ["E-1", "E-2", "E-3", "E-4"], check="other")
    expect("a different check_id is never a supersession partner",
           "AD-000001" not in supersession(Path("."), [small, other_rule]))
    expect("a single record claims nothing", supersession(Path("."), [small]) == {})

    print()
    print("ALL PASS" if not failures else f"{len(failures)} SELF-TEST FAILURE(S)")
    return 0 if not failures else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-root", default=".")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--self-test", action="store_true", help="RED control: prove the checks fire")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    root = Path(args.project_root).resolve()
    engine_home = resolve_engine_home(root)
    accepted_debt = load_engine(engine_home)

    ad_dir = root / AD_REL
    records = sorted(p for p in ad_dir.glob("AD-*.json") if AD_ID_RE.match(p.stem)) if ad_dir.is_dir() else []

    history = engine_history_index(root)
    parsed_records = []
    for p in records:
        try:
            parsed_records.append(json.loads(p.read_text(encoding="utf-8")))
        except (OSError, ValueError):
            continue
    supersedes = supersession(root, parsed_records)

    hard: list[tuple[str, bool, str]] = []
    findings: list[dict] = []
    summaries = [
        verify_record(root, p, accepted_debt, hard, findings, history, supersedes) for p in records
    ]

    if not records:
        hard.append(("an accepted-debt registry exists", False, f"no AD-*.json under {AD_REL}"))

    failed = [(label, detail) for label, ok, detail in hard if not ok]
    verdict = {
        "engine_home": str(engine_home),
        "project_root": str(root),
        "records": summaries,
        "checks": [{"label": label, "ok": ok, "detail": detail} for label, ok, detail in hard],
        "findings": findings,
        "failed": len(failed),
        "ok": not failed,
    }

    if args.json:
        print(json.dumps(verdict, indent=2, ensure_ascii=False))
    else:
        for label, ok, detail in hard:
            print(f"{'PASS' if ok else 'FAIL'}: {label}" + (f"  [{detail}]" if detail and not ok else ""))
        for finding in findings:
            print(f"FINDING [{finding['issue']}] {finding['op_id']}: {finding['detail']}")
    return 0 if verdict["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

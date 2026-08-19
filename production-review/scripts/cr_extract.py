"""Extract compact CR data from the persisted ReadInternalWebsites JSON.

Usage: python3 cr_extract.py <persisted_json_path> <my_alias>

Reads the JSON dumped by ReadInternalWebsites for one or more CR detail pages
(the tool returns one entry per URL when batched) and prints a compact JSON
ARRAY of documents with just the fields /my-crs needs:

    {
      "cr_id": "CR-12345678",
      "title": "...",
      "author": "alias",
      "current_revision": 2,
      "url": "https://code.amazon.com/reviews/CR-12345678",
      "i_approved_current": true,
      "next_actions": [{"user": "alias", "action": "MERGE_CR"}, ...],
      "comments": [
        {"revision": 1, "author": "x", "body": "...", "location": "general"|"file:line",
         "fixed": false, "created_at": "..."},
        ...
      ]
    }

next_actions comes straight from CRUX's structured `actions.next_actions`
field — the authoritative "whose turn is it next" determination. Common
action values: MERGE_CR, REVIEW_CR, RESPOND_TO_COMMENTS_OR_APPROVE,
APPROVE_CR, ADDRESS_FAILED_ANALYZERS, ADDRESS_COMMENTS.

CoverlayWorker boilerplate comments are dropped (always noise).

Ported from Vincente_AI_Prompts (MIT-spirit personal config). No hardcoded
paths — portable as-is.
"""
import json
import re
import sys


def parse_location(loc):
    if not isinstance(loc, str) or not loc:
        return "general"
    if loc == "TOP" or loc.startswith("v") and ":TOP:" in loc:
        return "general"
    # Format: "v4:<package>:<file_path>::<start_line>::<end_line>:"
    m = re.match(r"^v\d+:[^:]*:([^:]+)::(\d+)::", loc)
    if m:
        return f"{m.group(1)}:{m.group(2)}"
    return loc


def main():
    if len(sys.argv) != 3:
        print("usage: cr_extract.py <json_path> <my_alias>", file=sys.stderr)
        sys.exit(2)
    path, me = sys.argv[1], sys.argv[2]

    with open(path) as f:
        raw = json.load(f)

    # ReadInternalWebsites returns [{"type": "text", "text": "<json string>"}, ...]
    # — one entry per URL when batched.
    results = []
    for entry in raw:
        text = entry.get("text", "")
        if not text:
            continue
        payload = json.loads(text)
        c = payload.get("content", {})
        if not c.get("crId"):
            continue

        rev_summary = c.get("revisionSummary", {})
        approved_by = rev_summary.get("approved_by", []) or []
        i_approved = f"USER:{me}" in approved_by

        # Pull next_actions from CRUX's structured action map. The path can
        # appear under `revisionDetails.revision.cr_revision.actions` or
        # mirrored at `revisionDetails.actions`. Try both.
        rev_details = c.get("revisionDetails", {})
        actions_block = (
            rev_details.get("revision", {}).get("cr_revision", {}).get("actions", {})
            or rev_details.get("actions", {})
        )
        # actions_block looks like {"actions": {"next_actions": [...], "completed_actions": [...]}}
        next_actions_raw = actions_block.get("actions", {}).get("next_actions", []) if actions_block else []
        next_actions = []
        for na in next_actions_raw:
            ua = na.get("user_action", {})
            user = ua.get("id", {}).get("entity_id", {}).get("id")
            action = ua.get("action")
            if user and action:
                next_actions.append({"user": user, "action": action})

        out = {
            "cr_id": c.get("crId"),
            "title": rev_summary.get("summary"),
            "author": rev_summary.get("author", {}).get("entity_id", {}).get("id"),
            "current_revision": c.get("revision"),
            "url": f"https://code.amazon.com/reviews/{c.get('crId')}",
            "i_approved_current": i_approved,
            "next_actions": next_actions,
            "comments": [],
        }

        for comment in c.get("allComments", []):
            author = comment.get("author")
            if author == "CoverlayWorker":
                continue
            out["comments"].append({
                "revision": comment.get("revision"),
                "author": author,
                "body": comment.get("content", ""),
                "location": parse_location(comment.get("location")),
                "fixed": bool(comment.get("fixed")),
                "created_at": comment.get("created_at"),
            })

        results.append(out)

    json.dump(results, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()

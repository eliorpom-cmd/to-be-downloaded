#!/usr/bin/env bash
#
# How many installed apps have taken the latest update on their own.
#
# Usage: ./scripts/adoption.sh
#
# `stats.sh` counts downloads. This counts SELF-UPDATES, which is a different
# and much narrower thing, and it can be read off one asset.
#
# The trick is the signature file. Nobody downloads a `.sig` by hand, Homebrew
# never asks for one, and neither does anyone taking the DMG. The in-app
# updater is the only thing that fetches it, because it verifies the Ed25519
# signature BEFORE unpacking anything. So:
#
#   .sig downloads ≈ apps that updated themselves
#   .zip downloads  = those, plus Homebrew, plus everyone clicking the release
#
# v1.0.0 bears this out: 162 on the zip against 5 on the sig.
#
# Each run stores a snapshot, so the next one can say what moved and over how
# long. The snapshot lives outside the repository — it is local observation,
# not part of the project.
set -euo pipefail

REPO="eliorpom-cmd/to-be-downloaded"
SNAPSHOT="${HOME}/.config/tbd-release/adoption.json"

mkdir -p "$(dirname "$SNAPSHOT")"

curl -sf "https://api.github.com/repos/${REPO}/releases" > /tmp/tbd-releases.json || {
  echo "❌ GitHub unreachable"; exit 1
}

SNAPSHOT="$SNAPSHOT" /usr/bin/python3 <<'PY'
import json, os, time

releases = json.load(open("/tmp/tbd-releases.json"))
snapshot_path = os.environ["SNAPSHOT"]

previous = {}
if os.path.exists(snapshot_path):
    previous = json.load(open(snapshot_path))

now = time.time()
counts, published = {}, {}
for release in releases:
    tag = release["tag_name"]
    published[tag] = release["published_at"][:10]
    counts[tag] = {a["name"]: a["download_count"] for a in release["assets"]}

def delta(tag, asset):
    """What moved since the last run, when there is a last run to compare to."""
    before = previous.get("counts", {}).get(tag, {}).get(asset)
    if before is None:
        return ""
    change = counts[tag][asset] - before
    return f"  (+{change})" if change > 0 else "  (=)"

latest = releases[0]["tag_name"]
version = latest.lstrip("v")
sig = f"TBD-{version}-macos.zip.sig"
zipname = f"TBD-{version}-macos.zip"

print(f"{latest}, published {published[latest]}")
print()
if sig in counts[latest]:
    print(f"  self-updates       {counts[latest][sig]:>6}{delta(latest, sig)}")
print(f"  zip downloads      {counts[latest].get(zipname, 0):>6}{delta(latest, zipname)}"
      "   (self-updates + Homebrew + the release page)")
print(f"  dmg downloads      {counts[latest].get('TBD.dmg', 0):>6}{delta(latest, 'TBD.dmg')}")

# What the previous release reached, so the new number has a size to be
# compared against rather than being a bare figure.
others = [r["tag_name"] for r in releases[1:]]
if others:
    print()
    print("  for scale:")
    for tag in others:
        v = tag.lstrip("v")
        z = counts[tag].get(f"TBD-{v}-macos.zip", 0)
        d = counts[tag].get("TBD.dmg", 0)
        s = counts[tag].get(f"TBD-{v}-macos.zip.sig", 0)
        print(f"    {tag:<8} zip {z:>5}   dmg {d:>5}   self-updates {s:>4}"
              f"   ({published[tag]})")

# The number that survives having more than one version in the wild.
#
# Three assets, three audiences. Only the updater fetches a .sig; only a human
# on the release page fetches a .dmg; the .zip is fetched by the updater, by
# Homebrew, and by anyone clicking it. So the zip downloads that no updater
# asked for, plus the dmg, are people arriving — not people upgrading.
installs = updates = 0
for tag, assets in counts.items():
    v = tag.lstrip("v")
    z = assets.get(f"TBD-{v}-macos.zip", 0)
    g = assets.get(f"TBD-{v}-macos.zip.sig", 0)
    d = assets.get("TBD.dmg", 0)
    installs += max(0, z - g) + d
    updates += g

print()
print("  since the first release:")
print(f"    arrivals           {installs:>6}   (dmg, plus the zips no updater asked for)")
print(f"    upgrades           {updates:>6}")

if "at" in previous:
    hours = (now - previous["at"]) / 3600
    print()
    print(f"  changes are since the last run, {hours:.1f} h ago")

json.dump({"at": now, "counts": counts}, open(snapshot_path, "w"))
PY

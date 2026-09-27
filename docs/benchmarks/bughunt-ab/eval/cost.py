# OpenAI API cost of the Codex calls, standard short-context prices (Sep 2026).
# Usage: LANDING_RUNS=<landing .swarm dir> BUG_RUNS=<bugbench .swarm dir> python3 cost.py
import collections
import glob
import json
import os

P = {
    "gpt-6-astra": (10, 1, 50),
    "gpt-6-sol": (2, 0.2, 10),
    "gpt-6-luna": (0.1, 0.01, 0.5),
    "gpt-5.6-sol": (4, 0.4, 20),
    "gpt-5.6-terra": (2, 0.2, 12),
    "gpt-5.6-luna": (0.2, 0.02, 1.2),
    "gpt-5.5": (5, 0.5, 30),
}


def price(model, u):
    i, c, o = P[model]
    inp, cached, out = (
        u["input_tokens"],
        u.get("cached_input_tokens", 0),
        u["output_tokens"],
    )
    return ((inp - cached) * i + cached * c + out * o) / 1e6


def amap(d):
    m = {}
    f = os.path.join(d, "anon.map")
    if os.path.exists(f):
        for l in open(f):
            p = l.rstrip("\n").split("\t")
            m[p[0]] = p[1]
    return m


runs = {
    "landing A astra solo": (
        os.environ["LANDING_RUNS"] + "/solo",
        {"astra": "gpt-6-astra"},
        "solo",
    ),
    "landing C swarm (codex part)": (
        os.environ["LANDING_RUNS"] + "/swarm",
        None,
        "all",
    ),
    "bug A astra solo": (
        os.environ["BUG_RUNS"] + "/solo",
        {"astra": "gpt-6-astra"},
        "solo",
    ),
    "bug C1 luna x16 + luna judge": (os.environ["BUG_RUNS"] + "/swarm", None, "all"),
    "bug C3 judge astra (rejudge only)": (
        os.environ["BUG_RUNS"] + "/swarm-judge-astra",
        None,
        "judge-astra",
    ),
    "bug D -m all (codex part)": (os.environ["BUG_RUNS"] + "/all", None, "all"),
}
for name, (d, fixed, kind) in runs.items():
    d = os.path.expanduser(d)
    tot = 0.0
    per = collections.Counter()
    files = []
    if kind == "solo":
        files = [(f"{d}/{k}.usage", m) for k, m in fixed.items()]
    else:
        am = amap(d)
        judge = (
            json.load(open(f"{d}/run.json")).get("judge", {}).get("model")
            if os.path.exists(f"{d}/run.json")
            else None
        )
        if kind == "judge-astra":
            judge = "gpt-6-astra"
        rounds = [] if kind == "judge-astra" else glob.glob(f"{d}/r*/a*.usage")
        for f in rounds:
            files.append((f, am[os.path.basename(f)[:-6]]))
        for f in glob.glob(f"{d}/j/*/*.usage") + glob.glob(f"{d}/final.usage"):
            files.append((f, judge))
    for f, m in files:
        if m not in P or not os.path.exists(f):
            continue
        u = json.load(open(f))["usage"]
        c = price(m, u)
        tot += c
        per[m] += c
    print(
        f"{name:38s} ${tot:7.2f}  "
        + ", ".join(f"{k} ${v:.2f}" for k, v in per.most_common())
    )

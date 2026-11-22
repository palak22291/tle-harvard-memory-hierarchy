#!/usr/bin/env python3
"""
Team TLE - Phase II (Member 4)
Cycle-by-cycle Harvard vs. Von Neumann timeline from sim/arch_comparison.vcd.

Run `make sim_arch_compare` first, then:
    python3 scripts/vcd_timeline.py            # first 30 cycles, L2_LATENCY = 0
    python3 scripts/vcd_timeline.py --cycles 60 --pair 1 --markdown

For every rising clock edge after reset it samples, for both systems:
    IF  = fetch request outstanding   (if_req, or the fetch ready pulse)
    MEM = data request outstanding    (d_req,  or the data ready pulse)
    STALL (Von Neumann only) = if_stall, fetch blocked by a data transfer
No third-party packages are needed.
"""

import argparse
import os
import sys

TB = "tb_architecture_comparison"


def parse_vcd(path, wanted):
    """Return {signal_path: [(time, value), ...]} for the wanted full paths."""
    id_to_paths, scope = {}, []
    changes = {w: [] for w in wanted}
    with open(path) as f:
        lines = iter(f)
        for line in lines:
            tok = line.split()
            if not tok:
                continue
            if tok[0] == "$scope":
                scope.append(tok[2])
            elif tok[0] == "$upscope":
                scope.pop()
            elif tok[0] == "$var":
                full = ".".join(scope + [tok[4]])
                if full in changes:
                    id_to_paths.setdefault(tok[3], []).append(full)
            elif tok[0] == "$enddefinitions":
                break
        t = 0
        for line in lines:
            line = line.strip()
            if not line:
                continue
            if line[0] == "#":
                t = int(line[1:])
            elif line[0] in "01xz" and len(line) > 1:
                for p in id_to_paths.get(line[1:], []):
                    changes[p].append((t, line[0]))
            elif line[0] == "b":
                val, ident = line[1:].split()
                for p in id_to_paths.get(ident, []):
                    changes[p].append((t, val))
    return changes


def value_at(chg, t):
    v = "x"
    for ct, cv in chg:
        if ct > t:
            break
        v = cv
    return v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vcd", default="sim/arch_comparison.vcd")
    ap.add_argument("--pair", type=int, default=0, help="0/1/2 = L2_LATENCY 0/2/4")
    ap.add_argument("--cycles", type=int, default=30)
    ap.add_argument("--markdown", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(args.vcd):
        sys.exit(f"{args.vcd} not found - run `make sim_arch_compare` first")

    base = f"{TB}.pair[{args.pair}]"
    sig = {
        "clk": f"{TB}.clk",
        "rst": f"{TB}.rst_n",
        "h_if": f"{base}.h_if_req", "h_ifr": f"{base}.h_if_rdy",
        "h_d": f"{base}.h_d_req",   "h_dr": f"{base}.h_d_rdy",
        "v_if": f"{base}.v_if_req", "v_ifr": f"{base}.v_if_rdy",
        "v_d": f"{base}.v_d_req",   "v_dr": f"{base}.v_d_rdy",
        "v_st": f"{base}.vs",
    }
    ch = parse_vcd(args.vcd, set(sig.values()))
    missing = [k for k, v in sig.items() if not ch[v]]
    if missing:
        sys.exit(f"signals not found in VCD: {missing}")

    # rising clock edges after reset release; sample 1 time unit after each edge
    clk = ch[sig["clk"]]
    edges = [t for (t, v), (_, pv) in zip(clk[1:], clk[:-1]) if v == "1" and pv == "0"]
    rst_rel = next(t for t, v in ch[sig["rst"]] if v == "1")
    edges = [t for t in edges if t > rst_rel][: args.cycles]

    def on(*keys, t):
        return any(value_at(ch[sig[k]], t) == "1" for k in keys)

    rows = []
    for n, t in enumerate(edges, start=1):
        s = t + 1
        rows.append((n,
                     "IF" if on("h_if", "h_ifr", t=s) else "",
                     "MEM" if on("h_d", "h_dr", t=s) else "",
                     "IF" if on("v_if", "v_ifr", t=s) else "",
                     "MEM" if on("v_d", "v_dr", t=s) else "",
                     "STALL" if on("v_st", t=s) else ""))

    hdr = ("Cycle", "Harvard IF", "Harvard MEM", "VN IF", "VN MEM", "VN if_stall")
    if args.markdown:
        print("| " + " | ".join(hdr) + " |")
        print("| " + " | ".join([":---"] * len(hdr)) + " |")
        for r in rows:
            print("| " + " | ".join(str(c) if c != "" else "·" for c in r) + " |")
    else:
        print("  ".join(f"{h:>11}" for h in hdr))
        for r in rows:
            print("  ".join(f"{str(c):>11}" for c in r))
        both_h = sum(1 for r in rows if r[1] and r[2])
        both_v = sum(1 for r in rows if r[3] and r[4])
        stall = sum(1 for r in rows if r[5])
        print(f"\nIn these {len(rows)} cycles: Harvard IF+MEM together = {both_h}, "
              f"Von Neumann IF+MEM pending together = {both_v} (of which stalled = {stall})")


if __name__ == "__main__":
    main()

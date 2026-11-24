#!/usr/bin/env python3
"""
Team TLE - waveform figures for the report, drawn straight from the simulation VCDs.

    make sim_all                              # writes sim/*.vcd
    python3 scripts/plot_waveforms.py         # Phase II figure: Harvard vs. Von Neumann
    python3 scripts/plot_waveforms.py --all   # also redraw the two Phase I figures into sim/phase1_redraw/

Figures (docs/figures/):
    fig_arch_comparison_waveform.png  sim/arch_comparison.vcd, L2_LATENCY = 0, first 16 cycles
    The Phase I figures (fig_dmem_read_latency.png, fig_harvard_top_dmem_access.png) are
    submitted files and are never overwritten: --all writes the redraws to sim/phase1_redraw/.

Needs matplotlib (pip install matplotlib). The VCD parser is the one in
scripts/vcd_timeline.py, so the figure and Table V come from the same data.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vcd_timeline import parse_vcd  # noqa: E402

import matplotlib  # noqa: E402
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
FIG_DIR = os.path.join(ROOT, "docs", "figures")
PS_PER_NS = 1000            # the VCDs use a 1 ps timescale

BIT_COLOR = "#1f3b6f"
BUS_COLOR = "#2e7d32"
STALL_COLOR = "#f4c7c3"

ARCH = "tb_architecture_comparison"
PAIR = f"{ARCH}.pair[0]"    # L2_LATENCY = 0

FIGURES = {
    "arch": dict(
        vcd="sim/arch_comparison.vcd",
        out="fig_arch_comparison_waveform.png",
        title="Same program, same driver: Harvard fetches during data accesses, "
              "Von Neumann stalls (make sim_arch_compare, L2_LATENCY = 0)",
        signals=[
            ("clk", f"{ARCH}.clk"),
            ("H  if_req", f"{PAIR}.h_if_req"),
            ("H  if_ready", f"{PAIR}.h_if_rdy"),
            ("H  d_req", f"{PAIR}.h_d_req"),
            ("H  d_ready", f"{PAIR}.h_d_rdy"),
            ("VN if_req", f"{PAIR}.v_if_req"),
            ("VN if_ready", f"{PAIR}.v_if_rdy"),
            ("VN d_req", f"{PAIR}.v_d_req"),
            ("VN d_ready", f"{PAIR}.v_d_rdy"),
            ("VN if_stall", f"{PAIR}.vs"),
        ],
        reset=f"{ARCH}.rst_n",
        cycles=16,           # the same 16 clocks as Table V
        shade=f"{PAIR}.vs",
        phase1=False,
    ),
    "dmem": dict(
        vcd="sim/dmem.vcd",
        out="fig_dmem_read_latency.png",
        title="data_memory: write, then read with 1-clock synchronous latency (make sim_dmem)",
        signals=[(n, f"tb_dmem.{n}") for n in
                 ["clk", "rst_n", "dmem_en", "dmem_we", "d_be", "d_addr", "d_wdata", "d_ready", "d_rdata"]],
        window_ns=(0, 120),
        phase1=True,
    ),
    "harvard_top": dict(
        vcd="sim/harvard_top.vcd",
        out="fig_harvard_top_dmem_access.png",
        title="harvard_top: IMEM stays enabled while DMEM is written and read (make sim_harvard_top)",
        signals=[
            ("clk", "tb_harvard_top.clk"), ("stall", "tb_harvard_top.u_top.stall"),
            ("pc_out", "tb_harvard_top.pc_out"), ("imem_en", "tb_harvard_top.imem_en"),
            ("i_ready", "tb_harvard_top.i_ready"), ("req", "tb_harvard_top.req"),
            ("we", "tb_harvard_top.we"), ("d_addr", "tb_harvard_top.d_addr"),
            ("d_wdata", "tb_harvard_top.d_wdata"), ("state", "tb_harvard_top.u_top.u_rwc.state"),
            ("dmem_en", "tb_harvard_top.u_top.dmem_en"), ("dmem_ready", "tb_harvard_top.u_top.dmem_ready"),
            ("d_ready", "tb_harvard_top.d_ready"), ("d_rdata", "tb_harvard_top.d_rdata"),
        ],
        window_ns=(40, 160),
        phase1=True,
    ),
}


def rising_edges(clk):
    return [t for (t, v), (_, pv) in zip(clk[1:], clk[:-1]) if v == "1" and pv == "0"]


def segments(chg, t0, t1):
    """[(start, end, value)] covering [t0, t1]."""
    out, cur = [], "x"
    for t, v in chg:
        if t <= t0:
            cur = v
    start = t0
    for t, v in chg:
        if t0 < t < t1:
            out.append((start, t, cur))
            start, cur = t, v
    out.append((start, t1, cur))
    return out


def bus_text(v):
    if any(c in v for c in "xz"):
        return v[:1]
    return format(int(v, 2), "X")


def draw(cfg):
    vcd = os.path.join(ROOT, cfg["vcd"])
    if not os.path.exists(vcd):
        sys.exit(f"{cfg['vcd']} not found - run `make sim_all` first")
    wanted = {p for _, p in cfg["signals"]}
    for key in ("reset", "shade"):
        if cfg.get(key):
            wanted.add(cfg[key])
    ch = parse_vcd(vcd, wanted)
    missing = [p for p in wanted if not ch[p]]
    if missing:
        sys.exit(f"signals not found in {cfg['vcd']}: {missing}")

    clk = ch[cfg["signals"][0][1]]
    if "cycles" in cfg:
        rst_rel = next(t for t, v in ch[cfg["reset"]] if v == "1")
        edges = [t for t in rising_edges(clk) if t > rst_rel]
        period = edges[1] - edges[0]
        t0 = edges[0] - period // 2
        t1 = edges[cfg["cycles"]] - period // 2
    else:
        t0, t1 = (x * PS_PER_NS for x in cfg["window_ns"])
        edges, period = [], None

    sigs = cfg["signals"]
    fig, ax = plt.subplots(figsize=(13, 0.62 * len(sigs) + 1.4), dpi=150)
    ns = lambda t: t / PS_PER_NS  # noqa: E731

    if cfg.get("shade"):
        for s, e, v in segments(ch[cfg["shade"]], t0, t1):
            if v == "1":
                ax.axvspan(ns(s), ns(e), color=STALL_COLOR, alpha=0.6, lw=0, zorder=0)

    for row, (label, path) in enumerate(sigs):
        y = len(sigs) - 1 - row
        segs = segments(ch[path], t0, t1)
        is_bus = any(len(v) > 1 for _, v in ch[path])
        if is_bus:
            for s, e, v in segs:
                ax.plot([ns(s), ns(e)], [y + 0.15, y + 0.15], color=BUS_COLOR, lw=1)
                ax.plot([ns(s), ns(e)], [y + 0.75, y + 0.75], color=BUS_COLOR, lw=1)
                ax.plot([ns(s), ns(s)], [y + 0.15, y + 0.75], color=BUS_COLOR, lw=1)
                ax.text(ns((s + e) / 2), y + 0.45, bus_text(v), ha="center", va="center",
                        fontsize=7, family="monospace")
        else:
            xs, ys = [], []
            for s, e, v in segs:
                lvl = y + (0.75 if v == "1" else 0.15)
                xs += [ns(s), ns(e)]
                ys += [lvl, lvl]
            ax.plot(xs, ys, color=BIT_COLOR, lw=1.4, drawstyle="steps-post")
        ax.text(ns(t0) - (ns(t1) - ns(t0)) * 0.01, y + 0.45, label, ha="right", va="center",
                fontsize=9, family="monospace")

    if edges:
        for n, t in enumerate(edges[: cfg["cycles"]], start=1):
            ax.axvline(ns(t), color="#bbbbbb", lw=0.5, zorder=0)
            ax.text(ns(t) + ns(period) / 2, len(sigs) + 0.05, str(n), ha="center", va="bottom", fontsize=7)
        ax.text(ns(t0), len(sigs) + 0.05, "cycle", ha="right", va="bottom", fontsize=7)
    else:
        for t in range(int(ns(t0)), int(ns(t1)) + 1, 20):
            ax.axvline(t, color="#dddddd", lw=0.5, zorder=0)

    ax.set_xlim(ns(t0), ns(t1))
    ax.set_ylim(-0.1, len(sigs) + 0.5)
    ax.set_yticks([])
    for side in ("left", "right", "top"):
        ax.spines[side].set_visible(False)
    ax.set_xlabel("time (ns)")
    ax.set_title(cfg["title"], fontsize=10)
    fig.tight_layout()
    out_dir = os.path.join(ROOT, "sim", "phase1_redraw") if cfg["phase1"] else FIG_DIR
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, cfg["out"])
    fig.savefig(out)
    plt.close(fig)
    print(f"wrote {os.path.relpath(out, ROOT)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="also redraw the Phase I figures")
    args = ap.parse_args()
    os.makedirs(FIG_DIR, exist_ok=True)
    for cfg in FIGURES.values():
        if cfg["phase1"] and not args.all:
            continue
        draw(cfg)


if __name__ == "__main__":
    main()

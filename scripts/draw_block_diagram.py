#!/usr/bin/env python3
"""
Team TLE - system block diagram for the report (docs/figures/fig_block_diagram.png).

    python3 scripts/draw_block_diagram.py

(a) Harvard hierarchy as built in rtl/harvard/harvard_cpu_top.v
(b) Von Neumann baseline as built in rtl/von_neumann/von_neumann_top.v
Both are driven by the same rtl/common/simple_cpu_driver.v. Needs matplotlib.
"""

import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import FancyBboxPatch  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "docs", "figures", "fig_block_diagram.png")

CPU, INSTR, DATA, SHARED = "#dfe7f5", "#e3f1e3", "#fdf0d8", "#f6dede"


def box(ax, x, y, w, h, title, body, color):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.08",
                                fc=color, ec="#333333", lw=1.1))
    ax.text(x + w / 2, y + h - 0.2, title, ha="center", va="top", fontsize=9.5, weight="bold",
            linespacing=1.15)
    body_top = y + h - 0.2 - 0.36 * (title.count("\n") + 1) - 0.12
    ax.text(x + w / 2, body_top, body, ha="center", va="top", fontsize=7.4, linespacing=1.35)


def arrow(ax, x0, y0, x1, y1, label="", above=True, two_way=False):
    style = "<|-|>" if two_way else "-|>"
    ax.annotate("", xy=(x1, y1), xytext=(x0, y0),
                arrowprops=dict(arrowstyle=style, lw=1.1, color="#333333", shrinkA=0, shrinkB=0))
    if label:
        ax.text((x0 + x1) / 2, (y0 + y1) / 2 + (0.1 if above else -0.1), label, ha="center",
                va="bottom" if above else "top", fontsize=7, family="monospace", linespacing=1.2)


def harvard(ax):
    ax.set_title("(a) Harvard hierarchy  (harvard_cpu_top.v)", fontsize=10.5, weight="bold")
    ax.text(5.6, 6.3, "separate instruction bus and data bus: a fetch and a data access can run in the same clock",
            ha="center", fontsize=8, style="italic")
    box(ax, 0.1, 1.9, 2.3, 2.9, "CPU driver", "simple_cpu_driver.v\nLOAD / STORE /\nALU / NOP\n"
        "two-stage, 1-entry\ninstruction buffer", CPU)
    box(ax, 4.5, 4.4, 2.6, 1.5, "Instruction memory", "instruction_memory.v\n256 x 32 ROM\n($readmemh)", INSTR)
    box(ax, 4.5, 1.1, 2.6, 2.6, "Address decoder\n+ R/W control", "address_decoder.v\n(bitmask decode)\n"
        "rw_control.v\nIDLE / ACTIVE / WAIT", DATA)
    box(ax, 8.7, 3.0, 2.2, 1.6, "Local DMEM", "data_memory.v\n256 x 32, d_be[3:0]\n0x000 - 0x3FF", DATA)
    box(ax, 8.7, 0.6, 2.2, 1.6, "Shared L2", "shared_l2_memory.v\n512 x 32, L2_LATENCY\n0x800 - 0xFFF", DATA)
    # instruction bus (own port)
    arrow(ax, 2.4, 4.6, 4.5, 4.6, "i_addr, if_req")
    arrow(ax, 4.5, 4.2, 2.4, 4.2, "i_rdata, if_ready", above=False)
    # data bus (separate port)
    arrow(ax, 2.4, 2.9, 4.5, 2.9, "d_addr, d_wdata,\nd_be, req, we")
    arrow(ax, 4.5, 2.3, 2.4, 2.3, "d_rdata, d_ready,\ninvalid_addr_err", above=False)
    arrow(ax, 7.1, 3.3, 8.7, 3.8, "dmem_en/we", two_way=True)
    arrow(ax, 7.1, 1.6, 8.7, 1.4, "l2_en/we", above=False, two_way=True)


def von_neumann(ax):
    ax.set_title("(b) Von Neumann baseline  (von_neumann_top.v)", fontsize=10.5, weight="bold")
    ax.text(5.6, 6.3, "one shared bus: a fetch waits while a data transfer is on the bus (structural hazard)",
            ha="center", fontsize=8, style="italic")
    box(ax, 0.1, 1.9, 2.3, 2.9, "CPU driver", "simple_cpu_driver.v\n(same module and\nprogram as in (a))", CPU)
    box(ax, 4.2, 1.9, 2.4, 2.9, "Bus arbiter", "bus_arbiter.v\none shared port\ndata has priority\n"
        "if_stall = fetch\nblocked by data", SHARED)
    box(ax, 8.2, 1.5, 2.7, 3.7, "Unified memory", "unified_memory.v\n2048 x 32, one port\n"
        "data: 0x000 - 0x3FF\nand 0x800 - 0xFFF\ncode: 0x1000 - 0x13FF\nL2-window wait states", SHARED)
    arrow(ax, 2.4, 4.2, 4.2, 4.2, "fetch request")
    arrow(ax, 2.4, 2.6, 4.2, 2.6, "data request")
    arrow(ax, 6.6, 3.35, 8.2, 3.35, "one shared\naddr/data bus", two_way=True)


def main():
    fig, axes = plt.subplots(1, 2, figsize=(15, 4.9), dpi=150)
    for ax in axes:
        ax.set_xlim(0, 11.1)
        ax.set_ylim(0.3, 6.6)
        ax.axis("off")
    harvard(axes[0])
    von_neumann(axes[1])
    fig.tight_layout()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    fig.savefig(OUT)
    print(f"wrote {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()

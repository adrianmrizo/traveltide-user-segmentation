"""Generate the README figures from the project datasets.

Renders each figure twice -- light and dark -- so the README can serve the
matching variant through a <picture> element on GitHub.

Usage (from the repository root):
    python scripts/make_figures.py
"""

from pathlib import Path

import matplotlib
matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.decomposition import PCA
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler

ROOT = Path(__file__).resolve().parents[1]
PROCESSED = ROOT / "data" / "processed"
OUT = ROOT / "reports" / "figures"

RANDOM_STATE = 42
N_COMPONENTS = 14   # cumulative explained variance passes 90% here
K = 3               # cluster count carried over from the elbow analysis
REFERENCE_DATE = pd.Timestamp("2023-07-31")  # last day covered by the dataset
CUTOFF = 5                                   # chosen minimum session count
ML_SEGMENTS = ["Premium Long-Haul", "High Friction Family", "Low Activity Leisure"]

# --- theme -----------------------------------------------------------------
# Validated categorical slots 1-3; see reports/figures/README.md.
THEMES = {
    "light": dict(
        surface="#fcfcfb", ink="#0b0b0b", ink2="#52514e", muted="#898781",
        grid="#e1e0d9", axis="#c3c2b7",
        series=("#2a78d6", "#eb6834", "#1baf7a"),
    ),
    "dark": dict(
        surface="#1a1a19", ink="#ffffff", ink2="#c3c2b7", muted="#898781",
        grid="#2c2c2a", axis="#383835",
        series=("#3987e5", "#d95926", "#199e70"),
    ),
}

plt.rcParams.update({
    "font.family": "sans-serif",
    "font.sans-serif": ["Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"],
    "figure.dpi": 160,
    "savefig.dpi": 160,
    "axes.titlesize": 13,
    "axes.titleweight": "semibold",
    "axes.labelsize": 10,
    "xtick.labelsize": 9,
    "ytick.labelsize": 9,
    "legend.fontsize": 9,
})


def style_axes(ax, t, *, grid_axis="y"):
    """Recessive grid and axes: the data should be the only loud thing."""
    ax.set_facecolor(t["surface"])
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(t["axis"])
        ax.spines[side].set_linewidth(0.8)
    ax.tick_params(colors=t["muted"], length=3, width=0.8)
    ax.xaxis.label.set_color(t["ink2"])
    ax.yaxis.label.set_color(t["ink2"])
    if grid_axis:
        ax.grid(axis=grid_axis, color=t["grid"], linewidth=0.8, zorder=0)
        ax.set_axisbelow(True)


def finish(fig, path, t):
    fig.patch.set_facecolor(t["surface"])
    fig.savefig(path, facecolor=t["surface"], bbox_inches="tight", pad_inches=0.3)
    plt.close(fig)
    print(f"  wrote {path.relative_to(ROOT)}")


def cap_radius(ax, linewidth_pt):
    """Round-cap overshoot, in x data units, for a bar drawn as a capped line."""
    fig = ax.figure
    px = linewidth_pt / 2 * fig.dpi / 72
    x0, x1 = ax.get_xlim()
    width_px = ax.get_window_extent().width
    return px * (x1 - x0) / width_px


def rounded_barh(ax, y, value, color, *, thickness=13, z=3):
    """Horizontal bar with a 4px-rounded data end, square at the baseline.

    Drawn as a round-capped line shortened by the cap radius, so the right
    edge lands exactly on `value`; the left cap is clipped away at x=0.
    """
    r = cap_radius(ax, thickness)
    ax.plot([0, max(value - r, 0)], [y, y], color=color, linewidth=thickness,
            solid_capstyle="round", zorder=z, clip_on=True)


# ---------------------------------------------------------------------------
# Figure 1 - cohort cutoff
# ---------------------------------------------------------------------------
def fig_cohort_cutoff(mode):
    t = THEMES[mode]
    cut = pd.read_csv(PROCESSED / "cutoff_criteria_summary.csv")
    rev = pd.read_csv(PROCESSED / "cumulative_revenue_per_sessions.csv")

    # Share of users and of revenue contributed by users with >= k sessions.
    users = cut.sort_values("total_sessions", ascending=False)
    users["cum_users_pct"] = 100 * users["users"].cumsum() / users["users"].sum()
    df = (users[["total_sessions", "cum_users_pct"]]
          .merge(rev[["total_sessions", "cumulative_revenue_pct"]], on="total_sessions")
          .sort_values("total_sessions"))
    df = df[df["total_sessions"].between(1, 9)]

    fig, ax = plt.subplots(figsize=(7.2, 4.0))
    style_axes(ax, t)

    series = [
        ("Share of revenue", "cumulative_revenue_pct", t["series"][1]),
        ("Share of users", "cum_users_pct", t["series"][0]),
    ]
    for label, col, color in series:
        ax.plot(df["total_sessions"], df[col], color=color, linewidth=2,
                marker="o", markersize=5, markeredgecolor=t["surface"],
                markeredgewidth=1.5, label=label, zorder=3)

    ax.axvline(CUTOFF, color=t["muted"], linewidth=1, linestyle=(0, (4, 3)), zorder=1)

    # Direct labels on the cutoff, which is the whole point of the chart.
    row = df[df["total_sessions"] == CUTOFF].iloc[0]
    for col, color, dy in (("cumulative_revenue_pct", t["series"][1], 9),
                           ("cum_users_pct", t["series"][0], -24)):
        ax.annotate(f"{row[col]:.0f}%", (CUTOFF, row[col]),
                    textcoords="offset points", xytext=(8, dy),
                    color=color, fontsize=11, fontweight="bold", zorder=4)
    ax.annotate(f"cutoff: ≥ {CUTOFF} sessions", (CUTOFF, 100),
                textcoords="offset points", xytext=(6, -2),
                color=t["ink2"], fontsize=9, va="top")

    ax.set_xlabel("Minimum sessions per user")
    ax.set_ylabel("Share of total (%)")
    ax.set_ylim(0, 105)
    ax.set_xticks(range(1, 10))
    ax.set_title("A cutoff at 5 sessions keeps a fifth of users and a quarter of revenue",
                 color=t["ink"], loc="left", pad=14)
    leg = ax.legend(frameon=False, loc="upper right")
    for text in leg.get_texts():
        text.set_color(t["ink2"])

    finish(fig, OUT / f"cohort_cutoff_{mode}.png", t)


# ---------------------------------------------------------------------------
# Figures 2 & 3 - cluster selection and separation
# ---------------------------------------------------------------------------
def build_feature_matrix(df):
    """Rebuild the exact feature matrix the shipped segmentation clustered on.

    Mirrors notebook 02: drop the identifier and helper flags, turn the last
    session into a recency in days, coerce everything to numeric and impute
    the remaining gaps with 0 (``avg_distance_km`` is missing for hotel-only
    users, which is a real zero rather than an unknown).
    """
    out = df.copy()
    out["days_since_last_session"] = (
        REFERENCE_DATE - pd.to_datetime(out["last_session"])
    ).dt.days
    out = out.drop(columns=["user_id", "has_trips", "has_revenue",
                            "last_session", "segment_label"])
    return out.apply(pd.to_numeric, errors="coerce").fillna(0)


def cluster_diagnostics():
    """Diagnostics for the shipped pipeline: scale -> PCA(14) -> KMeans(k=3).

    The published labels are read from the dataset rather than re-fitted: a
    re-fit on a current scikit-learn reproduces 84% of them, and the figures
    have to agree with the segment sizes quoted everywhere else.
    """
    labelled = pd.read_csv(PROCESSED / "user_features_labels.csv")
    df = labelled[labelled["segment_label"].isin(ML_SEGMENTS)].reset_index(drop=True)
    X = StandardScaler().fit_transform(build_feature_matrix(df))

    # 14 components is where cumulative explained variance passes 90%.
    variance = np.cumsum(PCA(svd_solver="full").fit(X).explained_variance_ratio_)
    X_pca = PCA(n_components=N_COMPONENTS, svd_solver="full").fit_transform(X)
    print(f"  PCA({N_COMPONENTS}) explains {variance[N_COMPONENTS - 1]:.1%} of variance")

    # Silhouette on a fixed sample: exact on 157k points is needlessly slow and
    # the estimate is stable to three decimals at this size.
    rng = np.random.default_rng(RANDOM_STATE)
    sample = rng.choice(len(X), size=min(20_000, len(X)), replace=False)

    ks = range(1, 10)
    inertia, silhouette = [], []
    for k in ks:
        km = KMeans(n_clusters=k, random_state=RANDOM_STATE, n_init=10).fit(X_pca)
        inertia.append(km.inertia_)
        silhouette.append(
            np.nan if k == 1
            else silhouette_score(X_pca[sample], km.labels_[sample])
        )

    codes, names = pd.factorize(df["segment_label"])
    shipped_sil = silhouette_score(X_pca[sample], codes[sample])
    print(f"  shipped labels silhouette in {N_COMPONENTS}D: {shipped_sil:.3f}")

    # A 2-component projection is for display only; the clusters live in 14D.
    X_2d = PCA(n_components=2, svd_solver="full").fit_transform(X)

    return dict(ks=list(ks), inertia=inertia, silhouette=silhouette,
                X_2d=X_2d, labels=codes, names=dict(enumerate(names)),
                shipped_sil=shipped_sil, variance=variance, n_users=len(df),
                cohort_size=len(labelled))


def fig_k_selection(mode, d):
    t = THEMES[mode]
    # Two measures on different scales -> two panels, never two y-axes.
    fig, axes = plt.subplots(1, 2, figsize=(9.4, 3.8))

    inertia = [v / 1e6 for v in d["inertia"]]
    panels = [
        (axes[0], d["ks"], inertia, "Inertia (millions)",
         "Elbow: within-cluster inertia", t["series"][0]),
        (axes[1], d["ks"][1:], d["silhouette"][1:], "Silhouette score",
         "Silhouette by k", t["series"][1]),
    ]
    for ax, xs, values, ylabel, title, color in panels:
        style_axes(ax, t)
        ax.plot(xs, values, color=color, linewidth=2, marker="o", markersize=5,
                markeredgecolor=t["surface"], markeredgewidth=1.5, zorder=3)
        ax.axvline(K, color=t["muted"], linewidth=1, linestyle=(0, (4, 3)), zorder=1)
        ax.set_xlabel("Number of clusters (k)")
        ax.set_ylabel(ylabel)
        ax.set_xticks(d["ks"])
        ax.set_title(title, color=t["ink"], loc="left", pad=10, fontsize=11)

    axes[0].annotate(f"k = {K}", (K, inertia[K - 1]), textcoords="offset points",
                     xytext=(12, 14), color=t["ink2"], fontsize=10, fontweight="bold")
    # Honest note: the silhouette band is narrow and weak across every k.
    axes[1].set_ylim(0.09, 0.20)
    axes[1].annotate(f"{d['silhouette'][K - 1]:.2f} at k = {K}",
                     (K, d["silhouette"][K - 1]), textcoords="offset points",
                     xytext=(10, -22), color=t["ink2"], fontsize=9.5)

    fig.suptitle("k = 3 sits at the elbow; silhouette stays weak at every k",
                 color=t["ink"], x=0.012, y=1.0, ha="left",
                 fontsize=13, fontweight="semibold")
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    finish(fig, OUT / f"k_selection_{mode}.png", t)


def fig_pca_clusters(mode, d):
    """Small multiples: the three clusters overlap in 2D, so facet them.

    One panel per segment, its points in the segment colour over the rest in
    grey. Faceting is also the relief the light-mode aqua needs, since each
    panel is titled rather than relying on colour alone.
    """
    t = THEMES[mode]
    X, labels = d["X_2d"], d["labels"]
    order = sorted(d["names"], key=lambda k: -(labels == k).sum())

    rng = np.random.default_rng(RANDOM_STATE)
    shown = rng.choice(len(X), size=min(30_000, len(X)), replace=False)
    Xs, ls = X[shown], labels[shown]

    fig, axes = plt.subplots(1, 3, figsize=(10.6, 3.9), sharex=True, sharey=True)
    for ax, k in zip(axes, order):
        style_axes(ax, t, grid_axis=None)
        ax.grid(color=t["grid"], linewidth=0.8, zorder=0)
        ax.set_axisbelow(True)

        other, this = ls != k, ls == k
        ax.scatter(Xs[other, 0], Xs[other, 1], s=2, color=t["grid"],
                   alpha=0.55, linewidths=0, zorder=2, rasterized=True)
        ax.scatter(Xs[this, 0], Xs[this, 1], s=2.5, color=t["series"][k],
                   alpha=0.45, linewidths=0, zorder=3, rasterized=True)

        n = int((labels == k).sum())
        share = 100 * n / d["cohort_size"]
        ax.set_title(d["names"][k], color=t["series"][k], loc="left",
                     pad=24, fontsize=11)
        ax.annotate(f"{n:,} users · {share:.1f}% of the cohort",
                    (0.0, 1.03), xycoords="axes fraction",
                    color=t["muted"], fontsize=8.5)
        ax.set_xlabel("PC1")
    axes[0].set_ylabel("PC2")

    fig.suptitle("The segments separate on spend and engagement, not on activity",
                 color=t["ink"], x=0.012, y=1.005, ha="left",
                 fontsize=13, fontweight="semibold")
    fig.tight_layout(rect=(0, 0.02, 1, 0.94))
    fig.text(0.012, -0.02,
             f"Clustered in 14 PCA dimensions (90.7% of variance), shown on the "
             f"first two · {d['n_users']:,} users, 30k plotted · silhouette "
             f"{d['shipped_sil']:.2f}",
             color=t["muted"], fontsize=8.5, ha="left")
    finish(fig, OUT / f"pca_clusters_{mode}.png", t)


# ---------------------------------------------------------------------------
# Figure 4 - where the money is
# ---------------------------------------------------------------------------
def fig_segment_value(mode):
    t = THEMES[mode]
    df = (pd.read_csv(PROCESSED / "segment_summary.csv")
          .sort_values("revenue_share_pct"))

    fig, ax = plt.subplots(figsize=(7.6, 4.4))
    style_axes(ax, t, grid_axis="x")

    y = np.arange(len(df))
    offset = 0.19
    ax.set_xlim(0, 56)
    ax.set_ylim(-0.6, len(df) - 0.4)
    fig.canvas.draw()  # cap_radius needs a realised axes extent

    pairs = [
        ("Share of revenue", "revenue_share_pct", t["series"][1], +offset),
        ("Share of users", "users_pct", t["series"][0], -offset),
    ]
    for label, col, color, dy in pairs:
        for yi, value in zip(y, df[col]):
            rounded_barh(ax, yi + dy, value, color)
        ax.plot([], [], color=color, linewidth=6, label=label)  # legend proxy
        for yi, value in zip(y, df[col]):
            ax.annotate(f"{value:.1f}%", (value, yi + dy),
                        textcoords="offset points", xytext=(7, 0),
                        va="center", color=t["ink2"], fontsize=9)

    ax.set_yticks(y)
    ax.set_yticklabels(df["segment_label"], color=t["ink"], fontsize=10)
    ax.set_xlabel("Share of the cohort (%)")
    ax.set_title("Revenue concentrates where users do not",
                 color=t["ink"], loc="left", pad=14)
    leg = ax.legend(frameon=False, loc="lower right")
    for text in leg.get_texts():
        text.set_color(t["ink2"])

    finish(fig, OUT / f"segment_value_{mode}.png", t)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    print("Cluster diagnostics (rebuilding the feature matrix and PCA)...")
    diagnostics = cluster_diagnostics()
    for mode in ("light", "dark"):
        print(f"{mode}:")
        fig_cohort_cutoff(mode)
        fig_k_selection(mode, diagnostics)
        fig_pca_clusters(mode, diagnostics)
        fig_segment_value(mode)


if __name__ == "__main__":
    main()

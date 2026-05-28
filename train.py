#!/usr/bin/env python3
"""Online training of the Contextual Thompson Sampling agent.

Runs the agent on the synthetic JoinIn environment, updating a linear
posterior from observed rewards. The learning curve (windowed mean
reward) is written to ``results/learning_curve.csv``, the trained weights
to ``weights/cts_weights.json``, and a PNG plot is rendered if matplotlib
is importable.

Usage:
    python train.py
"""
import csv
import json
import random
from pathlib import Path

from simulations.synthetic_bandit_simulation import (
    EVENTS_PER_USER,
    NUM_USERS,
    POSTERIOR_STD,
    PRIOR_WEIGHTS,
    SLATE_SIZE,
    choose_action,
    features,
    sample_event,
    sample_user,
)

SEED = 0
LEARNING_RATE = 0.05
STD_DECAY = 0.997
MIN_STD = 0.005
WINDOW = 200


class OnlineCTS:
    """Linear Thompson Sampling with online SGD posterior update.

    Maintains a point estimate ``weights`` and a diagonal posterior
    ``stds``. On each interaction it samples a weight vector around the
    mean, scores the candidate, then takes one SGD step on squared loss
    and shrinks the per-feature standard deviation.
    """

    def __init__(self, prior_weights, prior_stds, rng):
        self.feature_names = list(prior_weights.keys())
        self.weights = dict(prior_weights)
        self.stds = dict(prior_stds)
        self.rng = rng

    def sample(self):
        return {
            name: self.weights[name] + self.rng.gauss(0.0, self.stds[name])
            for name in self.feature_names
        }

    def score(self, sampled, feats):
        return sum(feats.get(name, 0.0) * sampled[name] for name in self.feature_names)

    def update(self, feats, reward):
        pred = sum(feats.get(name, 0.0) * self.weights[name] for name in self.feature_names)
        error = reward - pred
        for name in self.feature_names:
            value = feats.get(name, 0.0)
            if value == 0.0:
                continue
            self.weights[name] += LEARNING_RATE * error * value
            self.stds[name] = max(MIN_STD, self.stds[name] * STD_DECAY)


def rank_slate(agent, user, events):
    sampled = agent.sample()
    scored = [(agent.score(sampled, features(user, event)), event) for event in events]
    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [event for _, event in scored[:SLATE_SIZE]]


def maybe_plot(curve_path, baseline_reward):
    try:
        import matplotlib.pyplot as plt
    except Exception as err:
        print(f"matplotlib unavailable ({err}); skipping PNG plot")
        return

    impressions, rewards = [], []
    with curve_path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            impressions.append(int(row["impression"]))
            rewards.append(float(row["window_avg_reward"]))

    fig, ax = plt.subplots(figsize=(6, 3.2))
    ax.plot(impressions, rewards, label="CTS (online)", color="#1f77b4")
    ax.axhline(baseline_reward, linestyle="--", color="#d62728",
               label=f"Chronological baseline ({baseline_reward:.3f})")
    ax.set_xlabel("Impressions seen")
    ax.set_ylabel(f"Mean reward (window={WINDOW})")
    ax.set_title("Online learning of Contextual Thompson Sampling")
    ax.grid(alpha=0.3)
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(curve_path.with_suffix(".png"), dpi=160)
    print(f"Wrote {curve_path.with_suffix('.png')}")


def main():
    rng = random.Random(SEED)
    random.seed(SEED)
    agent = OnlineCTS(PRIOR_WEIGHTS, POSTERIOR_STD, rng)

    project_root = Path(__file__).resolve().parent
    results_dir = project_root / "results"
    weights_dir = project_root / "weights"
    results_dir.mkdir(exist_ok=True)
    weights_dir.mkdir(exist_ok=True)

    curve_rows = []
    window_buffer = []
    impression_index = 0
    totals = {"joins": 0, "requests": 0, "passes": 0, "reward": 0.0}

    for user_index in range(NUM_USERS):
        user = sample_user(user_index)
        events = [
            sample_event((user_index * EVENTS_PER_USER) + i)
            for i in range(EVENTS_PER_USER)
        ]
        slate = rank_slate(agent, user, events)
        for event in slate:
            feats = features(user, event)
            action, reward = choose_action(user, event)
            agent.update(feats, reward)

            impression_index += 1
            totals["reward"] += reward
            if action == "join":
                totals["joins"] += 1
            elif action == "request":
                totals["requests"] += 1
            elif action == "pass":
                totals["passes"] += 1

            window_buffer.append(reward)
            if len(window_buffer) >= WINDOW:
                window_mean = sum(window_buffer) / len(window_buffer)
                curve_rows.append(
                    {"impression": impression_index, "window_avg_reward": window_mean}
                )
                window_buffer = []

    final_metrics = {
        "policy": "Contextual Thompson Sampling (online)",
        "seed": SEED,
        "impressions": impression_index,
        "join_rate": totals["joins"] / impression_index,
        "request_rate": totals["requests"] / impression_index,
        "pass_rate": totals["passes"] / impression_index,
        "avg_reward_per_impression": totals["reward"] / impression_index,
    }

    with (weights_dir / "cts_weights.json").open("w") as f:
        json.dump(
            {
                "seed": SEED,
                "weights": agent.weights,
                "stds": agent.stds,
                "metrics": final_metrics,
            },
            f,
            indent=2,
        )

    curve_path = results_dir / "learning_curve.csv"
    with curve_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["impression", "window_avg_reward"])
        writer.writeheader()
        writer.writerows(curve_rows)

    with (results_dir / "training_metrics.json").open("w") as f:
        json.dump(final_metrics, f, indent=2)

    print(json.dumps(final_metrics, indent=2))
    print(f"Wrote weights to {weights_dir / 'cts_weights.json'}")
    print(f"Wrote learning curve to {curve_path}")

    baseline_path = results_dir / "baseline_metrics.json"
    if baseline_path.exists():
        with baseline_path.open() as f:
            baseline_reward = json.load(f)["avg_reward_per_impression"]
        maybe_plot(curve_path, baseline_reward)
    else:
        print("No baseline_metrics.json found; run baseline.py first for the PNG plot.")


if __name__ == "__main__":
    main()

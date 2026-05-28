#!/usr/bin/env python3
"""Load trained CTS weights and evaluate on the synthetic environment.

Reads ``weights/cts_weights.json`` (produced by ``train.py``), freezes the
posterior, and reports impression-level metrics under the same seeded
synthetic stream used by ``baseline.py``.

Usage:
    python evaluate.py
"""
import json
import random
from pathlib import Path

from simulations.synthetic_bandit_simulation import (
    EVENTS_PER_USER,
    NUM_USERS,
    SLATE_SIZE,
    choose_action,
    features,
    sample_event,
    sample_user,
)

SEED = 0


def load_weights():
    weights_path = Path(__file__).resolve().parent / "weights" / "cts_weights.json"
    if not weights_path.exists():
        raise FileNotFoundError(
            f"{weights_path} is missing. Run `python train.py` first."
        )
    with weights_path.open() as f:
        return json.load(f)


def rank_slate(weights, stds, rng, user, events):
    sampled = {name: weights[name] + rng.gauss(0.0, stds[name]) for name in weights}
    scored = []
    for event in events:
        feats = features(user, event)
        score = sum(feats.get(name, 0.0) * sampled[name] for name in weights)
        scored.append((score, event))
    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [event for _, event in scored[:SLATE_SIZE]]


def main():
    payload = load_weights()
    weights = payload["weights"]
    stds = payload["stds"]

    random.seed(SEED)
    rng = random.Random(SEED)
    totals = {"impressions": 0, "joins": 0, "requests": 0, "passes": 0, "reward": 0.0}

    for user_index in range(NUM_USERS):
        user = sample_user(user_index)
        events = [
            sample_event((user_index * EVENTS_PER_USER) + i)
            for i in range(EVENTS_PER_USER)
        ]
        slate = rank_slate(weights, stds, rng, user, events)
        for event in slate:
            action, reward = choose_action(user, event)
            totals["impressions"] += 1
            totals["reward"] += reward
            if action == "join":
                totals["joins"] += 1
            elif action == "request":
                totals["requests"] += 1
            elif action == "pass":
                totals["passes"] += 1

    metrics = {
        "policy": "Contextual Thompson Sampling (frozen weights)",
        "seed": SEED,
        "training_seed": payload.get("seed"),
        "impressions": totals["impressions"],
        "join_rate": totals["joins"] / totals["impressions"],
        "request_rate": totals["requests"] / totals["impressions"],
        "pass_rate": totals["passes"] / totals["impressions"],
        "avg_reward_per_impression": totals["reward"] / totals["impressions"],
    }

    output_dir = Path(__file__).resolve().parent / "results"
    output_dir.mkdir(exist_ok=True)
    with (output_dir / "evaluation_metrics.json").open("w") as f:
        json.dump(metrics, f, indent=2)

    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Heuristic / baseline policy: chronological re-ranking.

Sorts the candidate slate strictly by ascending hours-until-event, the
ordering JoinIn's Firestore query produced before this project. Run on the
synthetic environment and print impression-level metrics.

Usage:
    python baseline.py
"""
import json
import random
from pathlib import Path

from simulations.synthetic_bandit_simulation import (
    EVENTS_PER_USER,
    NUM_USERS,
    SLATE_SIZE,
    choose_action,
    sample_event,
    sample_user,
)

SEED = 0


def baseline_rank(events):
    return sorted(events, key=lambda event: event.hours_until_event)


def main():
    random.seed(SEED)
    totals = {"impressions": 0, "joins": 0, "requests": 0, "passes": 0, "reward": 0.0}

    for user_index in range(NUM_USERS):
        user = sample_user(user_index)
        events = [
            sample_event((user_index * EVENTS_PER_USER) + i)
            for i in range(EVENTS_PER_USER)
        ]
        slate = baseline_rank(events)[:SLATE_SIZE]
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
        "policy": "Chronological baseline",
        "seed": SEED,
        "impressions": totals["impressions"],
        "join_rate": totals["joins"] / totals["impressions"],
        "request_rate": totals["requests"] / totals["impressions"],
        "pass_rate": totals["passes"] / totals["impressions"],
        "avg_reward_per_impression": totals["reward"] / totals["impressions"],
    }

    output_dir = Path(__file__).resolve().parent / "results"
    output_dir.mkdir(exist_ok=True)
    with (output_dir / "baseline_metrics.json").open("w") as f:
        json.dump(metrics, f, indent=2)

    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()

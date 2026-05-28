#!/usr/bin/env python3
import csv
import json
import math
import random
from dataclasses import dataclass
from pathlib import Path


SEED = 0
NUM_USERS = 1200
EVENTS_PER_USER = 30
SLATE_SIZE = 5
CATEGORIES = [
    "sports_outdoor",
    "food_drinks",
    "social_fun",
    "academic_learning",
    "arts_culture",
    "travel_adventure",
]
UNIVERSITIES = ["unimi", "unipd", "polimi", "unito"]

PRIOR_WEIGHTS = {
    "bias": 0.05,
    "same_university": 0.35,
    "free_to_join": 0.20,
    "request_to_join": 0.08,
    "starts_soon": 0.22,
    "evening_event": 0.08,
    "weekend_event": 0.10,
    "attendee_ratio": 0.18,
    "waiting_ratio": 0.12,
    "has_image": 0.06,
    "fresh_event": 0.07,
    "category_profile_match": 0.16,
    "report_penalty": -0.40,
}

POSTERIOR_STD = {
    "bias": 0.02,
    "same_university": 0.08,
    "free_to_join": 0.06,
    "request_to_join": 0.05,
    "starts_soon": 0.07,
    "evening_event": 0.05,
    "weekend_event": 0.05,
    "attendee_ratio": 0.08,
    "waiting_ratio": 0.07,
    "has_image": 0.03,
    "fresh_event": 0.05,
    "category_profile_match": 0.08,
    "report_penalty": 0.10,
}

TRUE_WEIGHTS = {
    "bias": -1.25,
    "same_university": 0.75,
    "free_to_join": 0.45,
    "request_to_join": 0.18,
    "starts_soon": 0.55,
    "evening_event": 0.18,
    "weekend_event": 0.25,
    "attendee_ratio": 0.30,
    "waiting_ratio": 0.16,
    "has_image": 0.12,
    "fresh_event": 0.10,
    "category_profile_match": 0.85,
    "report_penalty": -1.15,
}


@dataclass
class User:
    uid: str
    university: str
    preferred_category: str


@dataclass
class Event:
    event_id: str
    university: str
    category: str
    event_type: str
    hours_until_event: float
    hour_of_day: int
    weekday: int
    attendee_ratio: float
    waiting_ratio: float
    has_image: float
    fresh_event: float
    report_penalty: float


def sigmoid(value):
    return 1.0 / (1.0 + math.exp(-value))


def dot(features, weights):
    return sum(features[name] * weights.get(name, 0.0) for name in features)


def sample_user(index):
    return User(
        uid=f"user_{index}",
        university=random.choice(UNIVERSITIES),
        preferred_category=random.choice(CATEGORIES),
    )


def sample_event(index):
    max_attendees = random.randint(4, 30)
    attendees = random.randint(0, max_attendees - 1)
    waitings = random.randint(0, max(1, max_attendees - attendees))
    return Event(
        event_id=f"event_{index}",
        university=random.choice(UNIVERSITIES),
        category=random.choice(CATEGORIES),
        event_type="freeToJoin" if random.random() < 0.68 else "requestToJoin",
        hours_until_event=random.uniform(2.0, 168.0),
        hour_of_day=random.randint(8, 23),
        weekday=random.randint(1, 7),
        attendee_ratio=attendees / max_attendees,
        waiting_ratio=waitings / max_attendees,
        has_image=1.0 if random.random() < 0.86 else 0.0,
        fresh_event=max(0.0, 1.0 - random.expovariate(1.7)),
        report_penalty=min(1.0, random.expovariate(7.0) / 5.0),
    )


def features(user, event):
    return {
        "bias": 1.0,
        "same_university": 1.0 if user.university == event.university else 0.0,
        "free_to_join": 1.0 if event.event_type == "freeToJoin" else 0.0,
        "request_to_join": 1.0 if event.event_type == "requestToJoin" else 0.0,
        "starts_soon": max(0.0, min(1.0, 1.0 - event.hours_until_event / 168.0)),
        "evening_event": 1.0 if event.hour_of_day >= 18 else 0.0,
        "weekend_event": 1.0 if event.weekday in (6, 7) else 0.0,
        "attendee_ratio": event.attendee_ratio,
        "waiting_ratio": event.waiting_ratio,
        "has_image": event.has_image,
        "fresh_event": event.fresh_event,
        "category_profile_match": 1.0 if user.preferred_category == event.category else 0.0,
        "report_penalty": event.report_penalty,
    }


def baseline_rank(events):
    return sorted(events, key=lambda event: event.hours_until_event)


def thompson_rank(user, events):
    sampled_weights = {
        name: PRIOR_WEIGHTS[name] + random.gauss(0.0, POSTERIOR_STD.get(name, 0.0))
        for name in PRIOR_WEIGHTS
    }
    return sorted(
        events,
        key=lambda event: dot(features(user, event), sampled_weights),
        reverse=True,
    )


def choose_action(user, event):
    utility = dot(features(user, event), TRUE_WEIGHTS)
    join_probability = sigmoid(utility)
    request_probability = sigmoid(utility - 0.35)
    maybe_probability = sigmoid(utility - 1.05)

    draw = random.random()
    if event.event_type == "freeToJoin" and draw < join_probability:
        return "join", 1.0
    if event.event_type == "requestToJoin" and draw < request_probability:
        return "request", 0.7
    if draw < maybe_probability:
        return "maybe", 0.3
    return "pass", -0.1


def run_policy(policy_name, ranker):
    rows = []
    totals = {
        "impressions": 0,
        "joins": 0,
        "requests": 0,
        "passes": 0,
        "reward": 0.0,
    }

    for user_index in range(NUM_USERS):
        user = sample_user(user_index)
        events = [sample_event((user_index * EVENTS_PER_USER) + i) for i in range(EVENTS_PER_USER)]
        ranked_events = ranker(user, events)[:SLATE_SIZE]

        for rank, event in enumerate(ranked_events):
            action, reward = choose_action(user, event)
            totals["impressions"] += 1
            totals["reward"] += reward
            if action == "join":
                totals["joins"] += 1
            elif action == "request":
                totals["requests"] += 1
            elif action == "pass":
                totals["passes"] += 1

            rows.append(
                {
                    "policy": policy_name,
                    "user_id": user.uid,
                    "event_id": event.event_id,
                    "rank": rank,
                    "action": action,
                    "reward": reward,
                    "university_match": features(user, event)["same_university"],
                    "category_match": features(user, event)["category_profile_match"],
                }
            )

    metrics = {
        "policy": policy_name,
        "impressions": totals["impressions"],
        "join_rate": totals["joins"] / totals["impressions"],
        "request_rate": totals["requests"] / totals["impressions"],
        "pass_rate": totals["passes"] / totals["impressions"],
        "avg_reward_per_impression": totals["reward"] / totals["impressions"],
    }
    return metrics, rows


def main():
    random.seed(SEED)
    baseline_metrics, baseline_rows = run_policy(
        "Chronological baseline",
        lambda user, events: baseline_rank(events),
    )

    random.seed(SEED)
    thompson_metrics, thompson_rows = run_policy("Contextual Thompson Sampling", thompson_rank)

    output_dir = Path(__file__).resolve().parents[1] / "results"
    output_dir.mkdir(exist_ok=True)

    metrics = [baseline_metrics, thompson_metrics]
    with (output_dir / "synthetic_metrics.json").open("w") as f:
        json.dump(metrics, f, indent=2)

    with (output_dir / "synthetic_interactions.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list((baseline_rows + thompson_rows)[0].keys()))
        writer.writeheader()
        writer.writerows(baseline_rows + thompson_rows)

    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()

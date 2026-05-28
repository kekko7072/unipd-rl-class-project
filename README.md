# UNIPD RL Class Project

Final project deliverable for Marco Carraro and Francesco Vezzani.

Main report:
- `main.tex`
- `main.bib`
- ICML/algorithm style files already included in this folder

Implementation evidence:
- `code/event_recommendation_service.dart`: JoinIn feature extraction, reward mapping, no-op remote logging hooks, and use of `dart_rl`.
- `code/home_page.dart`: feed integration, re-ranking after Firebase candidate retrieval, and user-action reward hooks.
- `code/pubspec.yaml`: dependency declaration for the published `dart_rl` package.
- `code/dart_rl_contextual_thompson_sampling.dart`: reusable library code published in `dart_rl` 1.0.0.

Synthetic evaluation:
- `simulations/synthetic_bandit_simulation.py`: local simulator that generates synthetic users/events and compares chronological ranking with Contextual Thompson Sampling.
- `results/synthetic_metrics.json`: generated aggregate results.
- `results/synthetic_interactions.csv`: generated synthetic interaction log.

Run the simulation:

```bash
python3 simulations/synthetic_bandit_simulation.py
```
# unipd-rl-class-project

# UNIPD RL Class Project

Final project deliverable for Marco Carraro and Francesco Vezzani.

## Report

- `main.tex`, `main.bib` (use the included ICML 2021 style files)
- Build with `make` (`pdflatex` + `bibtex`)

## Python entry points (specification requirement, seed=0)

| File | Purpose |
| --- | --- |
| `baseline.py` | Heuristic / baseline policy: chronological re-ranking; writes `results/baseline_metrics.json`. |
| `train.py` | Trains the online Contextual Thompson Sampling agent on the synthetic environment; writes `weights/cts_weights.json` and `results/learning_curve.csv`. |
| `evaluate.py` | Loads the trained weights and replays the seeded stream; writes `results/evaluation_metrics.json`. |

Run end-to-end:

```bash
python baseline.py
python train.py
python evaluate.py
```

## Implementation evidence (Flutter / Dart)

- `code/event_recommendation_service.dart`: feature extraction, reward mapping, no-op remote logging hooks, and use of `dart_rl`.
- `code/home_page.dart`: feed integration, re-ranking after Firebase candidate retrieval, and user-action reward hooks.
- `code/pubspec.yaml`: dependency declaration for the published `dart_rl` package.
- `code/dart_rl/`: copy of the reusable library published as `dart_rl` 1.0.0 on pub.dev.

## Synthetic environment

- `simulations/synthetic_bandit_simulation.py`: shared simulator (users, events, ground-truth utility, reward shaping). Imported by the entry-point scripts.

## Generated artifacts

- `weights/cts_weights.json`: posterior mean and per-feature standard deviation after training.
- `results/baseline_metrics.json`, `results/evaluation_metrics.json`, `results/training_metrics.json`: per-policy aggregate metrics.
- `results/learning_curve.csv`: windowed mean reward over training, plotted in Section 7 of the report.
- `results/synthetic_metrics.json`, `results/synthetic_interactions.csv`: aggregate output of the legacy two-policy comparison script.

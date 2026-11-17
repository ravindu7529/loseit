# LoseIt

A mobile app that recommends Sri Lankan recipes to people trying to lose
weight. The user enters their profile; the app derives a daily calorie
target from the Mifflin-St Jeor equation and ranks a 300-recipe Sri
Lankan dataset with a trained neural network.

```
┌──────────────────────┐    POST /recommend     ┌────────────────────────┐
│  Flutter app         │ ─────────────────────▶ │  FastAPI backend       │
│  (Android / web)     │ ◀───────────────────── │                        │
│                      │    ranked recipe IDs   │  loads:                │
│  • profile + plan    │                        │  • trained MLP         │
│  • recommendations   │  if unreachable, falls  │  • recipes.json        │
│  • recipe details    │  back to LOCAL          └────────────────────────┘
│  • progress tracking │  rule-based scoring                 ▲
│  • AI assistant      │  (bundled asset, works        trained on
│  • recipes.json      │   fully offline)                    │
│    bundled as asset  │                        ┌────────────────────────┐
└──────────────────────┘                        │  Training pipeline     │
                                                │  (offline, run once)   │
                                                │  528,801 synthetic     │
                                                │  (user, recipe) pairs  │
                                                └────────────────────────┘
```

---

## Quick start

### 1. Backend (trained model + API)

```bash
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# Optional - the dataset and trained model are already committed.
# Re-run only if you want to reproduce them from scratch:
.venv/bin/python generate_recipes.py    # -> data/recipes.json (300 recipes)
.venv/bin/python generate_dataset.py    # -> outputs/training_dataset.csv
.venv/bin/python train.py               # -> outputs/*.png, metrics.json, model

# Serve the trained model
.venv/bin/python -m uvicorn serve:app --port 8000 --host 0.0.0.0
```

Verify:

```bash
curl http://127.0.0.1:8000/health
curl -X POST http://127.0.0.1:8000/recommend \
  -H "Content-Type: application/json" \
  -d '{"age":28,"gender":"Female","height_cm":162,"weight_kg":78,
       "activity_level":"Light","dietary_pref":"Vegetarian",
       "spice_pref":"Medium","top_n":5}'
```

### 2. Mobile app

```bash
cd mobile
flutter pub get

flutter run -d chrome     # web
flutter run -d <device>   # Android emulator or device
```

The app works **with the backend stopped** — it falls back to on-device
rule-based scoring and says so in the UI. Start it with the backend
running to see the trained model path (the card badge reads `AI PICK`
rather than `OFFLINE`).

> On an Android emulator the app reaches the host machine at
> `10.0.2.2:8000` automatically. The URL is editable in
> **Profile → Backend & assistant settings** if you serve it elsewhere.

### 3. Tests

```bash
cd mobile
flutter analyze     # 0 issues
flutter test        # 52 tests
```

---

## Results (Chapter 6 — baseline comparison)

Six algorithms trained and evaluated on an identical, **user-level**
train/test split (120,000 train rows from 1,600 users; 30,000 test rows
from 400 held-out users, drawn from the full 528,801-pair dataset).

| Model | MAE ↓ | RMSE ↓ | R² ↑ |
|---|---|---|---|
| Rule-based baseline (not trained) | 7.894 | 9.658 | 0.675 |
| Linear Regression | 6.281 | 8.093 | 0.772 |
| Random Forest | 4.497 | 5.713 | 0.886 |
| k-Nearest Neighbors | 4.019 | 5.061 | 0.911 |
| Gradient Boosting | 3.925 | 4.920 | 0.916 |
| **Neural Network (MLP)** | **3.209** | **4.017** | **0.944** |

The MLP explains 94.4% of label variance against the rule-based
baseline's 67.5%. The progression baseline → linear → forest → boosting
→ neural network is the ablation evidence: gains come from (a) being
trained on data at all, and (b) modelling non-linear feature
interactions — most visibly the spice-preference signal the hand-written
baseline never had access to.

Plots in `backend/outputs/`: `loss_curve.png`, `model_comparison.png`,
`predicted_vs_actual.png`.

**Observable effect of the spice signal.** Holding the profile constant
and varying only spice preference changes the model's top pick:

| Dietary preference | Mild | Medium | Hot |
|---|---|---|---|
| Vegan | Tofu Kottu | Tofu Kottu | Soya Meat Kottu |
| Vegetarian | Egg Kottu | Tofu Kottu | Soya Meat Kottu |
| Non-Vegetarian | Egg Kottu | Beef Kottu | Mutton Biryani |

The rule-based baseline cannot produce this variation — it does not read
spice preference at all.

---

## Design decisions

These are deliberate and defended in the report; they should not be
"simplified" without updating it.

1. **Content-based filtering, not collaborative filtering.** The app has
   no users yet, so there is no interaction history to learn from — the
   cold-start problem. Recommendations match recipe attributes to the
   user's calculated needs.
2. **Dietary compatibility is a hard filter, never learned.** Vegan /
   vegetarian / pescatarian / non-vegetarian filtering is applied
   *outside* the model, on both the server and the device. A dietary
   restriction can be health-critical, ethical or religious, so it is
   never subject to a model's prediction error. This is enforced by
   tests on both sides.
3. **Training labels are synthetic (weak supervision) and deliberately
   richer than the local fallback.** The on-device Dart fallback scores
   only calorie fit + protein. The trained model's labels also include a
   spice-match term and Gaussian noise. That gap is what gives the model
   something real to learn, and is what makes the baseline-vs-model
   comparison meaningful rather than circular. **Do not make the local
   fallback match the label function.**
4. **Train/test split is at the user level**, not the row level, so the
   same synthetic user cannot appear in both sets paired with different
   recipes.
5. **The MLP is the selected model**, chosen after empirically comparing
   six algorithms on identical data. The losing models stay in
   `train.py` — they are the evidence for the choice.

---

## Project layout

```
loseit_project/
  backend/
    data/recipes.json              300-recipe Sri Lankan dataset
    generate_recipes.py            Phase 1 - builds the dataset (seeded, deterministic)
    generate_dataset.py            Phase 2 - builds 528,801 labelled pairs
    train.py                       Phase 2 - trains + compares 6 models
    serve.py                       Phase 3 - FastAPI: /health /metrics /recipes /recommend
    outputs/                       trained model, metrics.json, plots
  mobile/
    lib/
      models/                      Recipe, UserProfile, MealLog, WeightEntry, ChatMessage
      services/
        recipe_service.dart        API call + local rule-based fallback
        storage_service.dart       shared_preferences persistence
        assistant_service.dart     grounded offline assistant + optional Claude
      state/app_state.dart         single ChangeNotifier source of truth
      screens/                     9 screens (see below)
      widgets/                     cards, pills, hand-drawn CustomPaint charts
      theme/app_theme.dart         "Lush Hearth" design system
    assets/data/recipes.json       copy of the backend dataset (works offline)
    assets/fonts/                  Plus Jakarta Sans (OFL)
    test/                          52 tests
```

**Screens:** Login, Register, Profile Setup, Dashboard, Recipes,
Recipe Details, Progress Tracking, AI Assistant, Profile/Settings, plus
a Log-Meal bottom sheet.

---

## The AI Assistant

A separate feature from the recommender. Two answer paths:

1. **Grounded offline engine (default).** Classifies the question,
   retrieves matching recipes from the bundled dataset, and answers from
   the user's own calculated targets. Every number it states is read out
   of the dataset or the BMR maths, so it cannot invent a calorie count.
   Needs no network and no API key.
2. **Claude (optional).** If an Anthropic API key is supplied, questions
   go to the Messages API with the retrieved recipes as grounding
   context. Falls back to path 1 on any error.

The key is **never hardcoded**. Supply it either at build time:

```bash
flutter run -d chrome --dart-define=ANTHROPIC_API_KEY=sk-ant-...
```

or paste it into **Profile → Backend & assistant settings**, where it is
kept on-device for the session only.

> Note for the report: calling any LLM API directly from a client app
> means the key ships with the client. For a graded prototype that is an
> accepted trade-off; a production build would proxy the call through
> the FastAPI backend so the key never leaves the server.

---

## What is verified

- `flutter analyze` — 0 issues.
- 52 tests, covering:
  - Mifflin-St Jeor BMR against hand-computed values, both sexes, the
    safe-minimum floors, and BMI category boundaries.
  - The hard dietary filter for all four preferences.
  - The local fallback score matching the backend's `baseline_score`
    formula exactly.
  - API success, HTTP failure, and unknown-ID responses — each ending in
    the correct source label.
  - The offline assistant only ever quoting calories present in the
    dataset.
  - A full end-to-end journey: guest sign-in → profile setup →
    dashboard → log a meal → recipes search → assistant → profile, plus
    persistence across a restart and data reset.
- Live API contract checked across all 12 dietary × spice combinations:
  every returned recipe ID resolves in the app's bundled asset, the
  dietary filter never leaks, and scores are strictly descending.

## Known limitations

- **No auth backend.** Login and registration validate input shape and
  store the session locally; there is no identity server. This is a
  scope boundary, not an oversight — the project's contribution is the
  recommender.
- **Recipe imagery is generated, not photographic.** The dataset ships
  no photos, and the app must work offline, so each recipe renders a
  deterministic gradient tile derived from its food group.
- **Labels are synthetic.** Once the app has real users, `train.py` can
  be re-pointed at logged interactions, moving the model from weakly
  supervised to genuinely supervised — the natural Future Work item.
- **iOS is untested.** Built and verified for Android and web; no Xcode
  was available on the build machine.

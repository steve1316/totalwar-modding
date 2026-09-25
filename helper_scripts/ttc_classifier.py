"""Classify units into TTC caps (`core`, `special,N`, `rare,N`) with a gradient-boosted model trained on existing entries.

Confidence cutoffs are tuned by 5-fold cross-validation so held-out confident picks score at least `CONFIDENT_ACCURACY_BAR` exact.
"""

import argparse
import collections
import sys
from dataclasses import dataclass
from typing import Dict, List, Tuple

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.feature_extraction import DictVectorizer
from sklearn.model_selection import StratifiedKFold, cross_val_predict

from ttc_data import UnitStats

CONFIDENT_ACCURACY_BAR = 0.95
NUMERIC_MAIN = ["multiplayer_cost", "upkeep_cost", "tier", "num_men", "melee_cp", "missile_cp", "recruitment_cost", "create_time", "point_allowance_weight", "weight"]
NUMERIC_LAND = ["bonus_hit_points", "melee_attack", "melee_defence", "morale", "charge_bonus", "accuracy"]


def _number(value: str) -> float:
    """Parse a table value as a number.

    Args:
        value (str): Raw TSV value.

    Returns:
        The number, or 0 when it is empty or not numeric.
    """
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def feature_dict(stats: UnitStats) -> Dict[str, float]:
    """Turn one unit's table rows into model features.

    Args:
        stats (UnitStats): The unit.

    Returns:
        Feature name to value. Categorical values become `name=value` indicator features.
    """
    main, land = stats.main, stats.land
    features: Dict[str, float] = {name: _number(main.get(name, "")) for name in NUMERIC_MAIN}
    features.update({name: _number(land.get(name, "")) for name in NUMERIC_LAND})
    features["num_mounts"] = _number(land.get("num_mounts", ""))
    features["cost_per_man"] = features["multiplayer_cost"] / max(features["num_men"], 1.0)
    features["is_high_threat"] = 1.0 if main.get("is_high_threat") == "true" else 0.0
    features[f"ui_group={main.get('ui_unit_group_land', '')}"] = 1.0
    features["has_land"] = 1.0 if land else 0.0
    features["has_missile"] = 1.0 if land.get("primary_missile_weapon") else 0.0
    features["is_monstrous"] = 1.0 if main.get("is_monstrous") == "true" else 0.0
    features["is_renown"] = 1.0 if main.get("is_renown") == "true" or "_ror" in stats.key else 0.0
    features[f"caste={main.get('caste', '')}"] = 1.0
    features[f"class={land.get('class', '')}"] = 1.0
    features[f"category={land.get('category', '')}"] = 1.0
    for group in stats.groups:
        features[f"group={group}"] = 1.0
    return features


def merge_rare_labels(labels: List[str], min_count: int = 5) -> List[str]:
    """Merge labels with too few examples into their category's most common label, so every class can be cross-validated.

    Args:
        labels (List[str]): Training labels.
        min_count (int): Minimum examples a label needs to be kept. Defaults to 5.

    Returns:
        The labels with rare ones replaced.
    """
    counts = collections.Counter(labels)
    best_by_category: Dict[str, str] = {}
    for label, _ in counts.most_common():
        best_by_category.setdefault(label.split(",")[0], label)
    return [label if counts[label] >= min_count else best_by_category[label.split(",")[0]] for label in labels]


@dataclass
class Prediction:
    """One classified unit."""

    # Picked label, e.g. `special,2`.
    label: str
    # Model probability of the pick.
    confidence: float
    # Second most likely label.
    runner_up: str
    # True when `confidence` reaches the cross-validated threshold.
    confident: bool


@dataclass
class Metrics:
    """Held-out accuracy of the classifier on the existing entries."""

    # Share of all entries predicted exactly (category and weight).
    exact: float
    # Share of all entries with the right category.
    category: float
    # Exact accuracy on confident picks only.
    confident: float
    # Share of entries that were confident picks.
    confident_share: float
    # Probability cutoff for a confident pick.
    threshold: float
    # Number of labeled entries evaluated.
    n: int


class Model:
    """A trained classifier plus the labeled data used for lookalikes."""

    def __init__(self, vectorizer: DictVectorizer, estimator: HistGradientBoostingClassifier, threshold: float, labeled: List[Tuple[UnitStats, str]]):
        """Store the fitted parts.

        Args:
            vectorizer (DictVectorizer): Fitted feature vectorizer.
            estimator (HistGradientBoostingClassifier): Fitted model.
            threshold (float): Confidence cutoff for confident picks.
            labeled (List[Tuple[UnitStats, str]]): Training units and their original labels.
        """
        self.vectorizer = vectorizer
        self.estimator = estimator
        self.threshold = threshold
        self.labeled = labeled
        matrix = vectorizer.transform([feature_dict(stats) for stats, _ in labeled])
        self._mean = matrix.mean(axis=0)
        self._scale = matrix.std(axis=0) + 1e-9
        self._labeled_matrix = (matrix - self._mean) / self._scale

    def predict(self, stats_list: List[UnitStats]) -> List[Prediction]:
        """Classify units.

        Args:
            stats_list (List[UnitStats]): Units to classify.

        Returns:
            One prediction per unit, in order.
        """
        if not stats_list:
            return []
        probabilities = self.estimator.predict_proba(self.vectorizer.transform([feature_dict(stats) for stats in stats_list]))
        classes = self.estimator.classes_
        predictions = []
        for row in probabilities:
            order = np.argsort(row, kind="stable")[::-1]
            runner_up = classes[order[1]] if len(order) > 1 else classes[order[0]]
            predictions.append(Prediction(str(classes[order[0]]), float(row[order[0]]), str(runner_up), float(row[order[0]]) >= self.threshold))
        return predictions

    def nearest_labeled(self, stats: UnitStats, k: int = 3) -> List[Tuple[str, str]]:
        """Find the labeled units most similar to a unit, for the review report.

        Args:
            stats (UnitStats): The unit to compare.
            k (int): Number of lookalikes. Defaults to 3.

        Returns:
            `(unit key, label)` pairs, closest first.
        """
        vector = (self.vectorizer.transform([feature_dict(stats)]) - self._mean) / self._scale
        distances = np.sqrt(((self._labeled_matrix - vector) ** 2).sum(axis=1))
        return [(self.labeled[i][0].key, self.labeled[i][1]) for i in np.argsort(distances, kind="stable")[:k]]


def _pick_threshold(confidences: np.ndarray, correct: np.ndarray) -> float:
    """Find the lowest confidence cutoff whose confident picks meet the accuracy bar.

    Args:
        confidences (np.ndarray): Held-out confidence of each pick.
        correct (np.ndarray): Whether each held-out pick was exactly right.

    Returns:
        The cutoff, or infinity when no cutoff meets the bar.
    """
    for threshold in np.unique(confidences):
        mask = confidences >= threshold
        if mask.any() and correct[mask].mean() >= CONFIDENT_ACCURACY_BAR:
            return float(threshold)
    return float("inf")


def train(labeled: List[Tuple[UnitStats, str]]) -> Tuple[Model, Metrics]:
    """Cross-validate to pick the confidence threshold, then fit the final model on every entry.

    Args:
        labeled (List[Tuple[UnitStats, str]]): Units with their existing labels.

    Returns:
        The trained model and its held-out metrics.
    """
    original = [label for _, label in labeled]
    targets = np.array(merge_rare_labels(original))
    vectorizer = DictVectorizer(sparse=False)
    matrix = vectorizer.fit_transform([feature_dict(stats) for stats, _ in labeled])
    estimator = HistGradientBoostingClassifier(random_state=0)
    folds = StratifiedKFold(n_splits=5, shuffle=True, random_state=0)
    probabilities = cross_val_predict(estimator, matrix, targets, cv=folds, method="predict_proba")
    classes = np.unique(targets)
    picks = classes[probabilities.argmax(axis=1)]
    confidences = probabilities.max(axis=1)
    truth = np.array(original)
    correct = picks == truth
    threshold = _pick_threshold(confidences, correct)
    mask = confidences >= threshold
    metrics = Metrics(
        exact=float(correct.mean()),
        category=float(np.mean([p.split(",")[0] == t.split(",")[0] for p, t in zip(picks, truth)])),
        confident=float(correct[mask].mean()) if mask.any() else 0.0,
        confident_share=float(mask.mean()),
        threshold=threshold,
        n=len(labeled),
    )
    estimator.fit(matrix, targets)
    return Model(vectorizer, estimator, threshold, labeled), metrics


def training_set(data) -> List[Tuple[UnitStats, str]]:
    """Pair every labeled unit that has table stats with its label.

    Args:
        data (ttc_data.TtcData): Loaded TTC inputs.

    Returns:
        `(stats, label)` pairs sorted by unit key.
    """
    return [(data.stats[key], label) for key, label in sorted(data.labels.items()) if key in data.stats]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Evaluate the TTC classifier on the existing entries.")
    parser.add_argument("--evaluate", action="store_true", help="Print held-out accuracy and fail if confident picks miss the bar.")
    args = parser.parse_args()
    import ttc_data

    _, result = train(training_set(ttc_data.load_all()))
    print(f"entries: {result.n}")
    print(f"held-out exact: {result.exact:.1%} | category: {result.category:.1%}")
    print(f"confident picks: {result.confident:.1%} exact on {result.confident_share:.1%} of entries (threshold {result.threshold:.3f})")
    sys.exit(0 if result.confident >= CONFIDENT_ACCURACY_BAR else 1)

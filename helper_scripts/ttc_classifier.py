"""Classify units into TTC caps (`core`, `special,N`, `rare,N`) with a gradient-boosted model trained on existing entries.

Confidence cutoffs are tuned by 5-fold cross-validation so held-out confident picks score at least `CONFIDENT_ACCURACY_BAR` exact.
"""

import argparse
import bisect
import collections
import re
import sys
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.feature_extraction import DictVectorizer
from sklearn.model_selection import StratifiedGroupKFold, StratifiedKFold, cross_val_predict

from ttc_data import UnitStats

CONFIDENT_ACCURACY_BAR = 0.95
NUMERIC_MAIN = ["multiplayer_cost", "upkeep_cost", "tier", "num_men", "melee_cp", "missile_cp", "recruitment_cost", "create_time", "point_allowance_weight", "weight"]
NUMERIC_LAND = ["bonus_hit_points", "melee_attack", "melee_defence", "morale", "charge_bonus", "accuracy"]
CATEGORY_RANK = {"core": 0, "special": 1, "rare": 2}
# Key parts that differ between variants of one unit (faction prefixes, DLC tags, mod prefixes), dropped when matching a unit to its counterpart.
STEM_NOISE = {"wh", "wh2", "wh3", "main", "dlc", "ror", "twa", "pro", "ie", "glf", "singe", "ovn", "cth", "emp"}
STEM_NOISE_PATTERN = re.compile(r"dlc\d+|twa\d+|pro\d+")
# Labeled units within this share of a unit's cost count as its priced peers.
PEER_COST_WINDOW = 0.1


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


def _stem(key: str) -> str:
    """Reduce a unit key to the words that name the unit itself, so variants from different mods share a stem.

    Args:
        key (str): Unit key.

    Returns:
        The last three meaningful words of the key.
    """
    parts = [p for p in key.lower().split("_") if p and not p.isdigit() and p not in STEM_NOISE and not STEM_NOISE_PATTERN.fullmatch(p)]
    return "_".join(parts[-3:])


def _signature(stats: UnitStats) -> Tuple[str, str, str, str]:
    """Identify a unit by its model and weapons, which clones and variants of one unit share.

    Args:
        stats (UnitStats): The unit.

    Returns:
        `(man_entity, primary_melee_weapon, primary_missile_weapon, mount)`.
    """
    land = stats.land
    return (land.get("man_entity", ""), land.get("primary_melee_weapon", ""), land.get("primary_missile_weapon", ""), land.get("mount", ""))


class PeerContext:
    """Compares a unit with its closest labeled counterpart and its same-tier peers, the way caps are priced by hand."""

    def __init__(self, stats: Dict[str, UnitStats], labels: Dict[str, str]):
        """Index every unit for counterpart and peer lookups.

        Args:
            stats (Dict[str, UnitStats]): Every vanilla and modded unit, labeled or not.
            labels (Dict[str, str]): Unit key to label for the labeled units.
        """
        self.stats = stats
        self.labels = {key: label for key, label in labels.items() if key in stats}
        self._by_signature: Dict[Tuple[str, str, str, str], List[str]] = collections.defaultdict(list)
        self._by_stem: Dict[str, List[str]] = collections.defaultdict(list)
        self._peer_costs: Dict[Tuple[str, str], List[float]] = collections.defaultdict(list)
        self._labeled_by_caste: Dict[str, List[Tuple[float, str, str]]] = collections.defaultdict(list)
        for key in sorted(self.labels):
            unit = stats[key]
            if unit.land:
                self._by_signature[_signature(unit)].append(key)
            self._by_stem[_stem(key)].append(key)
            self._labeled_by_caste[unit.main.get("caste", "")].append((_number(unit.main.get("multiplayer_cost", "")), self.labels[key], key))
        for unit in stats.values():
            self._peer_costs[(unit.main.get("caste", ""), unit.main.get("tier", ""))].append(_number(unit.main.get("multiplayer_cost", "")))
        for costs in self._peer_costs.values():
            costs.sort()

    def features(self, stats: UnitStats) -> Dict[str, float]:
        """Build the counterpart and peer features for one unit. The unit's own label is never used.

        Args:
            stats (UnitStats): The unit.

        Returns:
            Feature name to value.
        """
        key = stats.key
        cost = _number(stats.main.get("multiplayer_cost", ""))
        candidates = [c for c in self._by_signature.get(_signature(stats), []) if c != key] if stats.land else []
        candidates += [c for c in self._by_stem.get(_stem(key), []) if c != key and c not in candidates]
        features: Dict[str, float] = {"has_counterpart": 0.0}
        if candidates:
            best = min(candidates, key=lambda c: (abs(_number(self.stats[c].main.get("multiplayer_cost", "")) - cost), c))
            category, _, weight = self.labels[best].partition(",")
            features.update(
                {
                    "has_counterpart": 1.0,
                    f"counterpart={self.labels[best]}": 1.0,
                    "counterpart_rank": float(CATEGORY_RANK.get(category, 0)),
                    "counterpart_weight": _number(weight),
                    "cost_vs_counterpart": cost / max(_number(self.stats[best].main.get("multiplayer_cost", "")), 1.0),
                }
            )
        costs = self._peer_costs.get((stats.main.get("caste", ""), stats.main.get("tier", "")), [])
        features["peer_cost_percentile"] = bisect.bisect_left(costs, cost) / max(len(costs), 1)
        window = PEER_COST_WINDOW * max(cost, 1.0)
        peers = [label for peer_cost, label, other in self._labeled_by_caste.get(stats.main.get("caste", ""), []) if other != key and abs(peer_cost - cost) <= window]
        if peers:
            features["peer_mean_rank"] = float(np.mean([CATEGORY_RANK.get(label.split(",")[0], 0) for label in peers]))
            features["peer_mean_weight"] = float(np.mean([_number(label.partition(",")[2]) for label in peers]))
        return features


def feature_dict(stats: UnitStats, context: Optional[PeerContext] = None) -> Dict[str, float]:
    """Turn one unit's table rows into model features.

    Args:
        stats (UnitStats): The unit.
        context (Optional[PeerContext]): Adds counterpart and peer features when given.

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
    if context is not None:
        features.update(context.features(stats))
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
    # Exact accuracy when every label source is held out whole, i.e. for units from a mod the model has never seen. None without groups.
    unseen_mod_exact: Optional[float] = None


class Model:
    """A trained classifier plus the labeled data used for lookalikes."""

    def __init__(
        self,
        vectorizer: DictVectorizer,
        estimator: HistGradientBoostingClassifier,
        threshold: float,
        labeled: List[Tuple[UnitStats, str]],
        context: Optional[PeerContext] = None,
    ):
        """Store the fitted parts.

        Args:
            vectorizer (DictVectorizer): Fitted feature vectorizer.
            estimator (HistGradientBoostingClassifier): Fitted model.
            threshold (float): Confidence cutoff for confident picks.
            labeled (List[Tuple[UnitStats, str]]): Training units and their original labels.
            context (Optional[PeerContext]): Counterpart and peer lookups used for features, or None.
        """
        self.context = context
        self.vectorizer = vectorizer
        self.estimator = estimator
        self.threshold = threshold
        self.labeled = labeled
        matrix = vectorizer.transform([feature_dict(stats, context) for stats, _ in labeled])
        self._mean = matrix.mean(axis=0)
        self._scale = matrix.std(axis=0) + 1e-9
        self._labeled_matrix = (matrix - self._mean) / self._scale

    def predict(self, stats_list: List[UnitStats], non_core: Optional[List[bool]] = None) -> List[Prediction]:
        """Classify units.

        Args:
            stats_list (List[UnitStats]): Units to classify.
            non_core (Optional[List[bool]]): Per unit, True when it must not be `core` (Regiments of Renown). Its best `special` or `rare` label
                is picked instead.

        Returns:
            One prediction per unit, in order.
        """
        if not stats_list:
            return []
        probabilities = self.estimator.predict_proba(self.vectorizer.transform([feature_dict(stats, self.context) for stats in stats_list]))
        classes = self.estimator.classes_
        is_core = np.array([str(label).startswith("core") for label in classes])
        predictions = []
        for i, row in enumerate(probabilities):
            ranking = np.where(is_core, -1.0, row) if non_core and non_core[i] else row
            order = np.argsort(ranking, kind="stable")[::-1]
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
        vector = (self.vectorizer.transform([feature_dict(stats, self.context)]) - self._mean) / self._scale
        distances = np.sqrt(((self._labeled_matrix - vector) ** 2).sum(axis=1))
        return [(self.labeled[i][0].key, self.labeled[i][1]) for i in np.argsort(distances, kind="stable")[:k]]


def _wilson_lower_bound(successes: int, total: int, z: float = 1.645) -> float:
    """Return the one-sided 95% Wilson lower bound of an accuracy.

    Args:
        successes (int): Correct picks.
        total (int): All picks.
        z (float): Normal quantile. Defaults to 1.645 (one-sided 95%).

    Returns:
        The lower bound, or 0 when `total` is 0.
    """
    if total == 0:
        return 0.0
    p = successes / total
    centre = p + z * z / (2 * total)
    margin = z * np.sqrt(p * (1 - p) / total + z * z / (4 * total * total))
    return float((centre - margin) / (1 + z * z / total))


def _pick_threshold(confidences: np.ndarray, correct: np.ndarray) -> float:
    """Find the lowest confidence cutoff whose confident picks meet the accuracy bar with a margin.

    The threshold is tuned on the same held-out picks it is scored on, so the lower confidence bound (not the raw rate) must clear the bar.

    Args:
        confidences (np.ndarray): Held-out confidence of each pick.
        correct (np.ndarray): Whether each held-out pick was exactly right.

    Returns:
        The cutoff, or infinity when no cutoff meets the bar.
    """
    for threshold in np.unique(confidences):
        mask = confidences >= threshold
        if mask.any() and _wilson_lower_bound(int(correct[mask].sum()), int(mask.sum())) >= CONFIDENT_ACCURACY_BAR:
            return float(threshold)
    return float("inf")


def train(labeled: List[Tuple[UnitStats, str]], groups: Optional[List[str]] = None, context: Optional[PeerContext] = None) -> Tuple[Model, Metrics]:
    """Cross-validate to pick the confidence threshold, then fit the final model on every entry.

    Args:
        labeled (List[Tuple[UnitStats, str]]): Units with their existing labels.
        groups (Optional[List[str]]): Label source per unit. When given, a second cross-validation keeps each source in one fold to report how well
            units from a mod the model has never seen are predicted. It does not change the threshold.
        context (Optional[PeerContext]): Adds counterpart and peer features, mirroring how caps are priced by hand.

    Returns:
        The trained model and its held-out metrics.
    """
    original = [label for _, label in labeled]
    targets = np.array(merge_rare_labels(original))
    vectorizer = DictVectorizer(sparse=False)
    matrix = vectorizer.fit_transform([feature_dict(stats, context) for stats, _ in labeled])
    estimator = HistGradientBoostingClassifier(random_state=0)
    probabilities = cross_val_predict(estimator, matrix, targets, cv=StratifiedKFold(n_splits=5, shuffle=True, random_state=0), method="predict_proba")
    classes = np.unique(targets)
    unseen_mod_exact = None
    if groups is not None:
        folds = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=0)
        grouped = cross_val_predict(estimator, matrix, targets, groups=groups, cv=folds, method="predict_proba")
        unseen_mod_exact = float((classes[grouped.argmax(axis=1)] == np.array(original)).mean())
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
        unseen_mod_exact=unseen_mod_exact,
    )
    estimator.fit(matrix, targets)
    return Model(vectorizer, estimator, threshold, labeled, context), metrics


def training_groups(data) -> List[str]:
    """Return the label source of each unit in `training_set(data)`, in the same order.

    Args:
        data (ttc_data.TtcData): Loaded TTC inputs.

    Returns:
        One group name per training unit.
    """
    return [data.label_sources.get(key, key) for key in sorted(data.labels) if key in data.stats]


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

    loaded = ttc_data.load_all()
    _, result = train(training_set(loaded), training_groups(loaded), PeerContext(loaded.stats, loaded.labels))
    print(f"entries: {result.n}")
    print(f"held-out exact: {result.exact:.1%} | category: {result.category:.1%}")
    print(f"confident picks: {result.confident:.1%} exact on {result.confident_share:.1%} of entries (threshold {result.threshold:.3f})")
    print(f"units from a mod the model has never seen: {result.unseen_mod_exact:.1%} exact")
    sys.exit(0 if result.confident >= CONFIDENT_ACCURACY_BAR else 1)

from __future__ import annotations

import uuid
from dataclasses import dataclass

from core.models import Note

# Mirrors the constants baked into the retired Postgres `match_notes` function
# (backend/core/migrations/0002_match_notes_function.py, now deleted).
CLUSTER_SPACING = 280.0
CLUSTER_GAP = 400.0
SIMILARITY_THRESHOLD = 0.15
CANVAS_ORIGIN_X = 200.0
CANVAS_ORIGIN_Y = 200.0


@dataclass
class MatchedPosition:
    id: uuid.UUID
    new_x: float
    new_y: float


def _cosine_distance(a: list[float], b: list[float]) -> float:
    """1 - cosine_similarity, matching pgvector's `<=>` operator."""
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = sum(x * x for x in a) ** 0.5
    norm_b = sum(y * y for y in b) ** 0.5
    if norm_a == 0 or norm_b == 0:
        return 1.0
    return 1.0 - dot / (norm_a * norm_b)


def match_notes(notes: list[Note]) -> list[MatchedPosition]:
    """Pure-Python port of the Postgres `match_notes(board_uuid)` function.

    Pairs each embedded note with its single nearest neighbor; if that
    pair is within SIMILARITY_THRESHOLD they share a cluster (the note
    with the smaller UUID becomes the canonical cluster id), otherwise
    the note is its own cluster. Notes without an embedding are always
    their own cluster. Clusters are laid out left-to-right by descending
    size (ties broken by cluster id), notes within a cluster top-to-bottom
    ordered by note id.

    Note: unlike the original SQL (which used an inner join and silently
    dropped any note with no other embedded note on the board), this port
    always returns a position for every note passed in, including a single
    isolated embedded note (which gets its own singleton cluster). This is
    an intentional, disclosed improvement, not a parity bug.
    """
    embedded = [n for n in notes if n.embedding is not None]
    unembedded = [n for n in notes if n.embedding is None]

    nearest_id: dict[uuid.UUID, uuid.UUID] = {}
    nearest_dist: dict[uuid.UUID, float] = {}
    for a in embedded:
        best_id: uuid.UUID | None = None
        best_dist = float("inf")
        for b in embedded:
            if b.id == a.id:
                continue
            dist = _cosine_distance(a.embedding, b.embedding)
            if dist < best_dist:
                best_dist = dist
                best_id = b.id
        if best_id is not None:
            nearest_id[a.id] = best_id
            nearest_dist[a.id] = best_dist

    cluster_id: dict[uuid.UUID, uuid.UUID] = {}
    for n in embedded:
        nid = nearest_id.get(n.id)
        dist = nearest_dist.get(n.id)
        if nid is None or dist > SIMILARITY_THRESHOLD:
            cluster_id[n.id] = n.id
        elif n.id < nid:
            cluster_id[n.id] = n.id
        else:
            cluster_id[n.id] = nid

    all_notes_clustered: list[tuple[uuid.UUID, uuid.UUID]] = [
        (n.id, cluster_id[n.id]) for n in embedded
    ] + [(n.id, n.id) for n in unembedded]

    sizes: dict[uuid.UUID, int] = {}
    for _, cid in all_notes_clustered:
        sizes[cid] = sizes.get(cid, 0) + 1
    ordered_clusters = sorted(sizes.keys(), key=lambda cid: (-sizes[cid], cid))
    cluster_idx = {cid: idx for idx, cid in enumerate(ordered_clusters)}

    by_cluster: dict[uuid.UUID, list[uuid.UUID]] = {}
    for note_id, cid in all_notes_clustered:
        by_cluster.setdefault(cid, []).append(note_id)

    positions: list[MatchedPosition] = []
    for cid, note_ids in by_cluster.items():
        for pos_in_cluster, note_id in enumerate(sorted(note_ids)):
            positions.append(
                MatchedPosition(
                    id=note_id,
                    new_x=CANVAS_ORIGIN_X + cluster_idx[cid] * (CLUSTER_SPACING + CLUSTER_GAP),
                    new_y=CANVAS_ORIGIN_Y + pos_in_cluster * CLUSTER_SPACING,
                )
            )
    return positions

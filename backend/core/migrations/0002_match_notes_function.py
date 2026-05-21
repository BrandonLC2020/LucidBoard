from django.db import migrations

MATCH_NOTES_SQL = r"""
CREATE OR REPLACE FUNCTION match_notes(board_uuid uuid)
RETURNS TABLE (id uuid, new_x float4, new_y float4)
LANGUAGE plpgsql
AS $$
DECLARE
    cluster_spacing      float4 := 280;
    cluster_gap          float4 := 400;
    similarity_threshold float8 := 0.15;
    canvas_origin_x      float4 := 200;
    canvas_origin_y      float4 := 200;
BEGIN
    RETURN QUERY
    WITH
    embedded AS (
        SELECT n.id, n.embedding
        FROM notes n
        WHERE n.board_id = board_uuid
          AND n.embedding IS NOT NULL
    ),
    nearest AS (
        SELECT DISTINCT ON (a.id)
            a.id,
            b.id AS nearest_id,
            (a.embedding <=> b.embedding) AS dist
        FROM embedded a
        JOIN embedded b ON b.id <> a.id
        ORDER BY a.id, dist ASC
    ),
    cluster_seeds AS (
        SELECT
            n.id,
            CASE
                WHEN nr.dist > similarity_threshold THEN n.id
                WHEN n.id < nr.nearest_id            THEN n.id
                ELSE nr.nearest_id
            END AS cluster_id
        FROM embedded n
        JOIN nearest nr ON nr.id = n.id
    ),
    all_notes_clustered AS (
        SELECT cs.id, cs.cluster_id
        FROM cluster_seeds cs
        UNION ALL
        SELECT n.id, n.id AS cluster_id
        FROM notes n
        WHERE n.board_id = board_uuid
          AND n.embedding IS NULL
    ),
    cluster_meta AS (
        SELECT
            cluster_id,
            ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, cluster_id) - 1 AS cluster_idx,
            COUNT(*) AS cluster_size
        FROM all_notes_clustered
        GROUP BY cluster_id
    ),
    note_rank AS (
        SELECT
            anc.id,
            anc.cluster_id,
            cm.cluster_idx,
            cm.cluster_size,
            ROW_NUMBER() OVER (PARTITION BY anc.cluster_id ORDER BY anc.id) - 1 AS pos_in_cluster
        FROM all_notes_clustered anc
        JOIN cluster_meta cm ON cm.cluster_id = anc.cluster_id
    ),
    positioned AS (
        SELECT
            nr.id,
            (canvas_origin_x + nr.cluster_idx * (cluster_spacing + cluster_gap))::float4 AS new_x,
            (canvas_origin_y + nr.pos_in_cluster * cluster_spacing)::float4              AS new_y
        FROM note_rank nr
    )
    SELECT p.id, p.new_x, p.new_y
    FROM positioned p;
END;
$$;
"""

DROP_MATCH_NOTES_SQL = "DROP FUNCTION IF EXISTS match_notes(uuid);"


class Migration(migrations.Migration):
    dependencies = [("core", "0001_initial")]

    operations = [
        migrations.RunSQL(MATCH_NOTES_SQL, DROP_MATCH_NOTES_SQL),
    ]

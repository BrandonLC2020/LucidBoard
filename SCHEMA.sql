-- LucidBoard Database Schema

-- 1. Enable pgvector
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Boards Table
CREATE TABLE boards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    title TEXT NOT NULL,
    background_color TEXT DEFAULT '#FFFFFF',
    background_layout TEXT DEFAULT 'grid',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- 3. Notes Table
CREATE TABLE notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    board_id UUID REFERENCES boards(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id),
    content_text TEXT,
    content_drawing BYTEA,
    color TEXT NOT NULL,
    pos_x FLOAT NOT NULL,
    pos_y FLOAT NOT NULL,
    z_index INTEGER NOT NULL,
    template TEXT DEFAULT 'plain',
    checklist_items JSONB DEFAULT '[]'::jsonb,
    embedding VECTOR(1536), -- Assuming OpenAI/Gemini embedding size
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- 4. RPC for Auto-Organize (Clustering Logic)
-- Groups notes by cosine similarity of their embeddings using greedy nearest-neighbor
-- clustering. Notes without embeddings are placed in a fallback row at the bottom.
-- Returns new (x, y) positions so the Swift client can animate notes into place.
CREATE OR REPLACE FUNCTION match_notes(board_uuid uuid)
RETURNS TABLE (id uuid, new_x float4, new_y float4)
LANGUAGE plpgsql
AS $$
DECLARE
    cluster_spacing  float4 := 280;  -- px between note centres within a cluster
    cluster_gap      float4 := 400;  -- px between cluster groups
    similarity_threshold float8 := 0.15; -- cosine distance threshold (0 = identical, 2 = opposite)
    canvas_origin_x  float4 := 200;
    canvas_origin_y  float4 := 200;
BEGIN
    RETURN QUERY
    WITH
    -- Only notes that have been embedded
    embedded AS (
        SELECT n.id, n.embedding
        FROM notes n
        WHERE n.board_id = board_uuid
          AND n.embedding IS NOT NULL
    ),
    -- Build a similarity matrix: for each note, find its nearest embedded neighbour
    -- using pgvector cosine distance (<=>). Lower distance = more similar.
    nearest AS (
        SELECT DISTINCT ON (a.id)
            a.id,
            b.id AS nearest_id,
            (a.embedding <=> b.embedding) AS dist
        FROM embedded a
        JOIN embedded b ON b.id <> a.id
        ORDER BY a.id, dist ASC
    ),
    -- Greedy single-linkage: assign a cluster label by following the nearest-neighbour
    -- chain. Notes whose nearest neighbour is within the threshold share a cluster.
    -- We use a deterministic ordering (id) to break ties.
    cluster_seeds AS (
        SELECT
            n.id,
            -- A note starts a new cluster if its nearest neighbour is too far away,
            -- OR if it is the closer of the two mutual neighbours (prevents cycles).
            CASE
                WHEN nr.dist > similarity_threshold THEN n.id   -- isolated note
                WHEN n.id < nr.nearest_id            THEN n.id  -- canonical seed
                ELSE nr.nearest_id                              -- join seed's cluster
            END AS cluster_id
        FROM embedded n
        JOIN nearest nr ON nr.id = n.id
    ),
    -- Assign notes without embeddings their own singleton cluster id
    all_notes_clustered AS (
        SELECT cs.id, cs.cluster_id
        FROM cluster_seeds cs
        UNION ALL
        SELECT n.id, n.id AS cluster_id
        FROM notes n
        WHERE n.board_id = board_uuid
          AND n.embedding IS NULL
    ),
    -- Rank clusters by size (largest first) and assign a sequential cluster index
    cluster_meta AS (
        SELECT
            cluster_id,
            ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC, cluster_id) - 1 AS cluster_idx,
            COUNT(*) AS cluster_size
        FROM all_notes_clustered
        GROUP BY cluster_id
    ),
    -- Within each cluster, sort notes by similarity to the centroid (approximate:
    -- sort by ascending distance to the cluster member with the lowest id, i.e. the seed)
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
    -- Convert (cluster_idx, pos_in_cluster) into 2-D canvas coordinates.
    -- Clusters are laid out left-to-right; notes inside a cluster form a column.
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

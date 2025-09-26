--------------- Préparation du graphe --------------------------------

-- 1. Création des noeuds à partir des extrémités des tronçons
DROP TABLE IF EXISTS noeud;
CREATE TABLE noeud AS
SELECT DISTINCT ST_StartPoint(geom) AS geom
FROM troncon_departemental_decoupe
UNION
SELECT DISTINCT ST_EndPoint(geom)
FROM troncon_departemental_decoupe;
ALTER TABLE noeud ADD COLUMN id SERIAL PRIMARY KEY; -- ajout d'un identifiant unique


CREATE INDEX IF NOT EXISTS idx_noeud_geom ON noeud USING GIST(geom); --pour accélérer les calculs  
-- 2. Transformer les tronçons en table d'arêtes avec un noeud de départ et d'arrivée
    -- construction des arêtes dans le sens de numérisation
DROP TABLE IF EXISTS arete;
CREATE TABLE arete AS
SELECT
    t.*,
    ST_StartPoint(t.geom) AS source_geom,   -- pour faire la correspondance avec les noeud et la màj des id ensuite
    ST_EndPoint(t.geom)   AS target_geom,
    NULL::integer AS source_id,  -- on initialise des champs id source et target
    NULL::integer AS target_id
FROM troncon_departemental_decoupe t;

    -- mise à jour des source_id et target_id avec les id de noeud (très lent, peut mettre 15min)
UPDATE arete a
SET source_id = n.id
FROM noeud n
WHERE ST_Equals(a.source_geom, n.geom);

UPDATE arete a
SET target_id = n.id
FROM noeud n
WHERE ST_Equals(a.target_geom, n.geom);

    -- on supprime les colonnes source_geom et target_geom qui ne sont plus utiles
ALTER TABLE arete
DROP COLUMN source_geom,
DROP COLUMN target_geom;
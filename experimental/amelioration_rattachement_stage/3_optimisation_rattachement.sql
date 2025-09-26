-------------- OPTIMISATION DU RATTACHEMENT (pour minimiser le surédécoupage du réseau par les panneaux par la suite) -----------------------------


DROP TABLE IF EXISTS rattachement_cd44_optimise;

CREATE TABLE rattachement_cd44_optimise AS
WITH 
-- 1. regroupement des jumeaux
	-- selection des paires de panneaux proches et opposés (potentiellement jumeaux)
paires_proches AS (
    SELECT 
        LEAST(p1.id_panneau, p2.id_panneau) AS id_panneau_1,
        GREATEST(p1.id_panneau, p2.id_panneau) AS id_panneau_2,
        p1.id_troncon,
        p1.position_sur_troncon AS pos1,
        p2.position_sur_troncon AS pos2,
        ST_Distance(p1.panneau_projete, p2.panneau_projete) AS dist
    FROM rattachement_cd44 p1
    JOIN rattachement_cd44 p2
      ON p1.id_troncon = p2.id_troncon   -- on prend les panneaux sur un même tronçon
     AND p1.sens = -p2.sens     -- on prend les panneaux de direction opposée
     AND p1.id_panneau < p2.id_panneau
    WHERE ST_DWithin(p1.panneau_projete, p2.panneau_projete, 40)  -- on prend les panneaux proches dans un rayon de 40m
),

	-- on classe pour chaque panneau ses candidats jumeaux par distance
rang AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id_panneau_1 ORDER BY dist ASC) AS rn1, -- on obtient le rang du jumeaux le plus proche pour id_panneau_1
           ROW_NUMBER() OVER (PARTITION BY id_panneau_2 ORDER BY dist ASC) AS rn2 -- et le rang du jumeau le plus proche pour id_panneau_2
    FROM paires_proches
),

jumeaux AS (
    SELECT * FROM rang WHERE rn1 = 1 AND rn2 = 1 -- on garde juste les paires réciproques pour s'assurer que chaque panneau est le plus proche de l'autre 
),
	-- calcul des points de regroupement des jumeaux
regroupement_jumeaux AS (
    SELECT 
        pid.id_panneau,
        t.cleabs AS id_troncon,
        ST_Force2D(ST_LineInterpolatePoint(t.geom, (j.pos1 + j.pos2)/2.0)) AS panneau_projete, -- pour chaque paire de jumeaux on projette leur point médian sur le troncon
        (j.pos1 + j.pos2)/2.0 AS position_sur_troncon
    FROM jumeaux j
    JOIN troncon_departemental t ON t.cleabs = j.id_troncon
    CROSS JOIN LATERAL (VALUES (j.id_panneau_1), (j.id_panneau_2)) AS pid(id_panneau) -- génère 2 lignes pour chaque paire de jumeaux
),

base AS (
    SELECT * FROM rattachement_cd44
),

	-- on met a jour les entités jumelles
maj_jumeaux AS (
    SELECT 
        r.id_rattachement,
        r.id_panneau,
        r.id_troncon,
        r.sens,
        COALESCE(j.position_sur_troncon, r.position_sur_troncon) AS position_sur_troncon,   -- on remplace la valeur de position_sur_troncon si elle a été modifiée (panneaux jumeaux)
        COALESCE(j.panneau_projete, r.panneau_projete) AS panneau_projete  -- pareil pour la geometrie
    FROM base r
    LEFT JOIN regroupement_jumeaux j ON r.id_panneau = j.id_panneau
),
-- 2. On rabat aux extrémités les panneaux proches d'extrémités (distance < 25m)
maj_extremites AS (
    SELECT 
        r.*,
        CASE 
            WHEN ST_Distance(r.panneau_projete, ST_StartPoint(t.geom)) <= 25 THEN 0.0
            WHEN ST_Distance(r.panneau_projete, ST_EndPoint(t.geom))   <= 25 THEN 1.0
            ELSE r.position_sur_troncon
        END AS position_finale,
        CASE 
            WHEN ST_Distance(r.panneau_projete, ST_StartPoint(t.geom)) <= 25 THEN ST_Force2D(ST_StartPoint(t.geom))
            WHEN ST_Distance(r.panneau_projete, ST_EndPoint(t.geom))   <= 25 THEN ST_Force2D(ST_EndPoint(t.geom))
            ELSE r.panneau_projete
        END AS panneau_projete_final
    FROM maj_jumeaux r
    JOIN troncon_departemental t ON r.id_troncon = t.cleabs
), -- environ 2500 cas

-- 3. Suppression des doublons
sans_doublons AS (
    SELECT r.*
    FROM maj_extremites r
    LEFT JOIN (
        SELECT 
            GREATEST(r1.id_panneau, r2.id_panneau) AS id_panneau_supprimer
        FROM maj_extremites r1
        JOIN maj_extremites r2
          ON r1.id_troncon = r2.id_troncon
         AND r1.sens = r2.sens
         AND r1.id_panneau < r2.id_panneau
        JOIN panneaux_vitesses_cd44_standard p1 ON r1.id_panneau = p1.id_panneau
        JOIN panneaux_vitesses_cd44_standard p2 ON r2.id_panneau = p2.id_panneau
           AND p1.vitesse = p2.vitesse
        WHERE ST_DWithin(r1.panneau_projete, r2.panneau_projete, 10)
    ) d ON r.id_panneau = d.id_panneau_supprimer
    WHERE d.id_panneau_supprimer IS NULL
)
-- Table finale
SELECT 
    id_rattachement,
    id_panneau,
    id_troncon,
    sens,
    position_finale AS position_sur_troncon,
    panneau_projete_final AS panneau_projete
FROM sans_doublons;



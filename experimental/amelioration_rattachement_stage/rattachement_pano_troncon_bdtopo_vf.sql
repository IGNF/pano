-- Processus de rattachement de panneaux aux troncons de la BDTopo 

/*
Version validée

Test effectué avec les données de l'eurométropole de Strasbourg, cleanées et mises au modèle 
(tables panneau_strasbourg_metrop_2154_vf et panonceaux_strasbourg_metrop_2154_vf)
100% des panneaux sont rattachés suivant le test

Critères modulables, les valeurs peuvent être changées

*/

-------------------------------------------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------------------------------------------



-- Extensions : 

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Index spatiaux : 

CREATE INDEX IF NOT EXISTS idx_panneaux_geom ON panneaux_strasbourg_metrop_2154_vf USING GIST (geometrie);
CREATE INDEX IF NOT EXISTS idx_troncons_geom ON troncon_de_route_select_bbox_strasbourg_metrop USING GIST (geom);

-- Fonctions : 

-- Fonction qui dit si un point est situé à droite d'une ligne selon le sens de numérisation, en Lambert93
CREATE OR REPLACE FUNCTION is_right(line geometry(LineString, 2154), point geometry(Point, 2154)) RETURNS boolean AS $$
    SELECT ST_Contains(ST_Buffer(line, 20, 'side=right'), point);
$$ LANGUAGE SQL IMMUTABLE;

-- Calcul de l'azimuth de la direction prise par une ligne en un point, en Lambert-93
CREATE OR REPLACE FUNCTION linestring_azimuth_at_point(
    _line geometry(Linestring, 2154),
    _point geometry(Point, 2154)
) RETURNS real AS $$
DECLARE
    len double precision; -- curseur de distance pour trouver dans la ligne le segment contenant le point
BEGIN
    len = 0.0;
    FOR i IN 1..ST_NumPoints(_line)-1
    LOOP
        len = len + ST_Length(ST_MakeLine(ST_PointN(_line, i), ST_PointN(_line, i+1)));
        IF len > ST_Length(_line) * ST_LineLocatePoint(_line, _point) THEN
            RETURN degrees(ST_Azimuth(ST_PointN(_line, i), ST_PointN(_line, i+1)));
        END IF;
    END LOOP;
    -- si le point est sur l'extrémité finale de la linestring, la fonction renvoie null
    RETURN null;
END;
$$ LANGUAGE PLPGSQL IMMUTABLE;

-- Rattachement :

/*
TRUNCATE TABLE rattachement_bdtopo;
*/

-- Étape 1 : Rattachement par correspondance entre les champs `axe` et `cpx_numero` (non nuls)
INSERT INTO rattachement_bdtopo (
    id_panneau, id_troncon, panneau_projete, azimuth_projete, sens, position_sur_troncon
)
SELECT
    p.id_panneau,
    t.cleabs,
    ST_ClosestPoint(t.geom, p.geometrie) AS panneau_projete,
    degrees(ST_Azimuth(ST_PointN(t.geom, 1), ST_ClosestPoint(t.geom, p.geometrie))) AS azimuth_projete,
    CASE
        WHEN t.sens_de_circulation = 'Sens direct' THEN 1
        WHEN t.sens_de_circulation = 'Sens inverse' THEN -1
        ELSE (
            CASE
                WHEN p.azimuth_modulo IS NOT NULL AND 
                     (CAST(degrees(ST_Azimuth(ST_PointN(t.geom, 1), ST_ClosestPoint(t.geom, p.geometrie))) AS integer) % 360) 
                     BETWEEN ((CAST(p.azimuth_modulo AS integer) - 20) % 360) AND ((CAST(p.azimuth_modulo AS integer) + 20) % 360) THEN 1
                WHEN p.azimuth_modulo IS NOT NULL AND 
                     (CAST(degrees(ST_Azimuth(ST_PointN(t.geom, 1), ST_ClosestPoint(t.geom, p.geometrie))) AS integer) % 360) 
                     BETWEEN ((CAST(p.azimuth_modulo AS integer) + 160) % 360) AND ((CAST(p.azimuth_modulo AS integer) + 200) % 360) THEN -1
                WHEN p.lateral_route = 'D' THEN 1
                WHEN p.lateral_route = 'G' THEN -1
                ELSE (CASE WHEN is_right(t.geom, p.geometrie) THEN 1 ELSE -1 END)
            END)
    END AS sens,
	ST_LineLocatePoint(t.geom, ST_ClosestPoint(t.geom, p.geometrie)) AS position_sur_troncon  -- Calculer la position sur le tronçon
FROM 
    panneaux_strasbourg_metrop_2154_vf p
JOIN 
    troncon_de_route_select_bbox_strasbourg_metrop t
ON 
    p.axe = t.cpx_numero
WHERE
    p.axe IS NOT NULL AND t.cpx_numero IS NOT NULL
ORDER BY 
    ST_Distance(t.geom, p.geometrie) ASC
LIMIT 1;

-- Etape 2: Rattacher un panneau à un tronçon en utilisant en modulant des critères de distance (buffer) et d'autres critères  

-- Etape 2.1 : Cas où un seul tronçon traverse le buffer 

-- Etape 2.1.1 : Création d'un buffer sur les panneaux non-rattachés, filtre sur nb troncons traversant le buffer = 1
WITH panneaux_sans_rattachement AS (
    -- Sélectionner les panneaux qui ne sont pas encore rattachés
    SELECT p.*
    FROM panneaux_strasbourg_metrop_2154_vf p
    LEFT JOIN rattachement_bdtopo r ON p.id_panneau = r.id_panneau
    WHERE r.id_panneau IS NULL
),
buffer_data AS (
    SELECT 
        p.id_panneau,
        t.cleabs,
        ST_ClosestPoint(t.geom, p.geometrie) AS panneau_projete,
        t.geom AS troncon_geom,
        t.sens_de_circulation,
        t.cpx_numero,
        p.azimuth_modulo,
        p.geometrie AS panneau_geom,
        p.lateral_route,
        ST_Distance(p.geometrie, t.geom) AS distance,
		ROW_NUMBER() OVER (PARTITION BY p.id_panneau ORDER BY ST_Distance(p.geometrie, t.geom) ASC) AS rn
    FROM 
        panneaux_sans_rattachement p
    LEFT JOIN 
        troncon_de_route_select_bbox_strasbourg_metrop t
    ON 
        ST_Intersects(ST_Buffer(p.geometrie, 15), t.geom)
    GROUP BY 
        p.id_panneau, t.cleabs, p.geometrie, t.geom, t.sens_de_circulation, t.cpx_numero, p.azimuth_modulo, p.lateral_route
    HAVING COUNT(*) = 1  -- Garder uniquement les panneaux associés à un seul tronçon
)

-- Étape 2.1.2 : Rattachement des panneaux filtrés grâce au buffer à un troncon
INSERT INTO rattachement_bdtopo (
    id_panneau, id_troncon, panneau_projete, azimuth_projete, sens, position_sur_troncon
)
SELECT 
    DISTINCT id_panneau, -- Utiliser distinct pour éviter les doublons
    cleabs,
    panneau_projete,
    degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete)) AS azimuth_projete,
    CASE
        WHEN sens_de_circulation = 'Sens direct' THEN 1
        WHEN sens_de_circulation = 'Sens inverse' THEN -1
        ELSE (
            CASE
                WHEN azimuth_modulo IS NOT NULL AND 
                     (CAST(degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete)) AS integer) % 360) 
                     BETWEEN ((CAST(azimuth_modulo AS integer) - 20) % 360) AND ((CAST(azimuth_modulo AS integer) + 20) % 360) THEN 1
                WHEN azimuth_modulo IS NOT NULL AND 
                     (CAST(degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete)) AS integer) % 360) 
                     BETWEEN ((CAST(azimuth_modulo AS integer) + 160) % 360) AND ((CAST(azimuth_modulo AS integer) + 200) % 360) THEN -1
                WHEN lateral_route = 'D' THEN 1
                WHEN lateral_route = 'G' THEN -1
                ELSE (CASE WHEN is_right(troncon_geom, panneau_geom) THEN 1 ELSE -1 END)
            END)
    END AS sens,
    ST_LineLocatePoint(troncon_geom, ST_ClosestPoint(troncon_geom, panneau_geom)) AS position_sur_troncon  -- Utilisez le bon alias pour le tronçon
FROM buffer_data
WHERE id_panneau NOT IN (SELECT id_panneau FROM rattachement_bdtopo) -- Vérifier que le panneau n'est pas déjà rattaché
AND rn = 1
;

-- Etape 2.2 : Cas où un ou plusieurs tronçons d'une même route (ici même cpx_numero mais un autre critère pourrait être utilisé, comme le toponyme) traversent le buffer 

-- Étape 2.2.1 : Création d'un buffer sur les panneaux non-rattachés, filtre sur le cpx numero non null et identique pour tous les tronçons qui intersectent le buffer
WITH panneaux_sans_rattachement AS (
    -- Sélectionner les panneaux qui ne sont pas encore rattachés
    SELECT p.*
    FROM panneaux_strasbourg_metrop_2154_vf p
    LEFT JOIN rattachement_bdtopo r ON p.id_panneau = r.id_panneau
    WHERE r.id_panneau IS NULL
),

buffer_data_step2_2 AS (
    SELECT 
        p.id_panneau,  
        t.cleabs,  
        ST_ClosestPoint(t.geom, p.geometrie) AS panneau_projete,
        t.geom AS troncon_geom,
        t.sens_de_circulation,
        t.cpx_numero,
        p.azimuth_modulo,
        p.geometrie AS panneau_geom,
        p.lateral_route,
        ST_Distance(p.geometrie, t.geom) AS distance,
        COUNT(DISTINCT t.cleabs) AS nb_troncons,
        COUNT(DISTINCT t.cpx_numero) AS nb_distinct_cpx
    FROM 
        panneaux_sans_rattachement p
    LEFT JOIN 
        troncon_de_route_select_bbox_strasbourg_metrop t
    ON 
        ST_Intersects(ST_Buffer(p.geometrie, 15), t.geom)
    GROUP BY p.id_panneau, t.cleabs, t.geom, t.sens_de_circulation, t.cpx_numero, p.azimuth_modulo, p.geometrie, p.lateral_route
    HAVING 
        COUNT(DISTINCT t.cpx_numero) = 1 AND      -- Vérifie que tous les tronçons ont le même numéro cpx
        COUNT(t.cpx_numero) = COUNT(*)              -- Vérifie que tous les tronçons ont un cpx_numero non nul
),

buffer_data_ranked AS (
    -- Récupérer les tronçons triés par distance croissante par rapport aux panneaux
    SELECT 
        *, 
        ROW_NUMBER() OVER (PARTITION BY id_panneau ORDER BY distance ASC) AS rn  -- Numéro de rang pour chaque tronçon par panneau
    FROM buffer_data_step2_2
)

-- Étape 2.2.2 : Rattachement des panneaux filtrés grâce au buffer à un tronçon
INSERT INTO rattachement_bdtopo (
    id_panneau, id_troncon, panneau_projete, azimuth_projete, sens, position_sur_troncon
)
SELECT DISTINCT
    id_panneau,
    cleabs,
    panneau_projete,
    degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete)) AS azimuth_projete,  -- Calculer l'azimuth projeté du tronçon
    CASE
        WHEN sens_de_circulation = 'Sens direct' THEN 1
        WHEN sens_de_circulation = 'Sens inverse' THEN -1
        ELSE 
            CASE 
                WHEN azimuth_modulo IS NOT NULL AND (CAST(degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete)) AS integer) % 360) 
                     BETWEEN ((CAST(azimuth_modulo AS integer) - 20) % 360) AND ((CAST(azimuth_modulo AS integer) + 20) % 360) THEN 1
                WHEN azimuth_modulo IS NOT NULL AND (CAST(degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete)) AS integer) % 360) 
                     BETWEEN ((CAST(azimuth_modulo AS integer) + 160) % 360) AND ((CAST(azimuth_modulo AS integer) + 200) % 360) THEN -1
                WHEN lateral_route = 'D' THEN 1
                WHEN lateral_route = 'G' THEN -1
                ELSE (CASE WHEN is_right(troncon_geom, panneau_geom) THEN 1 ELSE -1 END)
            END
    END AS sens,
    ST_LineLocatePoint(troncon_geom, ST_ClosestPoint(troncon_geom, panneau_geom)) AS position_sur_troncon  -- Utilisez le bon alias pour le tronçon
FROM buffer_data_ranked
WHERE id_panneau NOT IN (SELECT id_panneau FROM rattachement_bdtopo) -- Vérifier que le panneau n'est pas déjà rattaché
AND rn = 1  -- Ne retenir que le tronçon le plus proche pour chaque panneau   
;

-- Etape 2.3 : Cas où plusieurs tronçons de routes différentes traversent le buffer et où on connait l'azimuth du panneau

-- Etape 2.3.1 : Création d'un buffer sur les panneaux non-rattachés et dont on connait l'azimuth
WITH panneaux_sans_rattachement_azimuth AS (
    -- Sélectionner les panneaux qui ne sont pas encore rattachés et dont on connait l'azimuth
    SELECT p.*
    FROM panneaux_strasbourg_metrop_2154_vf p
    LEFT JOIN rattachement_bdtopo r ON p.id_panneau = r.id_panneau
    WHERE r.id_panneau IS NULL AND p.azimuth_modulo IS NOT NULL
),

buffer_data_step2_3 AS (
    -- Créer un ensemble des données des panneaux et tronçons après avoir filtré les panneaux non rattachés
    SELECT 
        p.id_panneau,
        t.cleabs,
        ST_ClosestPoint(t.geom, p.geometrie) AS panneau_projete,
        t.geom AS troncon_geom,
        t.sens_de_circulation,
        t.cpx_numero,
        p.azimuth_modulo,
        p.geometrie AS panneau_geom,
        p.lateral_route,
        ST_Distance(p.geometrie, t.geom) AS distance,
        degrees(ST_Azimuth(ST_PointN(t.geom, 1), ST_ClosestPoint(t.geom, p.geometrie))) AS azimuth_projete  -- Calculer l'azimuth projeté du tronçon
    FROM 
        panneaux_sans_rattachement_azimuth p
    LEFT JOIN 
        troncon_de_route_select_bbox_strasbourg_metrop t
    ON 
        ST_Intersects(ST_Buffer(p.geometrie, 15), t.geom)
),

/*
buffer_data_filtered_step2_3 AS (
    -- Filtrer les données des tronçons qui ont un azimuth projeté proche de l'azimuth du panneau (±10° ou entre 170° et 190° par rapport à l'azimuth_modulo)
    SELECT 
        bd.*
    FROM buffer_data_step2_3 bd
    WHERE 
        (
            MOD(degrees(ST_Azimuth(ST_PointN(bd.troncon_geom, 1), bd.panneau_projete))::double precision, 360::double precision) 
            BETWEEN MOD((bd.azimuth_modulo - 10)::double precision, 360::double precision) AND MOD((bd.azimuth_modulo + 10)::double precision, 360::double precision)
        )
        OR 
        (
            MOD(degrees(ST_Azimuth(ST_PointN(bd.troncon_geom, 1), bd.panneau_projete))::double precision, 360::double precision)
            BETWEEN MOD((bd.azimuth_modulo + 170)::double precision, 360::double precision) AND MOD((bd.azimuth_modulo + 190)::double precision, 360::double precision)
        )
    -- Ne retenir que les tronçons dont l'azimuth du point projeté est dans ±10 degrés ou entre 170° et 190° par rapport à l'azimuth du panneau (modulo 360)
),
*/

buffer_data_filtered_step2_3 AS (
    -- Filtrer les données des tronçons qui ont un azimuth projeté proche de l'azimuth du panneau (±10° ou entre 170° et 190° par rapport à l'azimuth_modulo)
    SELECT 
        bd.*
    FROM buffer_data_step2_3 bd
    WHERE 
        (
            (CAST(degrees(ST_Azimuth(ST_PointN(bd.troncon_geom, 1), bd.panneau_projete)) AS integer) % 360) 
            BETWEEN ((CAST(bd.azimuth_modulo AS integer) - 10) % 360) AND ((CAST(bd.azimuth_modulo AS integer) + 10) % 360)
        )
        OR 
        (
            (CAST(degrees(ST_Azimuth(ST_PointN(bd.troncon_geom, 1), bd.panneau_projete)) AS integer) % 360)
            BETWEEN ((CAST(bd.azimuth_modulo AS integer) + 170) % 360) AND ((CAST(bd.azimuth_modulo AS integer) + 190) % 360)
        )
    -- Ne retenir que les tronçons dont l'azimuth du point projeté est dans ±10 degrés ou entre 170° et 190° par rapport à l'azimuth du panneau (modulo 360)
),
/* Ce qui serait bien, ce serait que s'il n'y a pas de tronçons qui traversent le buffer dont l'azimuth_projete est dans l'intervalle 
-10 à +10 degrés ou +170 à +190 degrés modulo 360, on essaie avec un intervalle plus grand (+-15 degrés par exemple, ou +-20 degrés)*/

buffer_data_ranked_step2_3 AS (
    -- Récupérer les tronçons triés par distance croissante pour les panneaux sélectionnés à l'étape 2.3
    SELECT 
        *, 
        ROW_NUMBER() OVER (PARTITION BY id_panneau ORDER BY distance ASC) AS rn  -- Numéro de rang pour chaque tronçon par panneau
    FROM buffer_data_filtered_step2_3
)

-- Étape 2.3.2 : Rattachement des panneaux filtrés à un tronçon
INSERT INTO rattachement_bdtopo (
    id_panneau, id_troncon, panneau_projete, azimuth_projete, sens, position_sur_troncon
)
SELECT DISTINCT
    id_panneau,
    cleabs,
    panneau_projete,
    azimuth_projete,
    CASE
        WHEN sens_de_circulation = 'Sens direct' THEN 1
        WHEN sens_de_circulation = 'Sens inverse' THEN -1
        ELSE
			CASE 
            	WHEN azimuth_modulo IS NOT NULL AND (CAST(degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete)) AS integer) % 360) 
                	BETWEEN ((CAST(azimuth_modulo AS integer) - 20) % 360) AND ((CAST(azimuth_modulo AS integer) + 20) % 360) THEN 1
            	WHEN azimuth_modulo IS NOT NULL AND (CAST(degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete)) AS integer) % 360) 
                 	BETWEEN ((CAST(azimuth_modulo AS integer) + 160) % 360) AND ((CAST(azimuth_modulo AS integer) + 200) % 360) THEN -1
            	WHEN lateral_route = 'D' THEN 1
            	WHEN lateral_route = 'G' THEN -1
            	ELSE (CASE WHEN is_right(troncon_geom, panneau_geom) THEN 1 ELSE -1 END)
        	END
			/*
			CASE 
    			WHEN azimuth_modulo IS NOT NULL AND 
         			MOD(degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete))::double precision, 360::double precision) 
         			BETWEEN MOD((azimuth_modulo - 10)::double precision, 360::double precision) AND MOD((azimuth_modulo + 10)::double precision, 360::double precision) THEN 1
    			WHEN azimuth_modulo IS NOT NULL AND 
         			MOD(degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete))::double precision, 360::double precision) 
         			BETWEEN MOD((azimuth_modulo + 170)::double precision, 360::double precision) AND MOD((azimuth_modulo + 190)::double precision, 360::double precision) THEN -1
    			WHEN lateral_route = 'D' THEN 1
    			WHEN lateral_route = 'G' THEN -1
    			ELSE (CASE WHEN is_right(troncon_geom, panneau_geom) THEN 1 ELSE -1 END)
			END
			*/
    END AS sens,
    ST_LineLocatePoint(troncon_geom, ST_ClosestPoint(troncon_geom, panneau_geom)) AS position_sur_troncon  -- Utilisez le bon alias pour le tronçon
FROM buffer_data_ranked_step2_3
WHERE id_panneau NOT IN (SELECT id_panneau FROM rattachement_bdtopo) -- Vérifier que le panneau n'est pas déjà rattaché
AND rn = 1  -- Ne retenir que le tronçon le plus proche pour chaque panneau   
;

-- Etape 2.4 : Cas où plusieurs tronçons de routes différentes traversent le buffer et où on ne connait pas l'azimuth du panneau

-- Etape 2.4.1 : Création d'un buffer sur les panneaux non-rattachés et dont on ne connait pas l'azimuth
WITH panneaux_sans_rattachement_azimuth_null AS (
    -- Sélectionner les panneaux non-rattachés dont l'azimuth est NULL
    SELECT p.*
    FROM panneaux_strasbourg_metrop_2154_vf p
    LEFT JOIN rattachement_bdtopo r ON p.id_panneau = r.id_panneau
    WHERE r.id_panneau IS NULL AND p.azimuth_modulo IS NULL
),

buffer_data_step2_4 AS (
    -- Créer un ensemble des données des panneaux avec azimuth NULL et leurs tronçons
    SELECT 
        p.id_panneau,
        t.cleabs,
        ST_ClosestPoint(t.geom, p.geometrie) AS panneau_projete,
        t.geom AS troncon_geom,
        t.sens_de_circulation,
        t.cpx_numero,
        p.geometrie AS panneau_geom,
        p.lateral_route,
        ST_Distance(p.geometrie, t.geom) AS distance
    FROM 
        panneaux_sans_rattachement_azimuth_null p
    LEFT JOIN 
        troncon_de_route_select_bbox_strasbourg_metrop t
    ON 
        ST_Intersects(ST_Buffer(p.geometrie, 15), t.geom)
),

buffer_data_ranked_step2_4 AS (
    -- Récupérer les tronçons triés par distance croissante pour les panneaux sélectionnés à l'étape 2.4
    SELECT 
        *, 
        ROW_NUMBER() OVER (PARTITION BY id_panneau ORDER BY distance ASC) AS rn  -- Numéro de rang pour chaque tronçon par panneau
    FROM buffer_data_step2_4
)

-- Étape 2.4.2 : Rattachement des panneaux filtrés à un tronçon
INSERT INTO rattachement_bdtopo (
    id_panneau, id_troncon, panneau_projete, azimuth_projete, sens, position_sur_troncon
)
SELECT DISTINCT
    id_panneau,
    cleabs,
    panneau_projete,
    degrees(ST_Azimuth(ST_PointN(troncon_geom, 1), panneau_projete)) AS azimuth_projete,  -- Calculer l'azimuth projeté du tronçon
    CASE
        WHEN sens_de_circulation = 'Sens direct' THEN 1
        WHEN sens_de_circulation = 'Sens inverse' THEN -1
        ELSE
			CASE 
            	WHEN lateral_route = 'D' THEN 1
            	WHEN lateral_route = 'G' THEN -1
            	ELSE (CASE WHEN is_right(troncon_geom, panneau_geom) THEN 1 ELSE -1 END)
        	END
    END AS sens,
    ST_LineLocatePoint(troncon_geom, ST_ClosestPoint(troncon_geom, panneau_geom)) AS position_sur_troncon  -- Utilisez le bon alias pour le tronçon
FROM buffer_data_ranked_step2_4
WHERE id_panneau NOT IN (SELECT id_panneau FROM rattachement_bdtopo)  -- Vérifier que le panneau n'est pas déjà rattaché
AND rn = 1 -- Ne retenir que le tronçon le plus proche...
AND ( 
    (lateral_route = 'D' AND is_right(troncon_geom, panneau_geom)) OR -- ...parmi les tronçons is_right quand la valeur de lateral route est D
    (lateral_route = 'G' AND NOT is_right(troncon_geom, panneau_geom)) OR -- ...parmi les tronçons not is_right quand la valeur de lateral route est G
    (lateral_route NOT IN ('D', 'G'))  -- Rattacher au tronçon le plus proche si lateral_route n'est pas D ou G
);


-- Etape 2.5 : Cas des panneaux restant

/* On peut imaginer des panneaux dont on ne connaitrait pas l'axe/cpx_numero, et dont l'imprécision des coordonnées ferait que le buffer de 15m 
ne serait traversé par aucun tronçon. Dans ce cas, on pourrait les traiter en reproduisant mes mêmes étapes mais avec un buffer de taille supérieure, ou bien juste
en cherchant le tronçon le plus proche, si on ne connait pas l'azimuth. */ 

/* Dans les données travaillées cependant, le buffer de 15m avait été estimé suffisant après avoir comparé la distance entre panneau et projeté du panneau, 
ainsi que les informations de précision planimétrique qui avaient été transmises par les collecteurs des données */ 

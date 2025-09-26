 -- Processus de rattachement de panneaux aux troncons de la BDTopo 

/*
Rattachement des panneaux de vitesses du département 44 (données transmises par le CD44), jeu de données déjà mis au modèle (tables panneaux_vitesses_cd44_standard)
99.7% des panneaux sont rattachés suivant le test soit 6627 panneaux
*/

-------------------------------------------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Extensions : 

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Index spatiaux : 
DROP INDEX idx_panneaux_geom;
DROP INDEX idx_troncons_geom;

CREATE INDEX IF NOT EXISTS idx_panneaux_geom ON panneaux_vitesses_cd44_standard USING GIST (geometrie);
CREATE INDEX IF NOT EXISTS idx_troncons_geom ON troncon_de_route USING GIST (geom);

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

	-- Etape préalable : Création de la table de rattachement

DROP TABLE IF EXISTS rattachement_cd44;

CREATE TABLE public.rattachement_cd44 (
    id_rattachement UUID PRIMARY KEY DEFAULT gen_random_uuid(),	-- Identifiant du rattachement entre un panneau et un tronçon de route
    id_panneau UUID,												-- Identifiant du panneau
    id_troncon VARCHAR (24),										-- Identifiant du tronçon de route. Se réfère au champs cleabs de la BDTopo troncon_de_route
    position_sur_troncon REAL,									-- Position du panneau sur le troncon entre 0 et 1
    sens INTEGER,												-- Sens d'application du panneau par rapport au sens de circulation
    panneau_projete GEOMETRY(Point, 2154),						-- Projeté du panneau sur le tronçon de route
    azimuth_projete FLOAT										-- Azimuth du projeté du panneau
);


-- TRUNCATE TABLE rattachement_cd44;


-- Rattachement par correspondance entre les champs `axe` et `cpx_numero` (non nuls)
INSERT INTO rattachement_cd44 (
    id_panneau, id_troncon, panneau_projete, azimuth_projete, sens, position_sur_troncon
)
SELECT DISTINCT ON (p.id_panneau)
    p.id_panneau,
    t.cleabs,
    ST_ClosestPoint(t.geom, p.geometrie) AS panneau_projete,
    degrees(ST_Azimuth(ST_PointN(t.geom, 1), ST_ClosestPoint(t.geom, p.geometrie))) AS azimuth_projete,
    CASE
        WHEN t.sens_de_circulation = 'Sens direct' THEN 1
        WHEN t.sens_de_circulation = 'Sens inverse' THEN -1
        ELSE (
            CASE
                WHEN p.azimuth IS NOT NULL AND 
                     (CAST(degrees(ST_Azimuth(ST_PointN(t.geom, 1), ST_ClosestPoint(t.geom, p.geometrie))) AS integer) % 360) 
                     BETWEEN ((CAST(p.azimuth AS integer) - 20) % 360) AND ((CAST(p.azimuth AS integer) + 20) % 360) THEN 1
                WHEN p.azimuth IS NOT NULL AND 
                     (CAST(degrees(ST_Azimuth(ST_PointN(t.geom, 1), ST_ClosestPoint(t.geom, p.geometrie))) AS integer) % 360) 
                     BETWEEN ((CAST(p.azimuth AS integer) + 160) % 360) AND ((CAST(p.azimuth AS integer) + 200) % 360) THEN -1
                WHEN p.lateral_route = 'D' THEN 1
                WHEN p.lateral_route = 'G' THEN -1
                ELSE (CASE WHEN is_right(t.geom, p.geometrie) THEN 1 ELSE -1 END)
            END)
    END AS sens,
    ST_LineLocatePoint(t.geom, ST_ClosestPoint(t.geom, p.geometrie)) AS position_sur_troncon
FROM 
    panneaux_vitesses_cd44_standard p
JOIN 
    troncon_departemental t
    ON p.axe = t.cpx_numero
WHERE
    p.axe IS NOT NULL AND t.cpx_numero IS NOT NULL
ORDER BY 
    p.id_panneau,
    ST_Distance(t.geom, p.geometrie) ASC;

-- on obtient 6627 panneaux rattachés, soit plus de 99% des panneaux du jeu de données


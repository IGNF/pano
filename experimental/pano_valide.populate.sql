

-- ####################################################
-- populate pano_valide :
-- ####################################################
INSERT INTO pano_valide(id, code,etat,geometrie,producteur,commentaire) (
    SELECT
        id                          AS id,
        pano_clean_code(
            array[
                Type_1,Type_3,Type_2,Type_4,Type_5,Type_6,Type_7
                ]
        )                           AS code,
        lower(Etat_1)::text         AS etat,
        ST_SetSrid(
            the_geom,
            4326
        )::geometry(Point, 4326)    AS geometrie,
        'police'                    AS producteur,
        'jeu de données test'       AS commentaire
    FROM pano);
-- Cas particuliers à traiter :
-- 'Ab3--b-50m' --> {"Ab3b":"50m"}
UPDATE pano_valide SET code = cast('{"Ab3b":"50m"}' AS json) WHERE id IN (
    SELECT id FROM pano WHERE Type_1 = 'Ab3--b-50m'
);
-- 'B14-B14-30km/h' --> '{"B14":30}'
UPDATE pano_valide SET code = cast('{"B14":"30"}' AS json) WHERE id IN (
    SELECT id FROM pano WHERE trim(Type_1) = 'B14-B14-30km/h'
);
-- 'B21-1' --> '{"B21-1":""}'
UPDATE pano_valide SET code = cast('{"B21-1":""}' AS json) WHERE id IN (
    SELECT id FROM pano WHERE Type_1 = 'B21-1'
);


-- ####################################################
-- calcul rattachements : 
-- ####################################################
INSERT INTO rattachements (
    SELECT
        pano,
        bdtopo_troncon,
        bdtopo_position_sur_troncon,
        bdtopo_sens,
        bdtopo_azimuth_du_projete::numeric(4,1),
        bdtopo_projete
    FROM (
        SELECT 
            p.id                                                      AS pano,
            t.cleabs                                                  AS bdtopo_troncon,
            (CASE
                WHEN t.sens_de_circulation='Sens inverse' THEN -1
                WHEN t.sens_de_circulation='Sens direct' THEN 1
                ELSE (CASE WHEN is_right(t.geometrie, p.geometrie) THEN 1 ELSE -1 END)
            END)                                                      AS bdtopo_sens,
            st_linelocatepoint(t.geometrie,p.geometrie)::numeric(3,2) AS bdtopo_position_sur_troncon,
            st_closestpoint(t.geometrie,p.geometrie)                  AS bdtopo_projete,
            (CASE
                WHEN t.sens_de_circulation = 'Sens direct' THEN 
                    linestring_azimuth_at_point(t.geometrie,p.geometrie)
                WHEN t.sens_de_circulation = 'Sens inverse' THEN
                    linestring_azimuth_at_point(ST_Reverse(t.geometrie),p.geometrie)
            ELSE
                CASE 
                    WHEN is_right(t.geometrie, p.geometrie) THEN
                        linestring_azimuth_at_point(t.geometrie,p.geometrie)
                    ELSE
                        linestring_azimuth_at_point(ST_Reverse(t.geometrie),p.geometrie)
                END
            END)                                                      AS bdtopo_azimuth_du_projete
        FROM (
            SELECT min(st_distance(t.geometrie, p.geometrie)) as min_distance
            FROM troncon_de_route_filtre t, pano_valide p
            WHERE ST_LineLocatePoint(t.geometrie,p.geometrie)::numeric(3,2) < 1
            AND ( 
                is_right(t.geometrie,p.geometrie) AND sens_de_circulation = 'Sens direct'
                OR
                (NOT is_right(t.geometrie,p.geometrie)) AND sens_de_circulation = 'Sens inverse'
                OR
                sens_de_circulation = 'Double sens'
            )
            GROUP BY p.id
        ) min_distance_table,
          troncon_de_route_filtre t, (
            SELECT v.*, s.road FROM pano_valide v LEFT JOIN pano s ON (v.id = s.id)
        ) p
        WHERE st_distance(t.geometrie, p.geometrie) = min_distance 
        -- AND ST_LineLocatePoint(t.geometrie,p.geometrie)::numeric(3,2) < 1
        -- AND ( 
        --     is_right(t.geometrie,p.geometrie) AND sens_de_circulation = 'Sens direct'
        --       OR
        --     (NOT is_right(t.geometrie,p.geometrie)) AND sens_de_circulation = 'Sens inverse'
        --       OR
        --     sens_de_circulation = 'Double sens'
        -- )
        -- AND t.nom_1_droite = replace(trim(split_part(p.road,'-',2)),'''',' ')
    ) t
);


-- ####################################################
-- update pano_valide.rattachements :
-- ####################################################
UPDATE pano_valide SET rattachements = json_object(
      '{
            bdtopo_troncon,
            bdtopo_position_sur_troncon,
            bdtopo_sens,
            bdtopo_azimuth_du_projete,
            bdtopo_projete
        }', array[
            bdtopo_troncon,
            bdtopo_position_sur_troncon::text,
            bdtopo_sens::text,
            bdtopo_azimuth_du_projete::text,
            ST_AsGeoJSON(bdtopo_projete)::text
        ]
)
FROM rattachements r
WHERE pano_valide.id = r.pano;

-- Renseignement arbitraire d'une valeur d'azimuth pour présenter un modèle complet
UPDATE pano_valide SET azimuth = (rattachements ->> 'bdtopo_azimuth_du_projete')::numeric;
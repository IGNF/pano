-- ####################################################
-- Schéma de la bdd test
-- ####################################################

-- Récupérer au préalable la table 'troncon_de_route' de la BDTopo
DROP TABLE IF EXISTS troncon_de_route_filtre CASCADE;
CREATE TABLE troncon_de_route_filtre AS (
    SELECT 
        cleabs AS cleabs,
        nom_rue_droite_valide AS nom_rue_droite_valide,
        nature AS nature,
        nom AS nom,
        etat_de_l_objet AS etat_de_l_objet,
        cpx_numero AS cpx_numero,
        sens_de_circulation AS sens_de_circulation,
        importance AS importance,
        nom_1_droite AS nom_1_droite,
        nom_2_droite AS nom_2_droite,
        ST_Transform(ST_SetSrid(ST_Force2D(geometrie),2154), 4326) AS geometrie

    FROM public.troncon_de_route
    WHERE NOT gcms_detruit
        AND importance <> '6'
        AND code_postal_droit = '95490'
);

-- Pour import du fichier 'pano.dataset.source.csv'
DROP TABLE IF EXISTS pano CASCADE;
CREATE TABLE pano (
    longitude numeric,
    latitude numeric,
    id integer,
    type_1 text,
    etat_1 text,
    type_2 text,
    etat_2 text,
    type_3 text,
    etat_3 text,
    type_4 text,
    etat_4 text,
    type_5 text,
    etat_5 text,
    type_6 text,
    etat_6 text,
    type_7 text,
    etat_7 text,
    road text,
    the_geom geometry
);

-- Création de la table cible
DROP TABLE IF EXISTS pano_valide CASCADE;
CREATE TABLE pano_valide (
    id integer primary key,
    code json,
    etat character varying (15),
    azimuth integer,
    rattachements json,
    producteur character varying(14),
    commentaire text,
    geometrie geometry(Point, 4326)
);

-- Création d'une table de rattachements pour les calculs intermédiaires
DROP TABLE IF EXISTS rattachements;
CREATE TABLE rattachements (
    pano integer,
    bdtopo_troncon character varying (24),
    bdtopo_position_sur_troncon numeric(3,2),
    bdtopo_sens integer,
    bdtopo_azimuth_du_projete numeric(4,1),
    bdtopo_projete geometry(Point, 4326)
);
ALTER TABLE rattachements ADD PRIMARY KEY (pano, bdtopo_troncon);

-- fonction qui dit si un point est situé à droite d'une ligne selon le sens de numérisation
CREATE OR REPLACE FUNCTION is_right(geometry(LineString,4326), geometry(LineString,4326)) RETURNS boolean AS $$
    SELECT ST_Contains(ST_Buffer($1, 10, 'side=right'), $2);
$$ LANGUAGE SQL IMMUTABLE;

-- fonction qui met la codification des panneaux du dataset source au format cible
CREATE OR REPLACE FUNCTION pano_clean_code(codes text[]) RETURNS json AS $$
    SELECT cast('{"' ||array_to_string(array_agg(
        split_part(ltrim(code),'-',1) ||
        '":"' ||
        replace(
            split_part(code,'-',2),
            'km/h',''
        )
    ), '","') || '"}' as json) FROM (
        SELECT unnest(codes) AS code
    ) t
$$LANGUAGE SQL IMMUTABLE;

-- Calcul de l'azimuth de la direction prise par une ligne en un point 
CREATE OR REPLACE FUNCTION linestring_azimuth_at_point(
    _line geometry(Linestring, 4326),
    _point geometry(Point, 4326)
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
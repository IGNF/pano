-- FUNCTION: public.compute_vla_estimee(character varying, geometry, character varying, boolean, character varying, character varying, character varying, character varying, character varying, character varying)

--DROP FUNCTION IF EXISTS public.compute_vla_estimee(character varying, geometry, character varying, boolean, character varying, character varying, character varying, character varying, character varying, character varying);
 
CREATE OR REPLACE FUNCTION public.compute_vla_estimee(
	cleabs character varying,
	geom geometry,
	nature character varying,
	urbain boolean,
	importance character varying,
	etat_de_l_objet character varying,
	acces_vehicule_leger character varying,
	nombre_de_voies character varying,
	nature_de_la_restriction character varying,
	sens_de_circulation character varying,
    cpx_classement_administratif character varying)
    RETURNS integer
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE 
    vraie_autoroute BOOLEAN;
BEGIN
 
-- Cas des troncons non praticables par un véhicule motorisé => vitesse nulle
IF (etat_de_l_objet <> 'En service'
    OR etat_de_l_objet IS NULL
    OR acces_vehicule_leger = 'Physiquement impossible'
    OR nature IN ('Escalier','Sentier')
    OR nature_de_la_restriction IN ('Voie verte', 'Aménagement mixte hors voie verte', 'Piste cyclable', 'Passage barré')
) THEN RETURN 0;
 
--  Cas spécifiques
ELSIF nature = 'Bac ou liaison maritime' THEN RETURN 5;
ELSIF nature = 'Bretelle' THEN RETURN 70;
 
-- Cas des troncons de type autoroutier
ELSIF nature = 'Type autoroutier' THEN 
    IF cpx_classement_administratif IN ('Autoroute', 'Autoroute/Route nommée') THEN
    -- vraie autoroute
        IF urbain THEN RETURN 90;
        ELSE return 130;
        END IF;
 
    ELSE --quasi autoroute
        IF urbain THEN RETURN 90;
        ELSE RETURN 110;
        END IF;
    END IF;
 
-- Route à double sens avec au moins 2 voies dans un même sens (voies rapides hors autoroute) → 90 km/h et 70 en zone urbaine
ELSIF (
    (sens_de_circulation = 'Double sens' AND nombre_de_voies IN ('4','5'))
    OR (sens_de_circulation IN ('Sens direct', 'Sens inverse') AND nombre_de_voies IN ('2','3','4','5'))
)
AND importance IN ('1','2')
AND nature != 'Type autoroutier'
THEN
    IF urbain THEN
        RETURN 70;
    ELSE
        RETURN 90;
    END IF;
 
-- Pour le reste : 80 hors agglo, 50 en agglo
ELSE
    IF urbain THEN RETURN 50;
    ELSE RETURN 80;
    END IF;
 
END IF;
END;
 
$BODY$;
 
ALTER FUNCTION public.compute_vla_estimee(character varying, geometry, character varying, boolean, character varying, character varying, character varying, character varying, character varying, character varying, character varying)
    OWNER TO postgres;


---- Tronçons du réseau départemental pour le rattachement des panneaux du CD44 -----
DROP TABLE IF EXISTS troncon_departemental;
CREATE TABLE troncon_departemental AS -- selection des champs de la BD Topo utiles au calcul de vitesse et à la navigation par la suite
	SELECT cleabs,
	nature,
	importance,
	urbain,
	etat_de_l_objet,
	acces_vehicule_leger,
	nombre_de_voies, 
	nature_de_la_restriction, 
	sens_de_circulation, 
	prive,
	cpx_numero,
	cpx_classement_administratif,
	position_par_rapport_au_sol, 
	fictif,
	largeur_de_chaussee,
	geom,
	compute_vla_estimee(cleabs,
        geom,
        nature,
        urbain,
        importance,
        etat_de_l_objet,
        acces_vehicule_leger,
        nombre_de_voies,
        nature_de_la_restriction,
        sens_de_circulation,
        cpx_classement_administratif) AS vla_estimee --calcul du champ vla_estimee
    FROM troncon_de_route_bdtopo
    -- Filtrage des tronçons praticables et candidats au rattachement + propagation des panneaux vitesse
	WHERE cpx_classement_administratif IN ('Départementale', 'Départementale/Route nommée')
  	AND etat_de_l_objet = 'En service'
 	AND nature NOT IN ('Escalier', 'Bac ou liaison maritime', 'Sentier')
 	AND (acces_vehicule_leger IS NULL
        OR acces_vehicule_leger != 'Physiquement impossible')
 	AND (nature_de_la_restriction IS NULL 
        OR nature_de_la_restriction != 'Piste cyclable');

---------- 5. Rattachement des panneaux aux segments ---------------------------------- 

--1. création d'une table de rattachement des panneaux aux segments

DROP TABLE IF EXISTS rattachement_cd44_segment;
CREATE TEMP TABLE rattachement_cd44_segment AS
 -- cas des panneaux de même tronçon initial 
WITH candidats AS (
  SELECT 
      p.id_panneau,       
      p.sens,
      s.id_segment,
	  s.sens_de_circulation,
      s.geom AS troncon_geom,
      p.panneau_projete,
      ST_StartPoint(s.geom) AS start_geom,
      ST_EndPoint(s.geom) AS end_geom
  FROM rattachement_cd44_optimise p
  JOIN troncon_departemental_decoupe s
ON s.cleabs = p.id_troncon)

SELECT id_panneau, id_segment, sens, panneau_projete as geom
FROM candidats
WHERE 
    (sens = '1' AND ST_Equals(start_geom, panneau_projete) -- si sens direct on le rattache au segment dont il est le start point
	 AND sens_de_circulation IN ('Double sens','Sens direct'))  -- on s'assure que le sens du panneau est bien compatible avec les sens de circulation possibles sur le tronçon
 OR 
    (sens = '-1' AND ST_Equals(end_geom, panneau_projete) -- si sens inverse on le rattache au segment dont il est le end point
	AND sens_de_circulation IN ('Double sens','Sens inverse'));


  -- cas des panneaux en extremités de tronçons initiaux différents
INSERT INTO rattachement_cd44_segment (id_panneau, id_segment, sens, geom)
	-- on sélectionne les panneaux non rattachés 
WITH  non_rattaches AS (
	SELECT p.*
	FROM rattachement_cd44_optimise p
	LEFT JOIN rattachement_cd44_segment r
	  ON p.id_panneau = r.id_panneau
	WHERE r.id_panneau IS NULL
	),
	-- On trouve les segments dont une extremite intersecte le panneau
candidats AS (
	    SELECT 
		  p.id_panneau,       
		  p.sens,
		  s.id_segment,
		  s.sens_de_circulation,
		  s.geom AS troncon_geom,
		  p.panneau_projete,
		  ST_StartPoint(s.geom) AS start_geom,
		  ST_EndPoint(s.geom) AS end_geom
	    FROM non_rattaches p
	    JOIN troncon_departemental_decoupe s
	      ON ST_Equals(ST_StartPoint(s.geom), p.panneau_projete)   -- cette fois on joint sur la géométrie et pas sur l'identifiant, 
	      OR ST_Equals(ST_EndPoint(s.geom), p.panneau_projete) 
	)
	
SELECT DISTINCT
    id_panneau,
    id_segment,
    sens,
    panneau_projete AS geom
FROM candidats
WHERE (sens = '1' AND ST_Equals(start_geom, panneau_projete) AND sens_de_circulation IN ('Double sens','Sens direct'))
   OR (sens = '-1' AND ST_Equals(end_geom, panneau_projete) AND sens_de_circulation IN ('Double sens','Sens inverse'));

 		-- => il n'en reste maintenant que 160 non rattachés : on considère que c'est négigeable dans ce cas


-- 2. On affecte la vitesse du panneau au segment auquel il est rattaché, dans le bon sens

	-- a. ajout de la vitesse dans la table de rattachement
ALTER TABLE rattachement_cd44_segment
ADD COLUMN vitesse varchar;   

UPDATE rattachement_cd44_segment r
SET vitesse = p.vitesse
FROM panneaux_vitesses_cd44_standard p   -- on le met a jour avec les valeurs de la table panneaux initiale
WHERE r.id_panneau = p.id_panneau;

	--	b. ajout des champs vla_sens_direct et vla_sens_inverse dans la table des troncons decoupes
ALTER TABLE troncon_departemental_decoupe
ADD COLUMN vla_sens_direct INTEGER,
ADD COLUMN vla_sens_inverse INTEGER,
ADD COLUMN source_vla_direct VARCHAR,
ADD COLUMN source_vla_inverse VARCHAR;

	-- c. On met à jour les champs vitesse_sens_direct / vitesse_sens_inverse seulement si l'extrémité a un seul panneau (car sauf erreur on ne peut pas avoir plusieurs panneaux à une extremité dans le meme sens)
		-- Table temporaire qui compte le nb de panneaux par extrémité
DROP TABLE IF EXISTS nb_panneau_extremite;
CREATE TEMP TABLE nb_panneau_extremite AS
SELECT id_segment, geom AS extremite_geom, COUNT(*) AS nb_panneaux
FROM rattachement_cd44_segment
GROUP BY id_segment, geom;


	-- vla_sens_direct
UPDATE troncon_departemental_decoupe t
SET vla_sens_direct = CASE
	WHEN r.vitesse ~ '^[0-9]+$' THEN r.vitesse::integer  -- on met la vitesse panneau convertie en entier
    WHEN r.vitesse like 'fin%' THEN vla_estimee  -- si la vitesse est un panneau fin de limitation on met la vla_estimee (retour à la vitesse par défaut)
    ELSE NULL
END,
   source_vla_direct = CASE
        WHEN r.vitesse ~ '^[0-9]+$' THEN 'Panneau'      -- on précise si la source de la vitesse est le panneau ou la vla_estimee
        WHEN r.vitesse LIKE 'fin%'  THEN 'Estimation'
        ELSE NULL
    END
FROM rattachement_cd44_segment r
JOIN nb_panneau_extremite e
  ON r.id_segment = e.id_segment
 AND r.geom = e.extremite_geom
WHERE r.sens = '1'
  AND t.id_segment = r.id_segment
  AND t.sens_de_circulation IN ('Sens direct','Double sens')
  AND e.nb_panneaux = 1;   -- on garde que les extremites avec un seul panneau

	-- vla_sens_inverse
UPDATE troncon_departemental_decoupe t
SET vla_sens_inverse = CASE
	WHEN r.vitesse ~ '^[0-9]+$' THEN r.vitesse::integer  
    WHEN r.vitesse like 'fin%' THEN vla_estimee
    ELSE NULL
END,
   source_vla_inverse = CASE
        WHEN r.vitesse ~ '^[0-9]+$' THEN 'Panneau'
        WHEN r.vitesse LIKE 'fin%'  THEN 'Estimation'
        ELSE NULL
    END
FROM rattachement_cd44_segment r
JOIN nb_panneau_extremite e
  ON r.id_segment = e.id_segment
 AND r.geom = e.extremite_geom
WHERE r.sens = '-1'
  AND t.id_segment = r.id_segment
  AND t.sens_de_circulation IN ('Sens inverse','Double sens')
  AND e.nb_panneaux = 1;


  

---------- Segmentation/surdécoupage des tronçons par les panneaux ---------------------

-- 1. Création des points de découpe avec les panneaux rattachés 
DROP TABLE IF EXISTS point_decoupe;
CREATE TEMP TABLE point_decoupe AS
SELECT DISTINCT ON (id_troncon, panneau_projete)  -- on supprime les doublons (rattachements jumeaux)
 id_panneau,
 id_troncon,
 panneau_projete as geom
FROM rattachement_cd44_optimise WHERE position_sur_troncon NOT IN (0,1);  -- on exclut les extrémités de troncon


-- 2. On crée les points pour recoller les segments après la découpe
DROP TABLE IF EXISTS snap_points;
CREATE TEMP TABLE snap_points AS
SELECT id_troncon, ST_Collect(geom) AS geom
FROM point_decoupe
GROUP BY id_troncon;
-- => 2850 points de recoupe


-- 3. Découper les tronçons par les points de découpe
DROP TABLE IF EXISTS troncon_decoupe;
CREATE TEMP TABLE troncon_decoupe AS
WITH decoupe AS (
  SELECT t.cleabs AS cleabs,
           ST_Difference(t.geom, ST_Collect(ST_Buffer(p.geom, 0.001))) -- on enlève de chaque troncon un buffer de 1 mm autour du panneau (ça fait des trous)
            AS geom
    FROM troncon_departemental t
    LEFT JOIN point_decoupe p
      ON t.cleabs = p.id_troncon
    GROUP BY t.cleabs, t.geom
)
SELECT cleabs, (ST_Dump(geom)).geom AS geom -- on recompose des géométries lignes
FROM decoupe;

-- 4. Recoller les extrémités sur les points de recoupe
DROP TABLE IF EXISTS troncons_decoupes_snap;
CREATE TEMP TABLE troncons_decoupes_snap AS
SELECT t.cleabs,ST_Snap(t.geom, s.geom, 0.001) AS geom
FROM troncon_decoupe t
LEFT JOIN snap_points s ON t.cleabs = s.id_troncon;


-- 5. Table finale avec réseau départemental surdécoupé

	-- Structure de la table
DROP TABLE IF EXISTS troncon_departemental_decoupe;
CREATE TABLE troncon_departemental_decoupe AS
SELECT *  FROM troncon_departemental;

 	-- On supprime les troncons qui ont été découpés 
DELETE FROM troncon_departemental_decoupe
WHERE cleabs IN (SELECT cleabs FROM troncons_decoupes_snap);  

	--  Insérer les bouts de troncons découpés dans la table des troncons decoupes
INSERT INTO troncon_departemental_decoupe (cleabs, nature, importance, urbain, etat_de_l_objet,
    acces_vehicule_leger, nombre_de_voies, nature_de_la_restriction,
    sens_de_circulation, prive, cpx_numero, cpx_classement_administratif,
    position_par_rapport_au_sol, fictif, largeur_de_chaussee, vla_estimee, geom
)
SELECT t.cleabs, t.nature, t.importance, t.urbain, t.etat_de_l_objet,
    t.acces_vehicule_leger, t.nombre_de_voies, t.nature_de_la_restriction,
    t.sens_de_circulation, t.prive, t.cpx_numero, t.cpx_classement_administratif,
    t.position_par_rapport_au_sol, t.fictif, t.largeur_de_chaussee, t.vla_estimee,
    ST_Force3D(s.geom)
FROM troncons_decoupes_snap s
JOIN troncon_departemental t
  ON s.cleabs = t.cleabs;

--  => on obtient 42 371 segments différents 41 638 géométries différentes

--  on ajoute un identifiant unique par segment
ALTER TABLE troncon_departemental_decoupe
ADD COLUMN id_segment serial PRIMARY KEY;




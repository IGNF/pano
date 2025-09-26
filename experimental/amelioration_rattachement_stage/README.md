# Contexte
Ce travail exploratoire a été réalisé dans le cadre d'un stage (avril-septembre 2025) avec pour objectif de réfléchir à l'élaboration d'une base de données routières navigable et souveraine (BD Nav) à partir de la BD Topo. Un enjeu principal de cette BD Nav est de pouvoir stocker une VLA (vitesse limite autorisée) associée aux tronçons de route, qui servira par la suite à dériver plusieurs vitesses selon différents profils. Cette VLA peut être obtenue à partir d'un calcul sur les attributs des tronçons ("VLA estimée"), ou bien à partir des panneaux de limitations de vitesses. Dans le cadre de la BD Nav, elle pourrait aussi être renseignée de manière collaborative par différents gestionnaires administratifs. 

Le passage d'une vitesse stockée dans une BD panneaux à une vitesse stockées par les tronçons dans la BD Nav constitue l'enjeu de la méthodologie proposée ici. 

La Loire Atlantique a été choisie comme zone de test car deux jeux de données de panneaux étaient disponibles sur les limitation de vitesse : ceux de la Métropole de Nantes et du CD 44. 


# Objectifs et principes
L'objectif est de construire une méthodologie pour obtenir une VLA panneau, ou estimation le cas échéant, au sein de la BD Nav. La table finale est une table de tronçons redécoupés par les panneaux et qui possèdent les attributs de la BD Topo utiles pour le calcul des vitesses réelles et le calcul d'itinéraires par la suite. Elle comprend aussi 4 nouveaux champs : vla_sens_direct, vla_sens_inverse qui stockent la VLA panneau ou estimation, et les champs source_vla_direct et source_vla_inverse qui indiquent la source de la vla obtenue.
Les grands principes de cette méthode sont les suivants :
- Rattachement des panneaux au réseau routier 
- Segmentation du réseau par les panneaux rattachés, après avoir optimisé le rattachement pour limiter les points de découpe
- Attribution des vitesses des panneaux à leur segment initial et dans la bonne direction
- Propagation des vitesses aux autres segment à partir des segments ayant une vitesse source : à travers un parcours de graphe en largeur (BFS)

Lorsque les panneaux indiquent une fin de limitation de vitesse, on attribue au segment la VLA estimée, calculée au préalable à partir des attributs des tronçons d'origine. Ainsi, les segments de la table finale se retrouvent tous, en théorie, avec une VLA dans les 2 sens, obtenue par panneau ou estimtation.


# Datasets

Panneaux : [panneaux_vitesse_cd44_standard.gpkg] (panneaux_vitesses_cd44_standard.gpkg)
Jeu de données déjà mis au modèle de la BD panneaux

Routes : [troncon_de_route_44](https://data.geopf.fr/telechargement/download/BDTOPO/BDTOPO_3-5_TRANSPORT_GPKG_LAMB93_FXX_2025-06-15/BDTOPO_3-5_TRANSPORT_GPKG_LAMB93_FXX_2025-06-15.7z)


# Installation des composants

Installation Postgresql (17) / Postgis, Python (version 3.13, venv)

# Intégration des datasets dans la base postgresql

Pre-requis : filtrer la table troncon_de_route du gpkg sur le département 44, créer une base postgresql, importer la table filtrée troncon_de_route du gpkg dedans sous le nom troncon_de_route_bd_topo (avec DB Manager sous QGIS).
Intégrer également la table panneaux_vitesse_cd44_standard.gpkg dans la base postgres.

# Lancement des scripts

## Préparation des données

### Filtrage des données BDTopo

script(s) : [1_filtrage_troncon_pour_rattachement](1_filtrage_troncon_pour_rattachement.sql)
inputs : table troncon_de_route_bdtopo
outputs : table troncon_departemental qui ne contient que les tronçons candidats au rattachement et à la propagation des vitesses des panneaux, et avec un nouveau champ vla_estimee calculé à partir d'autres attributs.


## Rattachement

### Rattachement à partir de données contenant la position et l'orientation des panneaux

script(s) : [rattachement_pano_troncon_bdtopo_correction7_valide](rattachement_pano_troncon_bdtopo_correction7_valide.sql)
inputs : 
outputs : 

### Rattachement à partir de données contenant le numéro de la route des panneaux

script(s) : [2_rattachement_panneaux_cd44.sql](2_rattachement_panneaux_cd44.sql)
inputs : tables paneaux_vitesses_cd44_standard et troncon_departemental
outputs : table rattachement_cd44


## Redécoupage du réseau par les panneaux


### Optimisation du rattachement

script(s) : [3_optimisation_rattachement.sql] (3_optimisation_rattachement.sql)
inputs : tables rattachement_cd44 et troncon_departemental
outputs : table rattachement_cd44_optimise

### Segmentation du réseau

script(s) : [4_segmentation_troncons.sql] (4_segmentation_troncons.sql)
inputs : tables rattachement_cd44_optimise et troncon_departemental
outputs : table troncon_departemental_decoupe avec les segments de tronçons découpés, reprend les attributs des troncons et ajoute un champ id_segment unique 

### Initialisation des vitesses sur les segments sources

script : [5_vitesse_segment_source.sql] (5_vitesse_segment_source.sql)
inputs : rattachement_cd44_optimise, panneaux_vitesses_cd44_standard, troncon_departemental_decoupe
outputs : table troncon_departemental_decoupe avec 2 nouveaux champs vla_sens_direct et vla_sens_inverse initialisés à partir des vitesses des panneaux pour les segments ayant un panneau rattaché, et 2 champs source_vla_direct et source_vla_inverse pour indiquer la source de la vla dans chaque sens.

## Propagation des vitesses sur le réseau

### Préparation du graphe
script : [6_preparation_graphe.sql] (6_preparation_graphe.sql)
inputs : table troncon_departemental_decoupe
outputs : table noeud correpondant aux extremites des tronçons et table arete correspondant aux tronçons définis par leur noeud de départ et leur noeud d'arrivée

### Propagation des vitesses dans le graphe

script: [7_propagation_vitesses.py] (7_propagation_vitesses.py)
inputs : table arete
outputs : table troncon_departemental_vla_finale contenant pour chaque segment de route, les attributs bd topo, la vla dans les deux sens et la source de la vla par sens
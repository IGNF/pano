#!/bin/bash

# Création du schéma du jeu de données expérimental
psql -d pano -f pano.schema.sql

# Peuplement de la table des données brute "pano"
psql -d pano -c "\COPY pano FROM '../data/pano.dataset.source.csv' CSV HEADER DELIMITER ';'"

# Peuplement de la table des panneaux dans le modèle cible
psql -d pano -f pano_valide.populate.sql

# Export des tables
psql -d pano -c "\COPY (SELECT *, ST_AsText(geometrie) AS wkt FROM pano_valide) TO pano_valide_complet.csv CSV HEADER DELIMITER ','"
psql -d pano -c "\COPY (SELECT *, ST_AsText(geometrie) AS wkt FROM troncon_de_route_filtre) TO troncon_de_route_filtre.csv CSV HEADER DELIMITER ','"
psql -d pano -c "\COPY (SELECT *, ST_AsText(bdtopo_projete) AS wkt FROM rattachements) TO rattachements.csv CSV HEADER DELIMITER ','"
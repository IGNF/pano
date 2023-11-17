### Concept de "zone de panneaux"  
Certains panneaux, répertoriés plus bas, portent une règlementation qui s'appliquent sur une zone. Une table `zone_panneau` est proposée pour matérialiser ces zones sous forme de polygones.
Il y a plusieurs avantages à créer des zones : 

- associer plus facilement une vitesse maximale autorisée (VMA) sur un ensemble de routes intersectées par la zone
- rendre les algorithmes de calcul de VMA moins sensible au réseau
- limiter l'impact de l'absence d'un panneau sur le résultat d'un calcul fait à partir des panneaux
- faciliter la visualisation des zones

Visualisation des panneaux de zones sans polygone : 
![image](https://github.com/IGNF/pano/assets/8489451/4b24b638-8834-45b5-ab16-d90fb9b8d61f)
... et avec des polygones "zone_panneau" : 
![image](https://github.com/IGNF/pano/assets/8489451/441e060f-af16-4243-9d60-c6bca6a0d9fd)

### Initialisation rudimentaire des zones panneaux 
```sql

DROP TABLE IF EXISTS traffic_sign_zone;
CREATE TABLE traffic_sign_zone (
	id serial primary key,
	name text,
	-- TODO filtrage concavehull de type point ou polyligne (les zones avec 1 ou 2 points...)
	geometry geometry(Geometry,4326)
);

INSERT INTO traffic_sign_zone ( name, geometry )
	SELECT t.name, ST_ConcaveHull(ST_Union(t.geom), 0.99) FROM (
		SELECT ("type" -> 'EB10') as name, geom FROM traffic_sign WHERE "type" ? 'EB10'
			UNION ALL
		SELECT ("type" -> 'EB20') as name, geom FROM traffic_sign WHERE "type" ? 'EB20'
	) t 
	WHERE t.name != '' AND t.name IS NOT NULL
	GROUP BY t.name
	;

```
### Modèle de `zone_panneau`
[lien vers le modèle](zone.pano.md)

### Contraintes d'intégrité en cas de mise à jour du tracé des limites de zone
Des contraintes d'intégrité peuvent être mises sur la base de critères géométriques : 
- un panneau de zone doit appartenir à une frontière de zone
- un panneau ne peut être déplacé

### Limite de cette initialisation

- Il faut avoir un moyen de regrouper les panneaux par appartenance à une même zone : c'est fait dans le cas précédent en utilisant la valeur portée par le panneau, à savoir le nom de l'agglomération mais tous les panneaux de zone ne portent pas de valeurs (zones 30 et zones de rencontre notamment).
- L'enveloppe concave faite par "ST_ConcaveHull" de postgis est arbitraire et ne correspond pas à la réalité terrain.
- il faut mettre à jour la zone à chaque fois qu'un panneau est ajouté

### Pistes d'amélioration

- croiser avec des données OCS pour avoir un meilleur résultat en initialisation automatique
- développer des interfaces pour réduire le temps opérateur de modification du tracé des limites des zone


### Liste des panneaux "de zone" :  

- {type: EB10, value: <nom_agglo>} : entrée d'agglomération
- {type: EB20, value: <nom_agglo>} : sortie d'agglomération
- {type: B30} : entrée de zone 30
- {type: B51} : sortie de zone 30
- {type: B52} : entrée de zone de rencontre
- {type: B53} : sortie de zone de rencontre
- ...?

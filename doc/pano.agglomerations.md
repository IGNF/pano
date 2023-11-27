# Concept de "zone de panneaux" 

## Contexte

En développant un algorithme de calcul d'une base des vitesses limites autorisée à partir d'un réseau routier et de de panneaux, il est apparu que :

* Il était délicat d'avoir une couverture exhaustive des entrées/sorties de villes (EB10 / EB20)
* Les limitations à 50 km/h avaient tendances à "déborder" très loin des villes (vu que les règles de cheminements sont différentes pour ces panneaux zonaux : pas d'arrêt sur les intersections,...)

Il a été jugé utile de matérialiser les zones entourées par ces EB10 / EB20 par des polygones et d'affecter la limitation de vitesse aux tronçons inclus dans la zone pour avoir de meilleurs résultats. Une table `zone_panneau` est proposée pour matérialiser ces zones sous forme de polygones.

Il y a plusieurs avantages à créer des zones : 

* Associer plus facilement une vitesse maximale autorisée (VMA) sur un ensemble de routes intersectées par la zone
* Rendre les algorithmes de calcul de VMA moins sensible au réseau
* Limiter l'impact de l'absence d'un panneau sur le résultat d'un calcul fait à partir des panneaux
* Faciliter la visualisation des zones

## Illustration de la matérialisation des zones

### Visualisation des panneaux de zones sans polygone

![image](https://github.com/IGNF/pano/assets/8489451/4b24b638-8834-45b5-ab16-d90fb9b8d61f)

### Visualisation des panneaux et des polygones "zone_panneau" :

![image](https://github.com/IGNF/pano/assets/8489451/441e060f-af16-4243-9d60-c6bca6a0d9fd)

## Modèle de `zone_panneau`

[lien vers le modèle](zone.pano.md)

## Initialisation des polygones "zone_panneau"

En première approche, il est possible d'**initialiser les zones par calcul d'une enveloppe concave** :

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

## Limite de cette initialisation

* Il faut avoir un moyen de regrouper les panneaux par appartenance à une même zone : c'est fait dans le cas précédent en utilisant la valeur portée par le panneau, à savoir le nom de l'agglomération mais tous les panneaux de zone ne portent pas de valeurs (zones 30 et zones de rencontre notamment).
* L'enveloppe concave faite par "ST_ConcaveHull" de postgis est arbitraire et ne correspond pas à la réalité terrain.
* Il faut mettre à jour la zone à chaque fois qu'un panneau est ajouté

## Contraintes d'intégrité en cas de mise à jour du tracé des limites de zone

Il demeure possible et relativement simple de valider visuellement les polygones et de les modifier. Des contraintes d'intégrité peuvent alors être mises sur la base de critères géométriques :

* Un panneau de zone doit appartenir à une frontière de zone
* Un panneau ne peut être déplacé

## Pistes d'amélioration pour l'initialisation

* Croiser avec des données OCS pour avoir un meilleur résultat en initialisation automatique
* Développer des interfaces pour réduire le temps opérateur de modification du tracé des limites des zone

## Liste des panneaux "de zone" :  

- {type: EB10, value: <nom_agglo>} : entrée d'agglomération
- {type: EB20, value: <nom_agglo>} : sortie d'agglomération
- {type: B30} : entrée de zone 30
- {type: B51} : sortie de zone 30
- {type: B52} : entrée de zone de rencontre
- {type: B53} : sortie de zone de rencontre
- ...?

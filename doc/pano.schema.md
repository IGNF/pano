# PANO

## Schéma des panneaux de signalisation routière

Spécification du format pivot de production et diffusion des données relatives aux panneaux de signalisation routière

| Nom de l'attribut | Type    | Obligatoire (O/N) | Description                                                                                                                                                          |
| ----------------- | ------- | ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| id                | integer | N                 | Identifiant unique du panneaux                                                                                                                                       |
| code              | object  | N                 | Les codes du panneau et de ses panonceaux selon la codification officielle ainsi que l'inscription qu'ils portent sont contenus dans un objet JSON                   |
| etat              | string  | N                 | L'état de détérioration du panneau                                                                                                                                   |
| azimuth           | integer | N                 | Angle en degrés entre la direction du panneau dans son axe de lecture et le nord. Indique la direction vers laquelle l'information portée par le panneau s'applique. |
| rattachements     | object  | N                 | Référence le tronçon de route sur lequel s'applique la directive inscrite sur le panneau.                                                                            |
| producteur        | string  | N                 | Information identifiant le producteur de la donnée                                                                                                                   |
| commentaire       | string  | N                 | Champ libre pour toute remarque utile concernant le panneau                                                                                                          |
| geometrie         | geojson | N                 | Représentation du panneau par une géométrie de type "Point" dans le système de coordonnées géographiques WGS84 et au format GeoJSON                                  |


# public

## Extension possible du schéma PANO

Proposition d'extensions au schéma PANO à discuter

| Nom de l'attribut | Type    | Obligatoire (O/N) | Description                                                                                                                                |
| ----------------- | ------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| numero_route      | string  | N                 | Motif de l'extension : Aide à désambiguïsation dans la recherche d'un rattachement au réseau routier                                       |
| nom_rue           | string  | N                 | Motif de l'extension : Aide à désambiguïsation dans la recherche d'un rattachement au réseau routier                                       |
| nature_route      | string  | N                 | Motif de l'extension : Aide à désambiguïsation dans la recherche d'un rattachement au réseau routier                                       |
| date_apparition   | date    | N                 | Date la plus ancienne à laquelle on peut attester de la présence du panneau sur le terrain. Motif de l'extension : indice de fiabilité     |
| date_confirmation | date    | N                 | Date la plus récente à laquelle on peut peut attester de la présence du panneau sur le terrain. Motif de l'extension : indice de fiabilité |
| date_creation     | date    | N                 | Date informatique de création de la donnée. Motif de l'extension : historisation de la donnée                                              |
| date_modification | date    | N                 | Date informatique de dernière modification de la donnée. Motif de l'extension : historisation de la donnée                                 |
| detruit           | boolean | N                 | Indique si l'objet est détruit ou non. Motif de l'extension : historisation de la donnée                                                   |


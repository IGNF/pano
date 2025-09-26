import pandas as pd
import geopandas as gpd
import networkx as nx
from sqlalchemy import create_engine
from collections import deque
from shapely.geometry import LineString
from geoalchemy2 import Geometry

# Connexion à ma base de données
db_url = "postgresql://postgres:postgres@localhost:5432/postgres"
engine = create_engine(db_url)


# Chargement de la table d'aretes
arete = gpd.read_postgis("SELECT * FROM arete", con=engine, geom_col='geom')


# 1. Création du graphe orienté à partir des arêtes
G = nx.DiGraph()

for _, row in arete.iterrows():
    # ajout des arêtes en sens direct
    if row['sens_de_circulation'] in ('Sens direct', 'Double sens'):
        G.add_edge(
            int(row['source_id']),  # pt de départ (sens de circulation = sens de numérisation initial)
            int(row['target_id']),   # pt d'arrivée 
            id_segment=row['id_segment'],
            sens="Sens direct",
            vitesse=row.get('vla_sens_direct'), # on lui attribut la vitesse du panneau rattaché
            source_vla=row.get('source_vla_direct'), # on lui attribut la source vla
            vla_estimee=row.get('vla_estimee'), 
            geom=row['geom']
        )

    # Ajout des arêtes en sens inverse
    if row['sens_de_circulation'] in ('Sens inverse', 'Double sens'):
        G.add_edge(
            int(row['target_id']),    # le end point du sens de numérisation devient le point de départ
            int(row['source_id']),    
            id_segment=row['id_segment'],
            sens = "Sens inverse",
            vitesse=row.get('vla_sens_inverse'),
            source_vla=row.get('source_vla_inverse'),
            vla_estimee=row.get('vla_estimee'),
            geom=row['geom']
        )

    # statistiques: compter le nombre d'arêtes avec une vitesse panneau avant propagation
avant = sum(
    1 for _, _, d in G.edges(data=True)
    if pd.notna(d.get('vitesse'))
)
print("Arêtes avec vitesse avant propagation :", avant)

    # et le nombre total d'arêtes dans le graphe
print(f"Nombre total d'arêtes : {G.number_of_edges()}")


# 2. Propagation des vitesses (selon une logique de parcours en largeur : BFS)

    # On récupère les arêtes qui ont déjà une vitesse panneau
edge_source = [(u, v, d) for u, v, d in G.edges(data=True) if pd.notna(d.get('vitesse'))]


def propage_vitesse(G, edge_source):       
    ok_edges = set()  # ensemble des arêtes déjà parcourues
    file = deque() # file de type FIFO
    
    # Boucle pour initialiser la file avec toutes les arêtes sources
    for u, v, data in edge_source:
        speed = data['vitesse']
        source = data['source_vla'] 
        ok_edges.add((u, v))  # on met l'arête source dans les arêtes déjà traitées
        file.append((u, v, speed, source)) # on l'ajoute à la file pour propager à partir d'elle 
        # => on propage à partir de toutes les arêtes sources, niveau par niveau
    
    # parcours BFS 
    while file:
        x, y, spd, src = file.popleft()  # on sort une arête x -> y de la file pour la traiter
        for succ in G.successors(y): # pour chaque arête au départ de y
            if (y, succ) not in ok_edges: # si arête n'est pas déjà traitée
                edge_data = G.get_edge_data(y, succ)
                if pd.isna(edge_data.get('vitesse')):# donc si vitesse nulle
                    G[y][succ]['vitesse'] = spd # on lui assigne la vitesse de l'arête précédente (x -> y)
                    G[y][succ]['source_vla'] = src # et également sa source vla 
                    ok_edges.add((y, succ))  # on l'ajoute aux arêtes déjà traitées
                    file.append((y, succ, spd, src)) # on l'ajoute à la file (pour continuer à propager au niveau suivant)


# appel  de la fonction de propagation des vitesses
propage_vitesse(G, edge_source)

#statistiques
print(f"Nombre total d'arêtes avec une vitesse après propagation : "f"{sum(1 for _, _, d in G.edges(data=True) if pd.notna(d.get('vitesse')))}")


# 3. Création de la table finale qui regroupe par id_segment les segments qui ont été dédoublés

    # on extrait les arêtes du graphe dans un df
edges_list = []
for u, v, data in G.edges(data=True):
    edges_list.append({
        'id_segment': data['id_segment'],
        'sens': data['sens'],
        'vitesse': data['vitesse'],
        'source_vla': data.get('source_vla'),
        'geom': data['geom']
    })
df_edges = pd.DataFrame(edges_list)

    # on regroupe les aretes de même id_segment avec un pivot
df_vla = df_edges.pivot(index='id_segment', columns='sens', values='vitesse')  # une seule ligne par id_segment et on met les valeurs de 'sens' en colonne
df_vla = df_vla.rename(columns={
    'Sens direct': 'vla_sens_direct',
    'Sens inverse': 'vla_sens_inverse'
}).reset_index()

    # on regroupe aussi les sources vla
df_source = df_edges.pivot(index='id_segment', columns='sens', values='source_vla')
df_source = df_source.rename(columns={
    'Sens direct': 'source_vla_direct',
    'Sens inverse': 'source_vla_inverse'
}).reset_index()

    # on fusionne les 2 pivots dans un df avec id_segment unique
df_final = pd.merge(df_vla, df_source, on='id_segment', how='outer')


    # Enfin on fusionne avec la table arete d'origine
troncon_vla_finale = arete.drop(columns=['vla_sens_direct','vla_sens_inverse','source_vla_direct','source_vla_inverse','vla_estimee', 'source_id', 'target_id']) # on supprime les colonnes qu'on a màj
troncon_vla_finale = pd.merge(troncon_vla_finale, df_final, on='id_segment', how='left') # on remet les colonnes mises à jour grâce à une jointure avec df_final

# 4. Exportation vers postgis
table_name = "troncon_departemental_vla_finale"
troncon_vla_finale.to_postgis(table_name, con=engine, if_exists='replace', index=False)


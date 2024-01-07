import pandas as pd
import numpy as np
from mlxtend.frequent_patterns import apriori
from mlxtend.frequent_patterns import association_rules
import os
    
# ---------------------------- #
#          OBJECTIVE           #
# ---------------------------- #

# Input -> Playlists with one or several genre keywords
# Output -> Association rules using tag genre to map relevant genre for all playlists

# ---------------------------- #
#       DATA PREPARATION       #
# ---------------------------- #

# mood keywords and relevant genres
moods = {'mood', 'fuzzy', 'feel', 'rage', 'anger', 'angry', 'annoying', 'aggresive', 'interest', 'interesting', 'optimism', 'optimistic', 'ecstasy', 'joy', 'serenity', 'love', 'trust', 'acceptance', 'accepting', 'submission', 'terror', 'fear', 'awe', 'amaze', 'amazing', 'surprise', 'surprising', 'distraction', 'distracting', 'grief', 'sadness', 'sad', 'pensiveness', 'pensive', 'remorse', 'loathing', 'disgust', 'boredom', 'boring', 'bored', 'chill', 'active', 'cheerful', 'reflective', 'gloomy', 'humorous', 'humor', 'melancholy', 'romantic', 'mysterious', 'ominous', 'calm', 'lighthearted', 'hope', 'hopeful', 'fearful', 'tense', 'lonely', 'alone', 'happy', 'good', 'bad', 'suave', 'vibe', 'breakup', 'depressed', 'depression', 'emo', 'bored', 'heart broken'}
genres = {'blues','classical','country','edm','dance','funk','hiphop','indie','jazz','pop','rnb','rock'}

# read data
print("import data")
playlists = pd.read_csv('../data/df_playlists.csv') 
playlists_idtags = playlists[['id', 'genre']].drop_duplicates() #In case there is duplicated playlists

# prepare dataset, we need the data that each row has separate genre
def separate_genre_labels(playlist_df):
    playlist_genre = []
    for index, row in playlist_df.iterrows():
        targeted_genre = playlist_df.loc[index, "genre"]
        continue_in_code_step1=False
        if('str' in str(type(targeted_genre))): continue_in_code_step1 = True
        if('float' in str(type(targeted_genre))): continue_in_code_step1 = False
        
        if continue_in_code_step1 == False: continue

        if len(targeted_genre) > 0:
            for genre in targeted_genre.split(","): 
                    playlist_genre.append({
                        "id": playlist_df.loc[index, "id"],
                        "genre": genre.lower().strip()})
    return pd.DataFrame(playlist_genre)

playlists_df = separate_genre_labels(playlists_idtags)

# remove leading and trailing spaces and hyphens
playlists_df['genre'] = playlists_df['genre'].apply(lambda x: x.strip(" ")).apply(lambda x: x.replace("-", " "))

# create a random sample of playlists  for learning
np.random.seed(1) # for reproducbility (every time the same sample and thus identical association rules)
df_ids = playlists_df['id'].unique()
df_sample_ids = np.random.choice(df_ids, 5)
df_sample = playlists_df[playlists_df.id.isin(df_sample_ids)]

# turn data into pivot table as input for association rule mining (rows: playlists, columns: genre)
basket_sample = (df_sample.groupby(['id', 'genre'])['id']
   .count().unstack().reset_index().fillna(0)
   .set_index('id', drop=True))

# --------------------------------------- #
#       FIND MOODS-RELATED PLAYLIST      #
# ------------------------------------- #

def moods_playlists(moods):
    '''identify moods playlists from playlist names (i.e., check if keywords appear in the playlist name)'''
    output = pd.DataFrame()
    
    for tag in moods:
        matches = playlists[playlists.name.str.match(tag + "$|" + tag + "[ ]") == True].copy()
        if 'mood' in moods:
            matches['cluster'] = 'mood'
        output = pd.concat([output, matches]).reset_index(drop=True)
    return output[['id', 'cluster']]

# determine playlist ids related to moods
moods_matches = moods_playlists(moods) 
print("identified " + str(len(moods_matches)) + " moods playlists")


# ---------------------------- #
#   ASSOCIATION RULE MINING    #
# ---------------------------- #

def tag_word_analysis(basket, genre, min_confidence, min_support):
    ''''
    1. select all playlists that contain a given main genre (e.g., pop)
    2. derive association rules of length 2, of which the lift exceeds 1, the confidence is greater than 90%, and the support exceeds a given level
    3. consider association rules of which the consequent is the main genre (e.g., dance pop -> pop)
    '''
    tag_cluster = pd.DataFrame()

    basket_genre = basket[basket[genre] == 1] # all playlists that contain the main genre
    frequent_itemsets = apriori(basket_genre, min_support=min_support, use_colnames=True, max_len=2)
    rules = association_rules(frequent_itemsets, metric='lift', min_threshold=1).sort_values(['confidence', 'support'], ascending=False).reset_index(drop=True)
    rules = rules.loc[rules['confidence'] >= min_confidence, ['antecedents', 'consequents']]

    # restructure frozen set 
    for counter in range(len(rules)):
        antecedent, = rules.loc[counter, 'antecedents']
        consequent, = rules.loc[counter, 'consequents']
        if consequent == genre and antecedent not in genres: 
            tag_cluster_temp = pd.DataFrame([[antecedent, genre], [genre, genre]], columns=['genre', 'cluster'])
            tag_cluster = pd.concat([tag_cluster_temp, tag_cluster])
    tag_cluster = tag_cluster.drop_duplicates()
    
    return tag_cluster
    
# determine association rules within each main genre (note that one tagword may be associated with multiple clusters (e.g., soft rock -> rock & soft rock -> pop))
min_support=0.2 # changing the support level has a major impact on the outcomes (higher support = fewer association rules = fewer clusters)
min_confidence = .90
print("starting association rule mining with minimum confidence of " + str(min_confidence) + " and minimum support of " + str(min_support))
tag_clusters = pd.concat([tag_word_analysis(basket_sample, genre, min_support=min_support, min_confidence=min_confidence) for genre in genres])
print("With association rule mining with minimum confidence of " + str(min_confidence) + " and minimum support of " + str(min_support) + ", We get " + str(len(tag_clusters)) + " total association rules " + "for " + str(len(tag_clusters.cluster.unique())) + " clusters")
print("The final cluster includes " + str(tag_clusters.cluster.unique()))


# ------------------------------- #
#  ASSIGN PLAYLISTS TO CLUSTERS   #
# ------------------------------- #

# add clusters to all playlists df
df_cluster = pd.merge(playlists_df,tag_clusters, left_on='genre', right_on='genre')[['id', 'genre', 'cluster']]

    
# calculate number of playlists without any cluster (because none of the tagwords are related to any of the association rules; choosing a lower minimum support level will remedy this problem to a certain extent)
all_playlists = len(playlists_idtags.id.unique())
num_playlists_output = len(df_cluster.id.unique())
print("{0:.1f}% of all playlists is not assigned to any cluster".format((all_playlists - num_playlists_output) / all_playlists * 100))

# reshape data frame (rows: playlists, columns: clusters + mood)
playlist_cluster = pd.concat([moods_matches, df_cluster[['id', 'cluster']]]).drop_duplicates()
playlist_cluster['values'] = 1
df_pivot = playlist_cluster.pivot(index='id', columns='cluster', values='values').fillna(0)
#This returns the df (long-to-wide) with column: playlist_id, section_1, section_2,..., section_n meaning that one playlist can fit several main sectionName


# ------------------------------- #
#       CLUSTER STATISTICS		  #
# ------------------------------- #

# The number of followers is 'object' and for now we are interested in the number of playlist and its percentage to total dataframe

def calculate_cluster_indices(df_pivot):
    return {column: df_pivot.index[(df_pivot[column ] == 1)].tolist() for column in df_pivot.columns}


def cluster_stats(df_pivot, playlists):
    # collect playlist ids for each label
    cluster_indices = calculate_cluster_indices(df_pivot)

    # calculate number of followers and market share for each cluster
    cluster_stats = pd.DataFrame()
    for keys, values in cluster_indices.items():
        cluster_temp = pd.DataFrame({'label':keys, 
                                'num_playlists':len(values)}, 
                               index=[0])
        cluster_stats = pd.concat([cluster_temp, cluster_stats])
    
    cluster_stats['perc_playlists'] = cluster_stats['num_playlists'] / len(df_pivot) * 100
    print(cluster_stats.sort_values('perc_playlists', ascending=False).reset_index(drop=True))
    return cluster_stats


clusters_stats = cluster_stats(df_pivot, playlists)

# ------------------------------- #
#          EXPORT RESULTS         #
# ------------------------------- #

# WE GO FOR 1, 90%

#Make output directory
path = '../gen'
try:
    os.mkdir(path)
except:
    print('dir exists')
    
#Exportfile
df_pivot.to_csv(path + "/df_playlists_cluster.csv")

%reset -f

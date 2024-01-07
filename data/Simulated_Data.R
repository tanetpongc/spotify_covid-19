#Simulated Scanner Data
set.seed(1234567)

library(data.table)

#################################################
########## SIMULATE PLAYLIST INFO DATA ##########
#################################################


curator = c("Spotify","MajorLabel","Indie","Professional","User")
percentile = c("top1%","top10%","top30%","tail")

music_tags <- c("Rock", "Pop", "Jazz", "Blues", "Classical", 
                  "hiphop", "Country", "Dance",
                  "Reggae", "Folk", "Soul", "Metal", "RnB", 
                  "Punk", "Latin", "Gospel", "Funk", 
                  "WorldMusic", "Indie", "EDM",
                "SwedishHouse", "Alternative", 'K-pop'
                ) 

playlist_common_words <- c("Echoes", "Groove", "Twilight", "Odyssey", "Harmony", 
                    "Pulse", "Dream", "Vibe", "Journey", "Mystic", 
                    "Chill", "Beats", "Serenity", "Breeze", "Fusion", 
                    "Rhythm", "Bliss", "Soul", "Radiance", "Eclipse", 
                    "Wanderlust", "Zenith", "Reverie", "Cosmos", "Nebula", 
                    "Horizon", "Euphoria", "Aurora", "Melody", "Celestial",
                    "Github","Simulated", "Test", "Repository")

moods <- c('NA','Non-mood','mood', 'fuzzy', 'feel','angry', 'ecstasy', 'joy', 'surprise', 'lonely', 'happy', 'good', 'bored', 'heart broken', '')


# Create a data table
num_ids <- 500
num_weeks <- 50

# Functions for generating playlist names and genres
pick_tags <- function(tags) {
  n <- sample(1:length(tags), 1)  # Randomly pick the number of genres to select
  sample(tags, n)                # Randomly select 'n' genres from the list
}

generate_playlist_name <- function() {
  word <- sample(moods, 1)  # Randomly pick an additional word (or none)
  playlist_word <- sample(playlist_common_words, 1)  # Randomly pick a genre word
  if (word != "") {
    playlist_name <- paste(word, playlist_word, "Simulated Playlist")
  } else {
    playlist_name <- paste(playlist_word, "Simulated Playlist")
  }
  return(playlist_name)
}

# Create a data.table
dt_playlists <- data.table(id = 1:num_ids)

# Add playlist_name and genre columns
dt_playlists[, name := sapply(1:.N, function(x) generate_playlist_name())]
dt_playlists[, genre := sapply(1:.N, function(x) paste(pick_tags(music_tags), collapse = ", "))]
dt_playlists[, curator := sapply(1:.N, function(x) sample(curator, 1))]
dt_playlists[, percentile := sapply(1:.N, function(x) sample(percentile, 1))]


#################################################
########## WEEKLY COLLECTED DATA BY ID ##########
#################################################

# Function to generate weekly followers for one id
generate_weekly_followers_for_id <- function(id) {
  followers <- numeric(num_weeks)
  followers[1] <- sample(1:100000, 1)  # Starting point
  
  for (week in 2:num_weeks) {
    # Controlled fluctuation
    fluctuation <- sample(-1000:1000, 1)
    next_followers <- max(1, min(100000, followers[week - 1] + fluctuation))
    followers[week] <- next_followers
  }
  
  return(followers)
}

# Function to generate MLShare values for one id
generate_weekly_mlshare_for_id <- function(id) {
  mlshare <- numeric(num_weeks)
  mlshare[1] <- runif(1, 0, 1)  # Starting point
  
  for (week in 2:num_weeks) {
    # Controlled fluctuation (smaller to ensure less variance)
    fluctuation <- runif(1, -0.05, 0.05)
    next_mlshare <- max(0, min(1, mlshare[week - 1] + fluctuation))
    mlshare[week] <- next_mlshare
  }
  
  return(mlshare)
}

# Function to generate ntracksotherpl values for one id
generate_weekly_ntracksotherpl_for_id <- function(id) {
  ntracksotherpl <- numeric(num_weeks)
  ntracksotherpl[1] <- sample(1:5000, 1)  # Starting point
  
  for (week in 2:num_weeks) {
    # Controlled fluctuation (smaller to ensure less variance)
    fluctuation <- sample(-250:250, 1)
    next_ntracksotherpl <- max(1, min(5000, ntracksotherpl[week - 1] + fluctuation))
    ntracksotherpl[week] <- next_ntracksotherpl
  }
  
  return(ntracksotherpl)
}

# Create a data table for all ids and weeks
dt_weekly <- data.table(id = rep(1:num_ids, each = num_weeks),
                 week = rep(1:num_weeks, times = num_ids),
                 followers = unlist(lapply(1:num_ids, generate_weekly_followers_for_id)),
                 MLShare = unlist(lapply(1:num_ids, generate_weekly_mlshare_for_id)),
                 ntracksotherpl = unlist(lapply(1:num_ids, generate_weekly_ntracksotherpl_for_id)),
                 feature = sample(0:1, num_ids * num_weeks, replace = TRUE))


write.csv(dt_playlists,"df_playlists.csv", row.names = TRUE)
write.csv(dt_weekly,"df_weekly.csv", row.names = TRUE)

rm(list=ls())

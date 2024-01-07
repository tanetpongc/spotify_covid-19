#####################################
# Import Necessary Library and Data #
#####################################
library(data.table) 
library(ggplot2)
library(plm)
library(car) #deltaMethod

playlist_df <- fread("../data/df_playlists.csv")
playlist_weekly_df <- fread("../data/df_weekly.csv") 
playlist_cluster <- fread("../gen/df_playlists_cluster.csv") #use wide-format table for merging with assigned category

###################################################################
#    MERGE RELEVANT DATASETS AND VARIABLE  OPERATIONALIZATION     #
###################################################################
# Create covid step variable, include=FALSE}
playlist_weekly_df[, covid_step:= ifelse(week >= 30, 1, 0)]

# Imposing category
# Create key of id and playlist_id for merging
playlistcluster_df <- merge(playlist_cluster,playlist_df, by="id")
df <- playlist_weekly_df[playlistcluster_df, on = c("id"), nomatch = 0L] #nomatch = 0L argument ensures that only matching rows are returned (similar to a left join in SQL)

df[, id := as.factor(id)]
df[, week := as.factor(week)]
df[, covid_step := as.factor(covid_step)]
df[, curator := as.factor(curator)]
df[, curator := relevel(curator, ref = "Spotify")]
df[, percentile := as.factor(percentile)]
df[, percentile := factor(percentile, levels = c("top1%","top10%","top30%","tail"))] #So the graph shows nicely

rm(list = c("playlist_df","playlist_weekly_df", "playlist_cluster", "playlistcluster_df"))

#Create grand mean centering for category factor to avoid confusing interpretation related to genre
genres <- c('mood','blues','classical','country','edm','dance','funk','hiphop','indie','jazz','pop','rnb','rock')

for (i in genres) df[, paste0(i,'_mc'):=get(i)-mean(get(i))]

#Create relevant variables (first difference)
df[, log_followers := log(followers+1)]
setorder(df, id, week)
lag_1 <- function(x, k = 1) head(c(rep(NA, k), x), length(x))
df[, dlog_followers := log_followers-lag_1(log_followers), by = c('id')]
df[, dmlshare := MLShare-lag_1(MLShare), by = c('id')] 
df[, dlog_trackshare := log(ntracksotherpl)-log(lag_1(MLShare)), by = c('id')]

##############################
#    MODEL FREE EVIDENCE     #
##############################
#MLShare
df[, MLSharegroup := cut(MLShare, breaks = c(0, 0.2, 0.4, 0.6, 0.8, 1), 
                                 labels = c("To 20%", "20% - 40%", "40% - 60%", "60% - 80%", "80% - 100%"), 
                                 include.lowest = TRUE)]
df_summary_byMLshare <- df[, .(followers_mean = mean(dlog_followers, na.rm = TRUE),
                     followers_se = sd(dlog_followers, na.rm = TRUE) / sqrt(.N)), 
                 by = .(week, MLSharegroup)]
df_summary_byMLshare[, week := as.numeric(as.character(week))]

ggplot(df_summary_byMLshare, aes(x = week, y = followers_mean, color = MLSharegroup)) + 
  geom_line() +  # Line plot for the means
  geom_point() + 
  geom_errorbar(aes(ymin = followers_mean - followers_se, ymax = followers_mean + followers_se), width = 0.2) +
  geom_vline(xintercept = 30, linetype = "dashed", color = "red", size = 1.2) +
  labs(
    x = "Week",
    y = "Follower Growth (Dlogfollowers)",
    color = "% of MLShare in Track",
    title = "Weekly Change of Followers by Week and Size of MLShare"
  ) +
  theme_minimal()

#Curator
df_summary_bycurator <- df[, .(followers_mean = mean(dlog_followers, na.rm = TRUE),
                     followers_se = sd(dlog_followers, na.rm = TRUE) / sqrt(.N)), 
                 by = .(week, curator)]
df_summary_bycurator[, week := as.numeric(as.character(week))]

ggplot(df_summary_bycurator, aes(x = week, y = followers_mean, color = curator)) + 
  geom_line() +  # Line plot for the means
  geom_point() + 
  geom_errorbar(aes(ymin = followers_mean - followers_se, ymax = followers_mean + followers_se), width = 0.2) +
  geom_vline(xintercept = 30, linetype = "dashed", color = "red", size = 1.2) +
  labs(
    x = "Week",
    y = "Follower Growth (Dlogfollowers)",
    color = "Curator",
    title = "Weekly Change of Followers by Week and Curator"
  ) +
  theme_minimal()

#Percentile
df_summary_bypercentile <- df[, .(followers_mean = mean(dlog_followers, na.rm = TRUE),
                               followers_se = sd(dlog_followers, na.rm = TRUE) / sqrt(.N)), 
                           by = .(week, percentile)]
df_summary_bypercentile[, week := as.numeric(as.character(week))]

ggplot(df_summary_bypercentile, aes(x = week, y = followers_mean, color = percentile)) + 
  geom_line() +  # Line plot for the means
  geom_point() + 
  geom_errorbar(aes(ymin = followers_mean - followers_se, ymax = followers_mean + followers_se), width = 0.2) +
  geom_vline(xintercept = 30, linetype = "dashed", color = "red", size = 1.2) +
  labs(
    x = "Week",
    y = "Follower Growth (Dlogfollowers)",
    color = "percentile",
    title = "Weekly Change of Followers by Week and Playlist Percentile"
  ) +
  theme_minimal()


###################################
#     FIXED EFFECT ESTIMATION     #
###################################
m <- plm(dlog_followers ~ covid_step + covid_step*curator + covid_step*percentile 
         + covid_step*mood_mc + covid_step*blues_mc + covid_step*classical_mc + covid_step*country_mc 
         + covid_step*edm_mc + covid_step*dance_mc  + covid_step*funk_mc + covid_step*hiphop_mc 
         + covid_step*indie_mc + covid_step*jazz_mc + covid_step*pop_mc  + covid_step*rnb_mc + covid_step*rock_mc
         + covid_step*MLShare + covid_step*log(ntracksotherpl) + feature + week, data = df, index = c("id","week"), model = "within")
m_rob <- m
m_rob$vcov <- vcovHC(m, type = "HC1")

summary(m_rob)

#################################
#      VISUALIZING RESULTS      #
#################################
# Function to perform delta method calculations
calculate_effects <- function(calcs_list, model) {
  calculations <- rbindlist(lapply(names(calcs_list), function(name) {
    res <- data.frame(deltaMethod(model, calcs_list[[name]]))
    colnames(res) <- c('est','se','q025','q975')
    res$type <- name
    res$est <- res$est * 100  # Convert to percentage
    res$se <- res$se * 100    # Convert to percentage
    return(res)
  }))
  return(calculations)
}

# Calculate different effects of curator
calcs_curator = list(Spotify='covid_step1', 
                     Indie="covid_step1+`covid_step1:curatorIndie`",
                     MajorLabel="covid_step1+`covid_step1:curatorMajorLabel`",
                     Professional="covid_step1+`covid_step1:curatorProfessional`",             
                     User="covid_step1+`covid_step1:curatorUser`"
)

m_rob_curatoreffect <- calculate_effects(calcs_curator, m_rob)

# Plot the effects of curator
ggplot(m_rob_curatoreffect, aes(x=type, y=est, fill = type)) +
  geom_bar(stat="identity", alpha=0.7) +
  geom_errorbar(aes(ymin=est-se, ymax=est+se), width=0.4, colour="darkgrey", alpha=0.9, size=0.9) +
  scale_fill_brewer(palette = "Set1") +
  theme_minimal() +
  labs(title ="The estimated weekly effect of pandemic declaration (Using Delta Rule) across Playlist Curator",x="Curator", y="Estimated Effects of Covid-19 on Followers' Growth (%)")

# Calculate different effects of percentile
calcs_percentile = list(Top1='covid_step1', 
                        Top10="covid_step1+`covid_step1:percentiletop10%`",
                        Top30="covid_step1+`covid_step1:percentiletop30%`",
                        Tail="covid_step1+`covid_step1:percentiletail`"
)

m_rob_percentileffect <- calculate_effects(calcs_percentile, m_rob)

# Plot the effects of percentile, choose different plot
ggplot(m_rob_percentileffect, aes(x = type, y = est, fill = type)) +
  geom_bar(stat = "identity", width = 0.6, alpha = 0.7) +
  geom_errorbar(aes(ymin = est - se, ymax = est + se), width = 0.2, colour = "orange", size = 1) +
  coord_flip() +  # Flip coordinates to make labels readable
  scale_fill_brewer(palette = "Pastel1") +
  theme_minimal() +
  theme(
    legend.position = "none",  
    axis.title.y = element_blank(),  
    axis.text.y = element_text(size = 12),  
    plot.title = element_text(hjust = 0.5)  
  ) +
  labs(
    x = "Percentile Group",
    y = "Estimated Effects of Covid-19 on Followers' Growth (%)",
    title = "The estimated weekly effect of pandemic declaration (Using Delta Rule) across Playlist Percentile"
  )

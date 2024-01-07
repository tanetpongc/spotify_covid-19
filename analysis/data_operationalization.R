#####################################
# Import Necessary Library and Data #
#####################################
library(data.table) #for reading csv data with fread(faster)
library(dplyr) #for left join command
library(plyr) #to rename sectionName of promotion.csv

playlist_df <- fread("../../gen/data-preparation/output/playlists.csv")
playlist_info_df<-playlist_df[, .(id,owner_class,recommendation_type,follower_percentile,listeners_to_followers_ratio)]

playlist_attribute <- fread("/data/volume_2/gen/data-preparation/output/placements-aggregated_extended.csv")
promotions_df <- fread("/data/volume_2/gen/data-preparation/externals/promotions.csv", stringsAsFactors=TRUE) 

playlist_followers_df <- fread("../../gen/data-preparation/output/followers.csv") 

playlist_cluster_widedf <- fread("../../gen/data-preparation/output/df_pivotcluster_1_90.csv") #use wide table for demand/followers data
colnames(playlist_cluster_widedf)[colnames(playlist_cluster_widedf) == 'id'] <- 'playlist_id'

playlist_cluster_longdf <- fread("../../gen/data-preparation/output/df_cluster_1_90.csv") #use long table for supply/promotion data
colnames(playlist_cluster_longdf)[colnames(playlist_cluster_longdf) == 'id'] <- 'playlist_id'


############################
#      Followers Data      #
############################


#create week variable in the period of interest (generate all dates, so we don't have any missings inbetween)
datefromfollowers <- data.table(date = seq(from = min(promotions_df$date), 
                                           to=max(playlist_followers_df$date), by = '1 day')) #the promotion-related data starts from 29 oct 2019 and followers ends on 14 oct 2020

# do within-data.table operation `:=` (much faster)
#datefromfollowers[, week := floor(1:.N/7)+1] #This leaves first 6 days as week 1, why?

datefromfollowers[, year:=strftime(date, format = "%Y")]
datefromfollowers[, week:=strftime(date, format = "%V")]
datefromfollowers[, month:=strftime(date, format = "%m")]

#strftime make a wrong week-year count by the year end so we have to adjust that first
datefromfollowers$year[datefromfollowers$year=="2019" & datefromfollowers$month=="12" & datefromfollowers$week=="01"] <- "2020"

datefromfollowers[, year_week:=paste0(year,"_w",week)]
datefromfollowers[, period:=as.numeric(as.factor(year_week))]



# left join w/ data.table avoids unnecessary memory burden
setkey(playlist_followers_df, date)
setkey(datefromfollowers, date)
playlist_followers_df[datefromfollowers, period:=i.period]
playlist_followers_df[datefromfollowers, month:=month]
playlist_followers_df[datefromfollowers, week:=week]
playlist_followers_df[datefromfollowers, year_week:=year_week]

playlist_followers_df <- playlist_followers_df[!is.na(playlist_followers_df$period), ] #drop NA period

#Select only playlist the have the full observation
numberobs_byid<-setDT(playlist_followers_df)[, .(totalobs=uniqueN(period)), by=.(id)]
message(paste("Max number of observation: ",max(numberobs_byid$totalobs)))

numberid_byobs<-setDT(numberobs_byid)[, .(totalid=uniqueN(id)), by=.(totalobs)]
numberid_byobs<-numberid_byobs[order(-numberid_byobs$totalobs),]

id_fullobs <- subset(numberobs_byid,totalobs == max(numberobs_byid$totalobs))
message(paste("Number of playlist in the period of interest: ",dim(numberobs_byid)[1]))
message(paste("Number of playlist with complete obs: ",dim(id_fullobs)[1]))
id_fullobslist <- unique(id_fullobs$id)

playlist_followers_full_df <- playlist_followers_df[id %in% id_fullobslist,]

# create mean value during the period df
period_df_noid <- setDT(playlist_followers_full_df)[, .(avgfollowers=mean(followers), month = min(month)), by=.(id,period,week,year_week)] 
  #so year end month 12 of 2019 become january

playlistid_id = playlist_df[, c('id','playlist_id')]
period_df <- merge(period_df_noid,playlistid_id, by="id")
  
# Create covid step variable, include=FALSE}
covid_period <- datefromfollowers$period[datefromfollowers$date==as.Date("2020-03-11")]
period_df$covidbyweek <- ifelse(period_df$period< covid_period, 0, 1)


############################
#      Attributes Data     #
############################

#Recalculated ntrack change as nadded and nremoved (always 0) dont work
lag_1 <- function(x, k = 1) head(c(rep(NA, k), x), length(x))
playlist_attribute[, ntrack_change := ntracks-lag_1(ntracks), by = c('id')]
playlist_attribute <- na.omit(playlist_attribute, cols = c("ntrack_change")) #drop NA in 30/09/2018

#Merge Week
setkey(playlist_attribute, date)
setkey(datefromfollowers, date)
playlist_attribute[datefromfollowers, period:=period]


#create updating frequency (when they add the track)
playlist_attribute[, updatefreq := ifelse (ntrack_change !=0, 1, 0)]


#R get confused with the "-", hence we will rename columns relating to -sd
names(playlist_attribute)[names(playlist_attribute) == "ac-sd_danceability"] <- "ac_sd_danceability"
names(playlist_attribute)[names(playlist_attribute) == "ac-sd_energy"] <- "ac_sd_energy"
names(playlist_attribute)[names(playlist_attribute) == "ac-sd_acousticness"] <- "ac_sd_acousticness"
names(playlist_attribute)[names(playlist_attribute) == "ac-sd_speechiness"] <- "ac_sd_speechiness"
names(playlist_attribute)[names(playlist_attribute) == "ac-sd_instrumentalness"] <- "ac_sd_instrumentalness"
names(playlist_attribute)[names(playlist_attribute) == "ac-sd_liveness"] <- "ac_sd_liveness"
names(playlist_attribute)[names(playlist_attribute) == "ac-sd_valence"] <- "ac_sd_valence"
names(playlist_attribute)[names(playlist_attribute) == "ac-sd_tempo"] <- "ac_sd_tempo"


#aggregate
period_playlist_attributes_df<-setDT(playlist_attribute)[, .(avgml_curr=mean(ml_curr),
                                                    avgsony_curr=mean(sony_curr),
                                                    avguniversal_curr=mean(universal_curr),
                                                    avgwarner_curr=mean(warner_curr),
                                                    avgntracks=mean(ntracks),
                                                    avgntrackschange=mean(ntrack_change),
                                                    avgnadded=mean(nadded),
                                                    avgnremoved=mean(nremoved),
                                                    totalupdated=sum(updatefreq),
                                                    avgntracksotherpl=mean(ntracksotherpl),
                                                    avgntracksotherpl_top10=mean(ntracksotherpl_top10),
                                                    avgntracksotherpl_top20=mean(ntracksotherpl_top20),
                                                    avgml_top10share=mean(ml_top10share),
                                                    avgml_top20share=mean(ml_top20share),
                                                    avgtrackage=mean(trackage),
                                                    avgtracklength_sec=mean(tracklength_sec),
                                                    avgac_danceability=mean(ac_danceability),
                                                    avgac_energy=mean(ac_energy),
                                                    avgac_speechiness=mean(ac_speechiness),
                                                    avgac_acousticness=mean(ac_acousticness),
                                                    avgac_instrumentalness=mean(ac_instrumentalness),
                                                    avgac_liveness=mean(ac_liveness),
                                                    avgac_valence=mean(ac_valence),
                                                    avgac_tempo=mean(ac_tempo),
                                                    avgac_sd_danceability=mean(ac_sd_danceability),
                                                    avgac_sd_energy=mean(ac_sd_energy),
                                                    avgac_sd_speechiness=mean(ac_sd_speechiness),
                                                    avgac_sd_acousticness=mean(ac_sd_acousticness),
                                                    avgac_sd_instrumentalness=mean(ac_sd_instrumentalness),
                                                    avgac_sd_liveness=mean(ac_sd_liveness),
                                                    avgac_sd_valence=mean(ac_sd_valence),
                                                    avgac_sd_tempo=mean(ac_sd_tempo),
                                                    avgnlabels=mean(nlabels),
                                                    avglabel_herf=mean(label_herf),
                                                    avgartists_herf=mean(artists_herf),
                                                    avgnartists=mean(nartists),
                                                    avgtrack_top10index=mean(track_top10index),
                                                    avgtrack_top20index=mean(track_top20index),
                                                    avgtrack_herf=mean(track_herf)
                                                    ),
                                        by=.(id,period)]

#Merge attributes with followers data
period_followerattribute_df <- merge(period_df,period_playlist_attributes_df, by=c("id","period"))

############################
#       Playlist Data      #
############################


#Rank the playlist based on the follower share so we know its position (Quantile th)
setorder(playlist_info_df, follower_percentile)
playlist_info_df$rank <-1:nrow(playlist_info_df)

period_followerattributeplaylist_df <- merge(period_followerattribute_df,playlist_info_df, by=c("id"))

############################
#      Promotions Data     #
############################


# filter promotion with our main genres and countries with full obervation
  # first we need to rename the value of section name to be consistent with our categories
  promotions_df$sectionName<- revalue(promotions_df$sectionName, c(
    "hiphop"="hip hop",
    "kpop"="k pop", 
    "edm_dance"="edm"
  ))


#We select countries with full observations (including GLOBAL) and playlist existed in demand/followers data
    playlistid_demand <- unique(period_followerattribute_df$playlist_id)
  promotions_maincountry_df <- promotions_df[!countryCode %in% c('cz', 'do','gr','kr','ro','ru'),]
  promotions_mainid_df <- promotions_maincountry_df[playlist_id %in% playlistid_demand,]

#Merge with period
  setkey(promotions_mainid_df, date)
  setkey(datefromfollowers, date)
  promotions_mainid_df[datefromfollowers, period:=period]


# Create dataframe of promotion info by section/genres and date
  promotions_mainid_numberpromotedbycountry <-setDT(promotions_mainid_df)[, .(sectionpromotedincountry=.N), by=.(playlist_id,period,countryCode)]
  promotions_mainid_sectionpromotedpercountry <-setDT(promotions_mainid_numberpromotedbycountry)[, .(sectionpromotedpercountry=mean(sectionpromotedincountry),totalpromoted=sum(sectionpromotedincountry)), by=.(playlist_id,period)]


# merge data
df <- left_join(period_followerattributeplaylist_df,promotions_mainid_sectionpromotedpercountry, by =c("playlist_id","period"))


####################################
#      Clean data before export    #
####################################

#Manage Duplicated
  duplicaterows<- df[duplicated(df)]
    #We extract the duplicated rows, remove both and add the distinct one back
  dupid <- unique(duplicaterows$id)
  df <- df[!id %in% dupid,]
  df <- rbind(df,duplicaterows)
  #select unique id and period we should have unique id(70862) x #week(105)
  df <- unique(df, by = c("id", "period"))

# We lost some continuous date due to missing attribute information on some certain dates (we have till week 44 of year 2020), we will  clean last time
  df_numberobs_byid<-setDT(df)[, .(totalobs=uniqueN(period)), by=.(id)]
  message(paste("Max number of observation in selected df: ",max(df_numberobs_byid$totalobs)))
  
  df_numberid_byobs<-setDT(df_numberobs_byid)[, .(totalid=uniqueN(id)), by=.(totalobs)]
  df_numberid_byobs<-df_numberid_byobs[order(-df_numberid_byobs$totalobs),]
  
  df_id_fullobs <- subset(df_numberobs_byid,totalobs == max(df_numberobs_byid$totalobs))
  message(paste("Number of playlist in the period of interest: ",dim(df_numberobs_byid)[1]))
  message(paste("Number of playlist with complete obs: ",dim(df_id_fullobs)[1]))
  df_id_fullobslist <- unique(df_id_fullobs$id)
  
  df <- df[id %in% df_id_fullobslist,]


########################
#      Export Data     #
########################
period = "week"

path = '../../gen/analysis/temp'
dir.create(path)

df_output = paste0(path,'/',period,'_precleandf_excludinggenre','.csv')
fwrite(df,df_output)

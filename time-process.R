library(jsonlite)
data <- fromJSON('timing.json')

data$run <- as.factor(data$run)
data$version <- as.factor(data$version)

data <- subset( data, select = c('run', 'version', 'elapsed', 'cache', 'match_pos_cache', 'warm_cache'))

attach(data)
agg <- aggregate( elapsed ~ cache * match_pos_cache * warm_cache + version, run, mean )
detach(data)

agg.aov <- subset(agg, version == 'perl-5.34.0@babble'  )
print(agg.aov)
a <- aov( elapsed ~ cache * (match_pos_cache + warm_cache) , agg.aov )
print(a); print( summary(a) )

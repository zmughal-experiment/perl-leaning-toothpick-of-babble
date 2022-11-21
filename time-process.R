library(jsonlite)
data <- fromJSON('timing.json')

data$run <- as.factor(data$run)
data$version <- as.factor(data$version)
data$workers <- as.factor(data$workers)

data <- subset( data, select = -c(timing))

model <- elapsed ~ version + workers * ( cache * match_pos_cache * warm_cache + bail_out_early + bail_out_late )

attach(data)
agg <- aggregate(model, run, mean )
detach(data)

agg.perl534 <- subset(agg, version == 'perl-5.34.0@babble'  )
print(agg.perl534)
fit <- aov( model, agg.perl534 )
print(fit); print( summary(fit) )

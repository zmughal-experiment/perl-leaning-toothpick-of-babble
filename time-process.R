library(jsonlite)
data <- fromJSON('timing.json')

data$run <- as.factor(data$run)
data$version <- as.factor(data$version)
data$workers <- as.factor(data$workers)

data <- subset( data, select = -c(timing))

model         <- elapsed ~ version * workers * ( cache * match_pos_cache * warm_cache + bail_out_early + bail_out_late )
model.reduced <- elapsed ~ version * workers * ( warm_cache )
model.reduced.noversion <- elapsed ~ workers * ( warm_cache )

attach(data)
agg <- aggregate(model, run, mean )
detach(data)

fit <- aov( model.reduced, agg )
print(fit); print( summary(fit) )

agg.perl534 <- subset(agg, version == 'perl-5.34.0@babble'  )
print(agg.perl534)
fit.perl534 <- aov( model.reduced.noversion, agg.perl534 )
print(fit.perl534); print( summary(fit.perl534) )

agg.sort.elapsed <- agg[order(agg$elapsed),c('version','warm_cache','workers','elapsed')]
print(agg.sort.elapsed)

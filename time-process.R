library(jsonlite)
data <- fromJSON('timing.json')

data$run <- as.factor(data$run)
data$version <- as.factor(data$version)
data$workers <- as.factor(data$workers)

data <- subset( data, select = -c(timing))

model         <- elapsed ~ version * workers * ( cache * match_pos_cache * warm_cache + bail_out_early + bail_out_late )
model.reduced <- elapsed ~ version * workers * ( warm_cache )
model.reduced.noversion <- elapsed ~ workers * ( warm_cache )

attach(data); agg <- aggregate(model, run, mean ); detach(data)

print('model.reduced')
fit <- aov( model.reduced, data )
print(fit); print( summary(fit) )
print('model.reduced coefficients')
print(as.matrix(sort(coef(fit))), digits=2)

print('model.reduced.noversion')
data.perl534 <- subset(data, version == 'perl-5.34.0@babble'  )
fit.perl534 <- aov( model.reduced.noversion, data.perl534 )
print(fit.perl534); print( summary(fit.perl534) )

print('agg.sort.elapsed')
agg.sort.elapsed <- agg[order(agg$elapsed),c('version','warm_cache','workers','elapsed')]
print(agg.sort.elapsed)

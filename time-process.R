library(ggplot2)
library(purrr)
library(ARTool)
library(jsonlite)
data <- fromJSON('timing.json')

data$run <- as.factor(data$run)
data$version <- as.factor(data$version)
data$workers <- as.factor(data$workers)
#print(str(data))#DEBUG

data <- subset( data, select = -c(timing))

model         <- elapsed ~ version * workers * ( cache * warm_cache + bail_out_early + bail_out_late )
model.reduced <- elapsed ~ version * workers * ( warm_cache )
model.reduced.noversion <- elapsed ~ workers * ( warm_cache )

agg <- aggregate(model, mean, data = data )

## Check equal group variances for ANOVA
#print('elapsed.var'); print(aggregate(model, var, data = data ))
## Check normality
#fit.aov <- aov( model.reduced, data )
#qqnorm( fit.aov$residuals ); qqline( fit.aov$residuals )
#print(shapiro.test( data$elapsed ))

print('model.reduced')
art.reduced <- art( model.reduced, data )
fit.reduced <- anova( art.reduced )
print(fit.reduced)

# Compare with version facet
plot.bp <- ( ggplot( data,
       aes( y = elapsed, workers, color = warm_cache  ) )
	+ geom_boxplot() + facet_wrap( ~ version ) )
ggsave(plot = plot.bp, filename = 'elapsed-facet-version-boxplot.png', width = 11)

print('model.reduced.noversion')
walk( levels(data$version), function(v) {
	print(v)
	data.v <- subset(data, version == v  )
	art.v <- art( model.reduced.noversion, data.v )
	fit.v <- anova(art.v)
	print(fit.v);
})

print('agg.sort.elapsed')
agg.sort.elapsed <- agg[order(agg$elapsed),c('version','warm_cache','workers','elapsed')]
print(agg.sort.elapsed)

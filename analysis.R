library(tm); library(ggplot2); library(wordcloud); library(lda); library(reshape2)


#-------------------------------------------------------------------------------
#
# Load corpus
#
#-------------------------------------------------------------------------------
# Load corpus and clean up
corpus <- Corpus(DirSource("./essays/"), readerControl = list(language="english"))
corpus <- tm_map(corpus, content_transformer(tolower))
corpus <- tm_map(corpus, removeNumbers)
corpus <- tm_map(corpus, removePunctuation)
corpus <- tm_map(corpus, stripWhitespace)

# This is janky
# library(SnowballC); corpus <- tm_map(corpus, stemDocument) 

# Remove stopwords and additional words
stopwords("english")
corpus <- tm_map(corpus, removeWords, stopwords("english"))
remove <- c("will", "may", "can", "might", "shall", "must", "one", "upon", 
            "much", "every", "often", "nothing", "less")
corpus <- tm_map(corpus, removeWords, remove)



#-------------------------------------------------------------------------------
#
# Create word cloud
#
#-------------------------------------------------------------------------------
# Word Cloud
set.seed(76)
wordcloud(corpus, scale=c(5,0.5), max.words=25, random.order=FALSE, 
          rot.per=0.35, use.r.layout=FALSE, colors=brewer.pal(8, "BuPu"))



#-------------------------------------------------------------------------------
#
# Latent Dirichlet Allocation
#
#-------------------------------------------------------------------------------
#---------------------------------------------------------------
# Run method
#---------------------------------------------------------------
n.topics <- 4
n.top.words <- 5
n.sim <- 10000

# Initial values
alpha <- 0.1
beta <- 0.1

dtm <- DocumentTermMatrix(corpus)
vocab <- colnames(dtm)
doc.list <- vector("list", length=length(corpus))
for(i in 1:length(corpus)) {
  doc.list[i] <- lexicalize(paste(fed.papers[[i]], collapse=""), lower=TRUE, vocab=vocab)
}
result <- lda.collapsed.gibbs.sampler(doc.list, n.topics, vocab, n.sim, alpha, beta, 
                              compute.log.likelihood=TRUE)

# Top words for each topic
top.words <- top.topic.words(result$topics, n.top.words, by.score=TRUE)

# Matrix of topic proportions for all essays
topic.proportions <- t(result$document_sums) / colSums(result$document_sums)
colnames(topic.proportions) <- apply(top.words, 2, paste, collapse=" ")
rownames(topic.proportions) <- 1:length(corpus)


#---------------------------------------------------------------
# For each of the topics, identify the two documents with the highest topic
# proportion allocated to is
#---------------------------------------------------------------
sampled.docs <- as.vector(
  apply(topic.proportions, 2, function(x){order(x, decreasing=TRUE)[1:2]})
  )
topic.proportions <- topic.proportions[sampled.docs,]

topic.proportions <- melt(
  cbind(
    data.frame(topic.proportions), 
    document=factor(sampled.docs, levels=sampled.docs)
    ),
  variable.name="topic", id.vars = "document"
)

# Plot
ggplot(topic.proportions, 
  aes(x = factor(topic), y=value, fill=topic)) + geom_bar(stat = "identity") +
  coord_flip() + ylab("proportion") + xlab("topic") + 
  facet_wrap(~ document, ncol=2) + theme(legend.position="none")



#-------------------------------------------------------------------------------
#
# Log-Odds of Word Use by Certain Authors vs Rest
#
#-------------------------------------------------------------------------------
load("federalist.RData")
n.essays <- length(fed.papers)
names(fed.papers) <- 1:n.essays


#---------------------------------------------------------------
# Restrict consideration to undisputed papers
#---------------------------------------------------------------
# Focus for now on 69 out of 85 essays whose authorship is not disputed
disputed <- which(as.character(authors.list$hamilton) != as.character(authors.list$madison))
undisputed <- setdiff(1:n.essays, disputed)

authors.list[undisputed,]
fed.papers <- fed.papers[undisputed]


#---------------------------------------------------------------
# ID which words were used by each author
#---------------------------------------------------------------
ham.words <- mad.words <- jay.words <- all.words <- NULL

# Compile all words
for (i in 1:length(fed.papers)) {
  words <- tolower(fed.papers[[i]])
  words <- gsub("[[:punct:]]", " ", words)
  words <- unlist(strsplit(words, " "))
  words <- words[!words == ""]
  words <- words[!words == " "]
  
  if (authors.list$hamilton[i] == "HAMILTON") {
    ham.words <- c(ham.words, words)
  } else if (authors.list$hamilton[i] == "MADISON") {
    mad.words <- c(mad.words, words)
  } else if (authors.list$hamilton[i] == "JAY") {
    jay.words <- c(jay.words, words)
  }  
  all.words <- c(all.words, words)
}

# Compute frequencies
ham.freq <- sort(table(ham.words), decreasing=TRUE)
ham.freq <- ham.freq / sum(ham.freq)

mad.freq <- sort(table(mad.words), decreasing=TRUE)
mad.freq <- mad.freq / sum(mad.freq)

jay.freq <- sort(table(jay.words), decreasing=TRUE)
jay.freq <- jay.freq / sum(jay.freq)

all.freq <- sort(table(all.words), decreasing=TRUE)
all.freq <- all.freq / sum(all.freq)

# Drop "uninteresting" words.  Some judgement calls here.  Have to also
# consider those words I left in, like "we"
uninteresting.words <- 
  c("the", "of", "to", "and", "in", "a", "be", "that", "it", "is", "by", 
    "which", "as", "on", "have", "for", "not", "this", "will", "their",
    "or", "with", "are", "been", "from", "they", "may", "an", "would", "other",
    "has", "its", "these", "them", "than", "so", "such", "if", "any", "at",
    "into", "was", "had", "were", "who", "those", "each", "but", "upon",
    "only", "too", "when", "though", "much", "even", "also", "therefore",
    "very", "what", "without",
    # Dicier words to remove. Focus in on topics/subjects/themes
    "we", "all", "no", "more", "most", "his", "he", "either", "there",
    "can", "most", "every", "under", "could", "some")

mad.freq <- mad.freq[!is.element(names(mad.freq), uninteresting.words)]
ham.freq <- ham.freq[!is.element(names(ham.freq), uninteresting.words)]
jay.freq <- jay.freq[!is.element(names(jay.freq), uninteresting.words)]
all.freq <- all.freq[!is.element(names(all.freq), uninteresting.words)]


#---------------------------------------------------------------
# Compute log-odds ratios
#---------------------------------------------------------------
# ID top words by each author and overall
n.top.words <- 25
top.ham.words <- names(ham.freq)[1:n.top.words]
top.mad.words <- names(mad.freq)[1:n.top.words]
top.jay.words <- names(jay.freq)[1:n.top.words]
top.words <- names(all.freq)[1:n.top.words]


# The set of words to consider
words.of.interest <- top.ham.words

# We compare the authors use of the set of words vs the rest
author <- "hamilton"
author.words <- ham.words
rest.words <- c(jay.words, mad.words)

log.odds.ratio <- rep(0, length(words.of.interest))
SE <- rep(0, length(words.of.interest))

for(i in 1:length(words.of.interest)) {
  word <- words.of.interest[i]
  
  p.author <- sum(author.words == word) / length(author.words)
  p.rest <- sum(rest.words == word) / length(rest.words)
  
  odds.ratio <- p.author / (1-p.author)
  odds.ratio <- odds.ratio / (p.rest/(1-p.rest))
  
  log.odds.ratio[i] <- log(odds.ratio)
  
  SE[i] <- 
    1/sum(author.words == word) + 
    1/sum(author.words != word) +
    1/sum(rest.words == word) + 
    1/sum(rest.words != word)
  SE[i] <- sqrt(SE[i])
}

top.words.data <- data.frame(words=words.of.interest, 
                             log.odds.ratio=log.odds.ratio,SE=SE)
top.words.data$words <- 
  factor(top.words.data$words, levels=rev(top.words.data$words))

limits <- aes(ymax = log.odds.ratio + 1.96*SE, ymin=log.odds.ratio - 1.96*SE)
dodge <- position_dodge(width=0.9)

ggplot(top.words.data, aes(x=words,y=log.odds.ratio)) + 
  geom_bar(stat="identity") + 
  theme(text = element_text(size=20), 
        axis.text.x = element_text(angle = 90, hjust = 1)) + 
  geom_errorbar(limits, position=dodge, width=0.25, col="red") + 
  geom_point(col="red", size=3) + 
  labs(
    x=sprintf("top %i %s words (sorted)", length(words.of.interest), author),
    y=sprintf("log odds ratio of %s use vs rest use", author),
    title="Comparison of Word Use in Undisputed Essays"
  ) + coord_flip()
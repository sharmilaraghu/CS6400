// import the lexicon MPQA
CREATE CONSTRAINT ON (w:Word) ASSERT w.word IS UNIQUE;
CREATE CONSTRAINT ON (w:Keyword) ASSERT w.word IS UNIQUE;
CREATE CONSTRAINT ON (p:Polarity) ASSERT p.polarity IS UNIQUE;

//create polarity poles
CREATE
(:Polarity {polarity:"positive"}),
(:Polarity {polarity:"negative"});

//import the sentiment corpus

USING PERIODIC COMMIT 5000
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/sharmilaraghu/CS6400/master/sentimentDict.csv" AS line
WITH line
MERGE (a:Keyword {word:line.word});

//create relationship between the polarity and keywords 

USING PERIODIC COMMIT 5000
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/sharmilaraghu/CS6400/master/sentimentDict.csv" AS line
WITH line
MATCH (w:Keyword {word:line.word}), (p:Polarity {polarity:line.polarity})
MERGE (w)-[:SENTIMENT]->(p);

//make sure necessary indexes exist
CREATE INDEX ON :ReviewWords(word);
CREATE INDEX ON :Review(sentiment);

// load the dataset 


USING PERIODIC COMMIT 5000
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/sharmilaraghu/CS6400/master/Review2.csv" as line
WITH line
CREATE (r:Review {review:toLOWER(line.review), trueSentiment:0, analyzed:FALSE});

USING PERIODIC COMMIT 5000
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/sharmilaraghu/CS6400/master/Review21.csv" as line
WITH line
CREATE (r:Review {review:toLOWER(line.review), trueSentiment:1, analyzed:FALSE});

//algo starts here

MATCH (n:Review)
WHERE n.analyzed = FALSE
WITH n, split(n.review, " ") as words
UNWIND words as word
CREATE (rw:ReviewWords {word:word})
WITH n, rw
CREATE (rw)-[:IN_REVIEW]->(n);

// assigning word counts

MATCH (n:Review)
WITH n, size((n)<-[:IN_REVIEW]-()) as wordCount
SET n.wordCount = wordCount;

//creating temporary relationships between keywords and words in our reviews

MATCH (n:Review)-[:IN_REVIEW]-(wordReview)
WITH distinct wordReview
MATCH  (keyword:Keyword)
WHERE wordReview.word = keyword.word AND (keyword)-[:SENTIMENT]-()
MERGE (wordReview)-[:TEMP]->(keyword);

//scoring the reviews

MATCH (n:Review)-[rr:IN_REVIEW]-(w)-[r:TEMP]-(keyword)-[:SENTIMENT]-(:Polarity)
OPTIONAL MATCH pos = (n:Review)-[:IN_REVIEW]-(wordReview)-[:TEMP]-(keyword)-[:SENTIMENT]-(:Polarity {polarity:'positive'})
WITH n, toFloat(count(pos)) as plus
OPTIONAL MATCH neg = (n:Review)-[:IN_REVIEW]-(wordReview)-[:TEMP]-(keyword)-[:SENTIMENT]-(:Polarity {polarity:'negative'})
WITH ((plus - COUNT(neg))/n.wordCount) as score, n
SET n.sentimentScore = score;

//assigning postive, negative, or neutral sentiment and deleting TEMP relationships

//based on percentage of pos or negatives words in reviews, detemining sentiment pos, neg, or neutral

MATCH (n:Review)-[rr:IN_REVIEW]-(w)-[r:TEMP]-(keyword)-[:SENTIMENT]-(:Polarity)
WHERE n.sentimentScore >= (.001)
SET n.sentiment = 'positive', n.analyzed = TRUE
DELETE w, r, rr;

MATCH (n:Review)-[rr:IN_REVIEW]-(w)-[r:TEMP]-(keyword)-[:SENTIMENT]-(:Polarity)
WHERE n.sentimentScore <= (-.001)
SET n.sentiment = 'negative', n.analyzed = TRUE
DELETE w, r, rr;

MATCH (n:Review)-[rr:IN_REVIEW]-(w)-[r:TEMP]-(keyword)-[:SENTIMENT]-(:Polarity)
WHERE (.001) > n.sentimentScore > (-.001)
SET n.sentiment = 'neutral', n.analyzed = TRUE
DELETE w, r, rr;

//cleaning up our temporary review words

MATCH (:Review)-[r]-(deleteMe:ReviewWords)
DELETE r, deleteMe;

//calculating percentages
/finally comparing our test movie reviews' true scores to the results determined by our algorithim

MATCH (n:Review {trueSentiment:1, sentiment:'negative'}) 
WITH toFloat(count(n)) as wrongs
MATCH (nn:Review {trueSentiment:0, sentiment:'positive'})
WITH (wrongs + count(nn)) as wrong
MATCH (nnn:Review {sentiment:'neutral'})
WITH (wrong + count(nnn)) as wrongCount
MATCH (total:Review)
WITH 100*(1-toFloat(wrongCount/(COUNT(total)))) as percentCorrect
RETURN percentCorrect;

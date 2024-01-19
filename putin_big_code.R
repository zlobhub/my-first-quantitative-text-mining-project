# 0.1) libraries
library(lubridate)
library(lexicon)
library(rvest)
library(readr)
library(dplyr)
library(lubridate)
library(stringr)
library(quanteda)
library(quanteda.textmodels)
library(quanteda.textstats)
library(HunMineR)
library(ggplot2)
library(plotly)


# 0.2) reading the needed data



################################################
# getting the data for the resigned journalists
################################################



putin_original_data1 <- read.csv("C:/Users/userű/Desktop/KVANTITEXT/putyin_projekt/cleaned_putin_text.csv",
                                 header = TRUE, fileEncoding="UTF-8", sep = ",")

#if sampling needed
#index_original_data1 <- index_original_data1[sample(nrow(index_original_data1), 50), ]

journalist_resign_date <- as.Date('2021-08-24')
invasion_date <-  as.Date('2022-02-24')


#0.5) basic filtering of the dataset

index_mutated_data1 <- putin_original_data1 %>%
  mutate(
    text = str_remove_all(string = text, pattern = "[:cntrl:]"),
    text = str_remove_all(string = text, pattern = "[:punct:]"),
    text = str_remove_all(string = text, pattern = "[:digit:]"),
    text = str_to_lower(text),
    text = str_trim(text),
    text = str_squish(text),
    doc_id = paste0("text", row_number()),
    date = sub("^(\\d{4}\\.\\d{2}\\.\\d{2}).*", "\\1", date)
  ) %>%
  filter(nchar(date) == 10)

index_mutated_data1$date <- as.Date(index_mutated_data1$date, format = "%Y.%m.%d")



index_mutated_data1 <- index_mutated_data1 %>% 
  mutate(resigned_or_not = ifelse(date < journalist_resign_date, 0, 1))



# Checking

#class(index_mutated_data1$date)
#unique(index_original_data1$date)

# 1.1.) Making a Corpus

corpus1 <-  quanteda::corpus(index_mutated_data1$text)

# Sok cikk készülhet, de vajon a hosszúságuk is növekszik?
# checking how many characters are written per days

index_mutated_data1$token_count <- sapply(tokens(corpus1), length)


article_length_plot <- ggplot(data = index_mutated_data1, aes(date, token_count)) + 
  geom_line() +
  geom_smooth(method = "auto", se = FALSE, color = "darkorange1") + 
  labs(y = "Sentiment", x = "Date", caption = "Source: index.hu") +
  scale_x_date(date_labels = "%y-%m", date_breaks = "1 month") +
  geom_vline(xintercept = as.Date(journalist_resign_date), linetype = "dashed", color = "deepskyblue4") +
  geom_vline(xintercept = as.Date(invasion_date), linetype = "dashed", color = "coral2") +
  ggtitle("Az index.hu -putyin- kifejezést tartalmazó cikjeinek karakterhossza dátum szerint")

print(article_length_plot)


article_length_plot_interactive <- ggplotly(article_length_plot, tooltip = c("y", "x"))

print(article_length_plot_interactive)



# corpus tisztítása

corpus1_filt <- corpus1 %>% 
  quanteda::tokens(remove_punct = TRUE, remove_symbols = TRUE, remove_numbers = TRUE, remove_url = TRUE) %>%
  quanteda::tokens_tolower()



# 1.2.) Tokenizing the text

index_toks1 <- quanteda::tokens(corpus1_filt)

index_toks1 <- quanteda::tokens_tolower(index_toks1)

index_toks1 <- quanteda::tokens_wordstem(index_toks1)



# 1.3.) lemmatizing the words

index_lem_toks1 <- index_toks1 %>% 
  quanteda::tokens_replace(pattern = lexicon::hash_lemmas$token,
                           replacement = lexicon::hash_lemmas$lemma)



# 1.4.) sopword removal, so the analysis will not have too much junk

sw_hu <- quanteda::stopwords("hungarian")

index_lem_sw1 <- index_lem_toks1 %>% 
  quanteda::tokens_remove(sw_hu)


#putting it all in one clean df

listr<-list(index_lem_sw1)[[1]]

cleantext1<-lapply(listr,function(x)paste(x,collapse=" "))%>%unlist()

index_clean_df1<-index_mutated_data1

index_clean_df1$text<-cleantext1

# if needed save the df
# write.csv(index_clean_df1,"clean_putin_filtered1.csv")


#checking
print(cleantext1[1])


# 1.5.) Making a dfm

index_dfm_clean1 <- cleantext1 %>%
  tokens() %>%
  dfm(
    remove_punct = TRUE,
    remove_numbers = TRUE,
    remove = stopwords(language = "hungarian"),
    verbose = quanteda_options("verbose")
  ) %>%
  dfm_tfidf()



# if needed save the dfm
#   write.csv(as.matrix(index_dfm_clean1), file = "putin_dfm1.csv")

#   dfm1 <- read.csv("C:/Users/userű/Desktop/szakdoga/code/scrap_clean_newest/textek_kulon_kulon/index_dfm_clean_v21.csv",
#                 header = TRUE, fileEncoding="UTF-8", sep = ",")



############################
# loading the dfm /// does not help for some reason... I have to use the previous dfm-s
############################


#sentiment dictionary used
poltext_szotar <- HunMineR::dictionary_poltext

poltext_szotar




############################
#text analysis

########################################################

# 1.6.) lookup making


texts <- index_dfm_clean1$text

index_article_szentiment <- quanteda::dfm_lookup(index_dfm_clean1, dictionary = poltext_szotar)

head(index_article_szentiment, 6)



docvars(index_dfm_clean1, "pos") <- as.numeric(index_article_szentiment[, 1])
docvars(index_dfm_clean1, "neg") <- as.numeric(index_article_szentiment[, 2])

head(docvars(index_dfm_clean1), 5)


# 1.7.) Saving the variables to the main dataframe:

index_clean_df1$pos <- docvars(index_dfm_clean1, "pos")
index_clean_df1$neg <- docvars(index_dfm_clean1, "neg")


corpu1_df <- quanteda::convert(index_dfm_clean1, to = "data.frame")

head(corpu1_df, 1)

# 1.8) 

# Grouping the scores by the date column
index_clean_df1 <- index_clean_df1 %>%
  group_by(date) %>%
  summarise(
    daily_pos = sum(pos),
    daily_neg = sum(neg),
    net_daily = daily_pos - daily_neg
  )


# 1.9)
#plotting it all

corpu1_df_plot <- ggplot(data = index_clean_df1, aes(date, net_daily)) + 
  geom_line() +
  geom_smooth(method = "auto", se = FALSE, color = "darkorange1") +  # Add trendline
  labs(y = "Sentiment", x = "Date", caption = "Source: index.hu") +
  geom_vline(xintercept = as.Date(journalist_resign_date), linetype = "dashed", color = "deepskyblue4") +
  ggtitle("Az index.hu -putyin- kifejezést tartalmazó cikjeinek szentimentje")

print(corpu1_df_plot)


corpu1_df_plot <- ggplot(data = index_clean_df1, aes(x = date, y = net_daily)) +
  geom_line(color = "darkseagreen", show.legend = FALSE) +
  geom_smooth(method = "auto", se = FALSE, color = "darkorange1", show.legend = FALSE) +
  geom_vline(xintercept = as.Date(journalist_resign_date), linetype = "dashed", color = "deepskyblue4", show.legend = FALSE) +
  labs(y = "Sentiment", x = "Date", caption = "Source: index.hu") +
  ggtitle("Az index.hu -brüsszel- kifejezést tartalmazó cikjeinek szentimentje") +
  theme_minimal()

# Convert ggplot to plotly
corpu1_df_plot_interactive <- ggplotly(corpu1_df_plot, tooltip = c("y", "x"))

# Print the interactive plot
print(corpu1_df_plot_interactive)

###################################################################################

###################################################################################

###################################################################################

# Ebből nem tudtunk me nagyon sokat

# Így megpróbálom a főnök nevét tartalmazó mondatokra szűrni a történetet


###################################################################################

###################################################################################

###################################################################################

#Funcition ami a putyin környezetében levő karaktereket szedi ki




words_around_putin <- function(text) {
  putin_position <- str_locate(tolower(text), "\\bputyin\\b")
  
  if (!is.na(putin_position[1, 1])) {
    start_position <- max(1, putin_position[1, 1] - 300)
    end_position <- min(nchar(text), putin_position[1, 2] + 300)
    
    surrounding_words <- str_extract_all(str_sub(text, start_position, end_position), "\\w+")
    
    return(paste(surrounding_words[[1]], collapse = " "))
  } else {
    return('')
  }
}

# Apply the function to create a new column
index_mutated_data1$surrounding_words <- sapply(index_mutated_data1$text, words_around_putin)

head(index_mutated_data1$surrounding_words,5)

# Most már van egy oszlopunk a putyin közeli szavakkal.
# Ezen az oszlopon is lefuttatom a lemmatizálást

# 2.1) Making a new corpus

corpus2 <-  quanteda::corpus(index_mutated_data1$surrounding_words)


corpus2_filt <- corpus2 %>% 
  quanteda::tokens(remove_punct = TRUE, remove_symbols = TRUE, remove_numbers = TRUE, remove_url = TRUE) %>%
  quanteda::tokens_tolower()



# 2.2.) Tokenizing the text

index_toks2 <- quanteda::tokens(corpus2_filt)

index_toks2 <- quanteda::tokens_tolower(index_toks2)

index_toks2 <- quanteda::tokens_wordstem(index_toks2)



# 2.3.) lemmatizing the words

index_lem_toks2 <- index_toks2 %>% 
  quanteda::tokens_replace(pattern = lexicon::hash_lemmas$token,
                           replacement = lexicon::hash_lemmas$lemma)



# 2.4.) sopword removal, so the analysis will not have too much junk


index_lem_sw2 <- index_lem_toks2 %>% 
  quanteda::tokens_remove(sw_hu)


#putting it all in one clean df

listrr<-list(index_lem_sw2)[[1]]

cleantext2<-lapply(listrr,function(x)paste(x,collapse=" "))%>%unlist()

index_clean_df2<-index_mutated_data1

index_clean_df2$surrounding_words<-cleantext2


# if needed save the df
# write.csv(index_clean_df1,"clean_putin_filtered2.csv")


#checking
print(cleantext2[1])


# 2.5.) Making a dfm

index_dfm_clean2 <- cleantext2 %>%
  tokens() %>%
  dfm(
    remove_punct = TRUE,
    remove_numbers = TRUE,
    remove = stopwords(language = "hungarian"),
    verbose = quanteda_options("verbose")
  ) %>%
  dfm_tfidf()



# if needed save the dfm2
# write.csv(as.matrix(index_dfm_clean1), file = "putin_dfm2.csv")


## TopFeatures

quanteda::topfeatures(index_dfm_clean2, 30)

index_dfm_clean2_sparse <- index_dfm_clean2 %>%
  quanteda::dfm_trim(min_termfreq = 0.001, termfreq_type = "prop")

quanteda::topfeatures(index_dfm_clean2_sparse, 30)




############################
#text analysis

########################################################


# 2.6) 

texts2 <- index_dfm_clean2$text

index_article_szentiment2 <- quanteda::dfm_lookup(index_dfm_clean2, dictionary = poltext_szotar)

head(index_article_szentiment2, 6)



docvars(index_dfm_clean2, "pos") <- as.numeric(index_article_szentiment2[, 1])
docvars(index_dfm_clean2, "neg") <- as.numeric(index_article_szentiment2[, 2])

head(docvars(index_dfm_clean2), 5)



# 2.7)

#Saving the sentiment scores to the main dataframe:

index_clean_df2$pos <- docvars(index_dfm_clean2, "pos")
index_clean_df2$neg <- docvars(index_dfm_clean2, "neg")

# Grouping the scores by the date column
index_clean_df2 <- index_clean_df2 %>%
  group_by(date) %>%
  summarise(
    daily_pos = sum(pos),
    daily_neg = sum(neg),
    net_daily = daily_pos - daily_neg
  )



# 2.9)

#plotting it all

corpu2_df_plot <- ggplot(data = index_clean_df2, aes(date, net_daily)) + 
  geom_line() +
  geom_smooth(method = "auto", se = FALSE, color = "darkorange1") +  # Add trendline
  labs(y = "Sentiment", x = "Date", caption = "Source: index.hu") +
  geom_vline(xintercept = as.Date(journalist_resign_date), linetype = "dashed", color = "deepskyblue4") +
  ggtitle("Az index.hu -putyin- kifejezést tartalmazó cikkjeinek 600 karakterének szentimentje Putyin neve körül")

print(corpu2_df_plot)


corpu2_df_plot <- ggplot(data = index_clean_df2, aes(x = date, y = net_daily)) +
  geom_line(color = "darkseagreen", show.legend = FALSE) +
  geom_smooth(method = "auto", se = FALSE, color = "darkorange1", show.legend = FALSE) +
  geom_vline(xintercept = as.Date(journalist_resign_date), linetype = "dashed", color = "deepskyblue4", show.legend = FALSE) +
  labs(y = "Sentiment", x = "Date", caption = "Source: index.hu") +
  ggtitle("Az index.hu -putyin- kifejezést tartalmazó cikkjeinek 600 karakterének szentimentje Putyin neve körül") +
  theme_minimal()

# Convert ggplot to plotly
corpu2_df_plot_interactive <- ggplotly(corpu2_df_plot, tooltip = c("y", "x"))

# Print the interactive plot
print(corpu2_df_plot_interactive)





#####################################################

#kiveszem belole a tul kevesszer/gyakran elofordulo dolgokat

head(index_dfm_clean1, 5)






tokens_clean1 <- tokens(cleantext1)


quanteda::topfeatures(dfm(tokens_clean1), 30)


index_dfm_clean1_sparse <- dfm(tokens_clean1) %>%
  quanteda::dfm_trim(min_termfreq = 0.001, termfreq_type = "prop")

head(index_dfm_clean1_sparse,5)

quanteda::topfeatures(index_dfm_clean1_sparse, 30)




top_tokens <- textstat_frequency(
  index_dfm_clean1_sparse,
  n = 15,
  groups = docvars(index_dfm_clean1_sparse, field = date )
)


library(purrr)
library(topicmodels)

k_topics <- c(5, 8, 10, 15)


index_dfm_clean1_sparse <- k_topics %>%
  purrr::map(topicmodels::LDA, x = index_dfm_clean1_sparse, control = list())




perp_df <- dplyr::tibble(
  k = k_topics,
  perplexity = purrr::map_dbl(index_dfm_clean1_sparse, topicmodels::perplexity)
)


perp_df_plot <- ggplot(perp_df, aes(k, perplexity)) +
  geom_point() +
  geom_line() +
  labs(
    x = "Klaszterek száma",
    y = "Zavarosság"
  )

ggplotly(perp_df_plot)

str(index_dfm_clean1_sparse)


vem_index <- LDA(index_dfm_clean1_sparse, k = 10, method = "VEM", control = list())


vem_index <- LDA(index_dfm_clean1_sparse, k = 7, method = "VEM", control = list())



vem_index <- index_dfm_clean1_sparse[[2]]

em_index <- LDA(index_dfm_clean1_sparse[[2]], k = 10, method = "VEM", control = list())

beta_matrix <- as(matrix(vem_index@beta, nrow = nterms(vem_index), ncol = k), "matrix")



topics_index_dfm_clean1_sparse <- tidytext::tidy(index_dfm_clean1_sparse, matrix = "beta") %>%
  mutate(electoral_cycle = "1998-2002")

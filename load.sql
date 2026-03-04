-- \copy movies(movie_id, title, genres)        FROM '/Users/olga/DataGripProjects/ml-32m/movies.csv'  CSV HEADER ENCODING 'UTF8'
-- \copy ratings(user_id, movie_id, rating, ts) FROM '/Users/olga/DataGripProjects/ml-32m/ratings.csv' CSV HEADER ENCODING 'UTF8'
-- \copy tags(user_id, movie_id, tag, ts)       FROM '/Users/olga/DataGripProjects/ml-32m/tags.csv'    CSV HEADER ENCODING 'UTF8'
-- \copy links(movie_id, imdb_id, tmdb_id)      FROM '/Users/olga/DataGripProjects/ml-32m/links.csv'   CSV HEADER ENCODING 'UTF8'
SELECT 'movies'  AS таблица, COUNT(*) AS строк FROM movies
UNION ALL
SELECT 'ratings',            COUNT(*)           FROM ratings
UNION ALL
SELECT 'tags',               COUNT(*)           FROM tags
UNION ALL
SELECT 'links',              COUNT(*)           FROM links;

-- Ожидаемый результат:
--   таблица  |  строк
---------+----------
--  movies    |    87585
--  ratings   | 32000204
--  tags      |  2000072
--  links     |    87585
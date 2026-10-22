CREATE DATABASE IF NOT EXISTS taobao_ods;
USE taobao_ods;

CREATE TABLE IF NOT EXISTS user_behavior (
    user_id BIGINT,
    item_id BIGINT,
    category_id BIGINT,
    behavior_type STRING,
    ts BIGINT
)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ','
STORED AS TEXTFILE;

LOAD DATA LOCAL INPATH '/mnt/d/JupyterNoteBook/portfolio/Project1/data/UserBehavior.csv'
OVERWRITE INTO TABLE user_behavior;
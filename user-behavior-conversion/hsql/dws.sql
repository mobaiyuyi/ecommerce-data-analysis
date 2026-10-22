CREATE DATABASE IF NOT EXISTS taobao_dws;
USE taobao_dws;

set hive.exec.dynamic.partition=true;
set hive.exec.dynamic.partition.mode=nonstrict;
set hive.map.aggr=true;
set mapreduce.job.reduces=16;
set hive.exec.max.dynamic.partitions=5000;
set hive.exec.max.dynamic.partitions.pernode=5000;

--数据只有9天窗口，按日汇总，不做月聚合
--用户日汇总
DROP TABLE IF EXISTS dws_user_behavior_1d;
CREATE TABLE IF NOT EXISTS dws_user_behavior_1d (
    user_id      BIGINT,
    pv_cnt       BIGINT,
    cart_cnt     BIGINT,
    fav_cnt      BIGINT,
    buy_cnt      BIGINT,
    pv_item_cnt  BIGINT,
    buy_item_cnt BIGINT,
    first_ts     BIGINT,
    last_ts      BIGINT
) PARTITIONED BY (dt STRING) STORED AS ORC;

insert overwrite table dws_user_behavior_1d partition(dt)
select
    user_id,
    sum(if(behavior_type='pv',1,0)) as pv_cnt,
    sum(if(behavior_type='cart',1,0)) as cart_cnt,
    sum(if(behavior_type='fav',1,0)) as fav_cnt,
    sum(if(behavior_type='buy',1,0)) as buy_cnt,
    count(distinct if(behavior_type='pv',item_id,null)) as pv_item_cnt,
    count(distinct if(behavior_type='buy',item_id,null)) as buy_item_cnt,
    min(ts) as first_ts,
    max(ts) as last_ts,
    dt
from taobao_dwd.dwd_user_behavior
group by user_id, dt;

--商品日汇总
DROP TABLE IF EXISTS dws_item_behavior_1d;
CREATE TABLE IF NOT EXISTS dws_item_behavior_1d (
    item_id     BIGINT,
    category_id BIGINT,
    pv_cnt      BIGINT,
    pv_uv       BIGINT,
    cart_cnt    BIGINT,
    cart_uv     BIGINT,
    fav_cnt     BIGINT,
    fav_uv      BIGINT,
    buy_cnt     BIGINT,
    buy_uv      BIGINT
) PARTITIONED BY (dt STRING) STORED AS ORC;

--item多条类目时取max
insert overwrite table dws_item_behavior_1d partition(dt)
select
    item_id,
    max(category_id) as category_id,
    sum(if(behavior_type='pv',1,0)) as pv_cnt,
    count(distinct if(behavior_type='pv',user_id,null)) as pv_uv,
    sum(if(behavior_type='cart',1,0)) as cart_cnt,
    count(distinct if(behavior_type='cart',user_id,null)) as cart_uv,
    sum(if(behavior_type='fav',1,0)) as fav_cnt,
    count(distinct if(behavior_type='fav',user_id,null)) as fav_uv,
    sum(if(behavior_type='buy',1,0)) as buy_cnt,
    count(distinct if(behavior_type='buy',user_id,null)) as buy_uv,
    dt
from taobao_dwd.dwd_user_behavior
group by item_id, dt;

--用户商品日汇总
DROP TABLE IF EXISTS dws_user_item_behavior_1d;
CREATE TABLE IF NOT EXISTS dws_user_item_behavior_1d (
    user_id     BIGINT,
    item_id     BIGINT,
    category_id BIGINT,
    pv_cnt      BIGINT,
    cart_cnt    BIGINT,
    fav_cnt     BIGINT,
    buy_cnt     BIGINT,
    first_ts    BIGINT,
    last_ts     BIGINT
) PARTITIONED BY (dt STRING) STORED AS ORC;

insert overwrite table dws_user_item_behavior_1d partition(dt)
select
    user_id,
    item_id,
    max(category_id) as category_id,
    sum(if(behavior_type='pv',1,0)) as pv_cnt,
    sum(if(behavior_type='cart',1,0)) as cart_cnt,
    sum(if(behavior_type='fav',1,0)) as fav_cnt,
    sum(if(behavior_type='buy',1,0)) as buy_cnt,
    min(ts) as first_ts,
    max(ts) as last_ts,
    dt
from taobao_dwd.dwd_user_behavior
group by user_id, item_id, dt;

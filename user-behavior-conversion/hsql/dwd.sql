CREATE DATABASE IF NOT EXISTS taobao_dwd;
USE taobao_dwd;

set hive.exec.dynamic.partition=true;
set hive.exec.dynamic.partition.mode=nonstrict;
set hive.map.aggr=true;
set mapreduce.job.reduces=16;
set hive.exec.max.dynamic.partitions=5000;
set hive.exec.max.dynamic.partitions.pernode=5000;

--行为事实表
DROP TABLE IF EXISTS dwd_user_behavior;
CREATE TABLE IF NOT EXISTS dwd_user_behavior (
    user_id       BIGINT,
    item_id       BIGINT,
    category_id   BIGINT,
    behavior_type STRING,
    ts            BIGINT,
    date_id       INT
) PARTITIONED BY (dt STRING) STORED AS ORC;

--原始时间戳按北京时间，容器JVM是UTC，统一加8小时对齐，否则日期整体早一天
insert overwrite table dwd_user_behavior partition(dt)
select
    t.user_id,
    t.item_id,
    t.category_id,
    t.behavior_type,
    t.ts,
    cast(from_unixtime(t.ts + 28800,'yyyyMMdd') as int) as date_id,
    from_unixtime(t.ts + 28800,'yyyy-MM-dd') as dt
from (
    select
        user_id,
        item_id,
        category_id,
        lower(trim(behavior_type)) as behavior_type,
        ts
    from taobao_ods.user_behavior
    where user_id is not null
      and item_id is not null
      and category_id is not null
      and ts is not null
      and user_id > 0
      and item_id > 0
      and category_id > 0
      and ts > 0
      and from_unixtime(ts + 28800,'yyyy-MM-dd') between '2017-11-25' and '2017-12-03'
      and lower(trim(behavior_type)) in ('pv','buy','cart','fav')
    group by user_id,item_id,category_id,lower(trim(behavior_type)),ts
) t;

--日期维度表
DROP TABLE IF EXISTS dim_date;
CREATE TABLE IF NOT EXISTS dim_date (
    date_id  INT,
    date_str STRING,
    year     INT,
    month    INT,
    day      INT,
    weekday  INT
) STORED AS ORC;

insert overwrite table dim_date
select
    cast(replace(dt,'-','') as int) as date_id,
    dt as date_str,
    year(to_date(dt)) as year,
    month(to_date(dt)) as month,
    day(to_date(dt)) as day,
    dayofweek(to_date(dt)) as weekday
from (
    select distinct dt from dwd_user_behavior
) p;

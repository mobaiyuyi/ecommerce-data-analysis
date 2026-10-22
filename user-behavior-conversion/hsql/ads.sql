USE taobao_ads;

set hive.map.aggr=true;
set mapreduce.job.reduces=16;
set hive.vectorized.execution.enabled=false;
set hive.vectorized.execution.reduce.enabled=false;

--数据只有9天连续窗口(2017-11-24~2017-12-03)，所有指标按整窗口算
--不再按月切分，避免7天对3天的时间不公平

--窗口用户表，后面所有人群口径都基于它
DROP TABLE IF EXISTS tmp_user_window;
CREATE TABLE IF NOT EXISTS tmp_user_window (
    user_id          BIGINT,
    pv_cnt           BIGINT,
    cart_cnt         BIGINT,
    fav_cnt          BIGINT,
    buy_cnt          BIGINT,
    last_interest_ts BIGINT,
    last_buy_ts      BIGINT,
    buy_rate         DOUBLE
) STORED AS ORC;

insert overwrite table tmp_user_window
select
    u.user_id,
    u.pv_cnt,
    u.cart_cnt,
    u.fav_cnt,
    u.buy_cnt,
    i.last_interest_ts,
    i.last_buy_ts,
    if(u.pv_cnt=0, 0, u.buy_cnt * 1.0 / u.pv_cnt) as buy_rate
from (
    select user_id,
           sum(pv_cnt) as pv_cnt,
           sum(cart_cnt) as cart_cnt,
           sum(fav_cnt) as fav_cnt,
           sum(buy_cnt) as buy_cnt
    from taobao_dws.dws_user_behavior_1d
    group by user_id
) u
left join (
    select user_id,
           max(if(behavior_type in ('cart','fav'), ts, null)) as last_interest_ts,
           max(if(behavior_type='buy', ts, null)) as last_buy_ts
    from taobao_dwd.dwd_user_behavior
    group by user_id
) i on u.user_id = i.user_id;

--分位阈值，换数据自动重算，不写死
DROP TABLE IF EXISTS tmp_pv75;
CREATE TABLE IF NOT EXISTS tmp_pv75 (pv_p75 BIGINT) STORED AS ORC;
insert overwrite table tmp_pv75
select cast(percentile_approx(pv_cnt,0.75) as bigint) from tmp_user_window;

DROP TABLE IF EXISTS tmp_rate25;
CREATE TABLE IF NOT EXISTS tmp_rate25 (rate_p25 DOUBLE) STORED AS ORC;
insert overwrite table tmp_rate25
select percentile_approx(u.buy_rate,0.25)
from tmp_user_window u
cross join tmp_pv75 t
where u.pv_cnt >= t.pv_p75
  and u.buy_cnt > 0;

--整体转化M1
DROP TABLE IF EXISTS ads_overall_conversion;
CREATE TABLE IF NOT EXISTS ads_overall_conversion (
    window_start    STRING,
    window_end      STRING,
    pv_uv           BIGINT,
    buy_uv          BIGINT,
    pv_buy_rate     DECIMAL(10,4),
    repurchase_rate DECIMAL(10,4)
) STORED AS ORC;

insert overwrite table ads_overall_conversion
select
    d.ws as window_start,
    d.we as window_end,
    sum(if(u.pv_cnt>0,1,0)) as pv_uv,
    sum(if(u.buy_cnt>0,1,0)) as buy_uv,
    cast(sum(if(u.buy_cnt>0,1,0)) / sum(if(u.pv_cnt>0,1,0)) as decimal(10,4)) as pv_buy_rate,
    cast(sum(if(u.buy_cnt>=2,1,0)) / sum(if(u.buy_cnt>0,1,0)) as decimal(10,4)) as repurchase_rate
from tmp_user_window u
cross join (
    select min(dt) as ws, max(dt) as we
    from taobao_dws.dws_user_behavior_1d
) d
group by d.ws, d.we;

--日趋势，总览页用
DROP TABLE IF EXISTS ads_daily_trend;
CREATE TABLE IF NOT EXISTS ads_daily_trend (
    stat_date STRING,
    pv_cnt    BIGINT,
    pv_uv     BIGINT,
    buy_cnt   BIGINT,
    buy_uv    BIGINT,
    buy_rate  DECIMAL(10,4)
) STORED AS ORC;

insert overwrite table ads_daily_trend
select
    dt as stat_date,
    sum(pv_cnt) as pv_cnt,
    sum(if(pv_cnt>0,1,0)) as pv_uv,
    sum(buy_cnt) as buy_cnt,
    sum(if(buy_cnt>0,1,0)) as buy_uv,
    cast(sum(buy_cnt) / sum(pv_cnt) as decimal(10,4)) as buy_rate
from taobao_dws.dws_user_behavior_1d
group by dt;

--用户人群M2-1 M2-2
--高点击=pv>=P75
--高点击低购买=高点击且buy_rate<=高点击人群P25，排除完全未购买
--cart_buy_rate=最后一次加购收藏之后还买过的用户/有加购收藏的用户
--必须先加购后购买，按ts判断，不能只看buy_cnt
DROP TABLE IF EXISTS ads_user_segment;
CREATE TABLE IF NOT EXISTS ads_user_segment (
    segment_name  STRING,
    user_cnt      BIGINT,
    pv_uv         BIGINT,
    buy_uv        BIGINT,
    cart_fav_uv   BIGINT,
    pv_cnt        BIGINT,
    buy_cnt       BIGINT,
    convert_rate  DECIMAL(10,4),
    buy_rate      DECIMAL(10,4),
    cart_buy_rate DECIMAL(10,4)
) STORED AS ORC;

insert overwrite table ads_user_segment
select '全站' as segment_name,
       count(*) as user_cnt,
       sum(if(pv_cnt>0,1,0)) as pv_uv,
       sum(if(buy_cnt>0,1,0)) as buy_uv,
       sum(if(cart_cnt+fav_cnt>0,1,0)) as cart_fav_uv,
       sum(pv_cnt) as pv_cnt,
       sum(buy_cnt) as buy_cnt,
       cast(sum(if(buy_cnt>0,1,0)) / count(*) as decimal(10,4)) as convert_rate,
       cast(sum(buy_cnt) / sum(pv_cnt) as decimal(10,4)) as buy_rate,
       cast(if(count(if(last_interest_ts is not null,1,null))=0, 0,
           count(if(last_interest_ts is not null and last_buy_ts>last_interest_ts,1,null)) * 1.0
           / count(if(last_interest_ts is not null,1,null))) as decimal(10,4)) as cart_buy_rate
from tmp_user_window
union all
select '高点击人群' as segment_name,
       count(*) as user_cnt,
       sum(if(pv_cnt>0,1,0)) as pv_uv,
       sum(if(buy_cnt>0,1,0)) as buy_uv,
       sum(if(cart_cnt+fav_cnt>0,1,0)) as cart_fav_uv,
       sum(pv_cnt) as pv_cnt,
       sum(buy_cnt) as buy_cnt,
       cast(sum(if(buy_cnt>0,1,0)) / count(*) as decimal(10,4)) as convert_rate,
       cast(sum(buy_cnt) / sum(pv_cnt) as decimal(10,4)) as buy_rate,
       cast(if(count(if(last_interest_ts is not null,1,null))=0, 0,
           count(if(last_interest_ts is not null and last_buy_ts>last_interest_ts,1,null)) * 1.0
           / count(if(last_interest_ts is not null,1,null))) as decimal(10,4)) as cart_buy_rate
from tmp_user_window u
cross join tmp_pv75 t
where u.pv_cnt >= t.pv_p75
union all
select '高意向人群' as segment_name,
       count(*) as user_cnt,
       sum(if(pv_cnt>0,1,0)) as pv_uv,
       sum(if(buy_cnt>0,1,0)) as buy_uv,
       sum(if(cart_cnt+fav_cnt>0,1,0)) as cart_fav_uv,
       sum(pv_cnt) as pv_cnt,
       sum(buy_cnt) as buy_cnt,
       cast(sum(if(buy_cnt>0,1,0)) / count(*) as decimal(10,4)) as convert_rate,
       cast(sum(buy_cnt) / sum(pv_cnt) as decimal(10,4)) as buy_rate,
       cast(if(count(if(last_interest_ts is not null,1,null))=0, 0,
           count(if(last_interest_ts is not null and last_buy_ts>last_interest_ts,1,null)) * 1.0
           / count(if(last_interest_ts is not null,1,null))) as decimal(10,4)) as cart_buy_rate
from tmp_user_window
where cart_cnt + fav_cnt > 0
union all
select '高点击低购买' as segment_name,
       count(*) as user_cnt,
       sum(if(pv_cnt>0,1,0)) as pv_uv,
       sum(if(buy_cnt>0,1,0)) as buy_uv,
       sum(if(cart_cnt+fav_cnt>0,1,0)) as cart_fav_uv,
       sum(pv_cnt) as pv_cnt,
       sum(buy_cnt) as buy_cnt,
       cast(sum(if(buy_cnt>0,1,0)) / count(*) as decimal(10,4)) as convert_rate,
       cast(sum(buy_cnt) / sum(pv_cnt) as decimal(10,4)) as buy_rate,
       cast(if(count(if(last_interest_ts is not null,1,null))=0, 0,
           count(if(last_interest_ts is not null and last_buy_ts>last_interest_ts,1,null)) * 1.0
           / count(if(last_interest_ts is not null,1,null))) as decimal(10,4)) as cart_buy_rate
from tmp_user_window u
cross join tmp_pv75 t
cross join tmp_rate25 r
where u.pv_cnt >= t.pv_p75
  and u.buy_cnt > 0
  and u.buy_rate <= r.rate_p25
union all
select '高意向未成交' as segment_name,
       count(*) as user_cnt,
       sum(if(pv_cnt>0,1,0)) as pv_uv,
       0 as buy_uv,
       sum(if(cart_cnt+fav_cnt>0,1,0)) as cart_fav_uv,
       sum(pv_cnt) as pv_cnt,
       0 as buy_cnt,
       cast(0 as decimal(10,4)) as convert_rate,
       cast(0 as decimal(10,4)) as buy_rate,
       cast(0 as decimal(10,4)) as cart_buy_rate
from tmp_user_window
where cart_cnt + fav_cnt > 0
  and buy_cnt = 0;

--高流量低转化商品M2-3 M3-3
--pv>=P80且buy_rate低于窗口平均
DROP TABLE IF EXISTS tmp_item_window;
CREATE TABLE IF NOT EXISTS tmp_item_window (
    item_id       BIGINT,
    category_id   BIGINT,
    pv_cnt        BIGINT,
    pv_uv         BIGINT,
    cart_fav_cnt  BIGINT,
    buy_cnt       BIGINT,
    buy_rate      DOUBLE
) STORED AS ORC;

insert overwrite table tmp_item_window
select item_id, category_id, pv_cnt, pv_uv, cart_fav_cnt, buy_cnt,
       if(pv_cnt=0, 0, buy_cnt * 1.0 / pv_cnt) as buy_rate
from (
    select item_id,
           max(category_id) as category_id,
           sum(pv_cnt) as pv_cnt,
           count(distinct if(pv_cnt>0,user_id,null)) as pv_uv,
           sum(cart_cnt) + sum(fav_cnt) as cart_fav_cnt,
           sum(buy_cnt) as buy_cnt
    from taobao_dws.dws_user_item_behavior_1d
    group by item_id
) x;

DROP TABLE IF EXISTS tmp_item80;
CREATE TABLE IF NOT EXISTS tmp_item80 (pv_p80 BIGINT, avg_buy_rate DOUBLE) STORED AS ORC;
insert overwrite table tmp_item80
select cast(percentile_approx(pv_cnt,0.8) as bigint) as pv_p80,
       sum(buy_cnt) * 1.0 / sum(pv_cnt) as avg_buy_rate
from tmp_item_window;

DROP TABLE IF EXISTS ads_item_high_traffic;
CREATE TABLE IF NOT EXISTS ads_item_high_traffic (
    item_id         BIGINT,
    category_id     BIGINT,
    pv_cnt          BIGINT,
    pv_uv           BIGINT,
    buy_cnt         BIGINT,
    cart_fav_cnt    BIGINT,
    buy_rate        DECIMAL(10,4),
    cart_fav_rate   DECIMAL(10,4),
    category_pv_cnt BIGINT,
    exposure_rate   DECIMAL(10,4)
) STORED AS ORC;

insert overwrite table ads_item_high_traffic
select
    i.item_id,
    i.category_id,
    i.pv_cnt,
    i.pv_uv,
    i.buy_cnt,
    i.cart_fav_cnt,
    cast(i.buy_rate as decimal(10,4)) as buy_rate,
    cast(if(i.cart_fav_cnt=0, 0, i.buy_cnt * 1.0 / i.cart_fav_cnt) as decimal(10,4)) as cart_fav_rate,
    c.category_pv_cnt,
    cast(i.pv_cnt * 1.0 / c.category_pv_cnt as decimal(10,4)) as exposure_rate
from tmp_item_window i
cross join tmp_item80 t
join (
    select category_id, sum(pv_cnt) as category_pv_cnt
    from taobao_dws.dws_item_behavior_1d
    group by category_id
) c on i.category_id = c.category_id
where i.pv_cnt >= t.pv_p80
  and i.buy_rate < t.avg_buy_rate;

--推荐名单M3
--高点击低购买用户 x 窗口内有行为的商品，商品限定类目转化率前25%
DROP TABLE IF EXISTS ads_recommend_list;
CREATE TABLE IF NOT EXISTS ads_recommend_list (
    user_id     BIGINT,
    item_id     BIGINT,
    category_id BIGINT,
    pv_cnt      BIGINT,
    cart_cnt    BIGINT,
    fav_cnt     BIGINT,
    buy_cnt     BIGINT
) STORED AS ORC;

insert overwrite table ads_recommend_list
select u.user_id, b.item_id, b.category_id, b.pv_cnt, b.cart_cnt, b.fav_cnt, b.buy_cnt
from (
    select user_id
    from tmp_user_window u
    cross join tmp_pv75 t
    cross join tmp_rate25 r
    where u.pv_cnt >= t.pv_p75
      and u.buy_cnt > 0
      and u.buy_rate <= r.rate_p25
) u
join (
    select user_id, item_id, max(category_id) as category_id,
           sum(pv_cnt) as pv_cnt, sum(cart_cnt) as cart_cnt,
           sum(fav_cnt) as fav_cnt, sum(buy_cnt) as buy_cnt
    from taobao_dws.dws_user_item_behavior_1d
    group by user_id, item_id
) b on u.user_id = b.user_id
join (
    select category_id
    from (
        select category_id,
               row_number() over (order by buy_rate desc, pv_cnt desc) as rn,
               count(*) over () as cat_cnt
        from (
            select category_id, sum(buy_cnt) * 1.0 / sum(pv_cnt) as buy_rate, sum(pv_cnt) as pv_cnt
            from taobao_dws.dws_item_behavior_1d
            group by category_id
        ) c
    ) d
    where rn <= ceil(cat_cnt * 0.25)
) k on b.category_id = k.category_id
where b.pv_cnt + b.cart_cnt + b.fav_cnt > 0;

--推荐效果M3-1 M3-2
DROP TABLE IF EXISTS ads_recommend_effect;
CREATE TABLE IF NOT EXISTS ads_recommend_effect (
    rec_item_cnt  BIGINT,
    exposure_uv   BIGINT,
    buy_uv        BIGINT,
    exposure_rate DECIMAL(10,4),
    buy_rate      DECIMAL(10,4)
) STORED AS ORC;

insert overwrite table ads_recommend_effect
select
    count(*) as rec_item_cnt,
    count(distinct if(l.pv_cnt>0,l.user_id,null)) as exposure_uv,
    count(distinct if(l.buy_cnt>0,l.user_id,null)) as buy_uv,
    cast(count(distinct if(l.pv_cnt>0,l.user_id,null)) / s.user_cnt as decimal(10,4)) as exposure_rate,
    cast(sum(if(l.buy_cnt>0,1,0)) / sum(if(l.pv_cnt>0,1,0)) as decimal(10,4)) as buy_rate
from ads_recommend_list l
cross join (
    select user_cnt from ads_user_segment where segment_name='高点击低购买'
) s
group by s.user_cnt;

--漏斗用，行为次数口径
--pv→cart/fav→buy三段独立计数，buy不要求先加购收藏
DROP TABLE IF EXISTS ads_funnel;
CREATE TABLE IF NOT EXISTS ads_funnel (
    stage_name STRING,
    stage_no   INT,
    cnt        BIGINT
) STORED AS ORC;

insert overwrite table ads_funnel
select '1 浏览' as stage_name, 1 as stage_no, sum(pv_cnt) as cnt
from taobao_dws.dws_user_behavior_1d
union all
select '2 加购/收藏', 2 as stage_no, sum(cart_cnt + fav_cnt) as cnt
from taobao_dws.dws_user_behavior_1d
union all
select '3 购买', 3 as stage_no, sum(buy_cnt) as cnt
from taobao_dws.dws_user_behavior_1d;

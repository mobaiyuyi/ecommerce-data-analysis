# ADS 表字段说明

窗口：2017-11-25 ~ 2017-12-03，连续 9 天。所有指标都在这一个窗口里算，没有月度切分。

表在 Hive 里是 `taobao_ads` 库，同步到 ClickHouse 后表名、字段名不变。

先分清两个转化率，混了整张报表就错：

- **行为转化率**：购买次数 / 浏览次数，看的是流量效率，量级 2% 左右
- **人数转化率**：购买人数 / 人群人数，看的是人群覆盖面，量级 68% 左右

两者分母不同，不能互相比较，也不能相互除。

## ads_overall_conversion

整窗口汇总，只有 1 行。

| 字段 | 类型 | 含义 |
|---|---|---|
| window_start | STRING | 窗口起始日，固定 2017-11-25 |
| window_end | STRING | 窗口结束日，固定 2017-12-03 |
| pv_uv | BIGINT | 窗口内有浏览行为的去重用户数，98.41 万 |
| buy_uv | BIGINT | 窗口内有购买行为的去重用户数，67.24 万 |
| pv_buy_rate | DECIMAL(10,4) | 购买用户渗透率 M1 = buy_uv / pv_uv，0.6806 |
| repurchase_rate | DECIMAL(10,4) | 复购率 = 购买次数≥2 的用户 / buy_uv |

注意：这张表没有行为转化率。2.25% 要从 `ads_daily_trend` 汇总算，见文末示例。

## ads_daily_trend

日粒度，9 行，一天一行。

| 字段 | 类型 | 含义 |
|---|---|---|
| stat_date | STRING | 日期，2017-11-25 这种格式 |
| pv_cnt | BIGINT | 当日浏览次数合计 |
| pv_uv | BIGINT | 当日有浏览的去重用户数 |
| buy_cnt | BIGINT | 当日购买次数合计 |
| buy_uv | BIGINT | 当日有购买的去重用户数 |
| buy_rate | DECIMAL(10,4) | 当日行为转化率 = buy_cnt / pv_cnt |

注意：日 uv 相加不等于窗口 uv，用户会跨天重复。跨天去重只在 `ads_overall_conversion` 里有。

## ads_user_segment

人群维度，5 行。`segment_name` 五个取值：全站、高点击人群、高意向人群、高点击低购买、高意向未成交。

| 字段 | 类型 | 含义 |
|---|---|---|
| segment_name | STRING | 人群名称 |
| user_cnt | BIGINT | 该人群去重用户数，分母基数 |
| pv_uv | BIGINT | 该人群里有浏览的用户数 |
| buy_uv | BIGINT | 该人群里有购买的用户数 |
| cart_fav_uv | BIGINT | 该人群里有加购或收藏的用户数 |
| pv_cnt | BIGINT | 该人群浏览次数合计 |
| buy_cnt | BIGINT | 该人群购买次数合计 |
| convert_rate | DECIMAL(10,4) | 人数转化率 = buy_uv / user_cnt |
| buy_rate | DECIMAL(10,4) | 行为转化率 = buy_cnt / pv_cnt，人群页用这个 |
| cart_buy_rate | DECIMAL(10,4) | 加购后购买率 M2-2，见下 |

人群定义：

- 高点击人群：pv_cnt ≥ 全站用户 pv 的 P75
- 高点击低购买：高点击，且 buy_rate ≤ 高点击人群 buy_rate 的 P25，且窗口内买过至少一次
- 高意向人群：加购次数 + 收藏次数 > 0
- 高意向未成交：有加购或收藏，且购买次数为 0

`cart_buy_rate` 口径：有加购或收藏的用户里，**最后一次加购/收藏之后还发生过购买**的用户占比，按 ts 判断先后。不是 `buy_cnt>0` 的占比，先买后加购的人不算。全站 23.15%。

注意：`高意向未成交` 这一行的 buy_uv、buy_cnt、convert_rate、buy_rate、cart_buy_rate 全部被写成 0，因为按定义它就没买。不要拿这一行当分母或基准做对比。

## ads_item_high_traffic

高流量低转化商品，约 59.70 万行，一行一个商品。

筛选条件：商品 pv ≥ 全站商品 pv 的 P80，且商品 buy_rate 低于全窗口商品加权平均 buy_rate。

| 字段 | 类型 | 含义 |
|---|---|---|
| item_id | BIGINT | 商品 ID |
| category_id | BIGINT | 所属类目 ID，同商品多类目时取 max |
| pv_cnt | BIGINT | 窗口内该商品浏览次数 |
| pv_uv | BIGINT | 浏览过该商品的去重用户数 |
| buy_cnt | BIGINT | 该商品购买次数 |
| cart_fav_cnt | BIGINT | 加购次数 + 收藏次数 |
| buy_rate | DECIMAL(10,4) | 该商品行为转化率 = buy_cnt / pv_cnt |
| cart_fav_rate | DECIMAL(10,4) | M3-3，加购收藏转化 = buy_cnt / cart_fav_cnt，5.66%~6.83% |
| category_pv_cnt | BIGINT | 该商品所属类目的窗口浏览总量 |
| exposure_rate | DECIMAL(10,4) | M2-3，该商品占类目浏览的份额 = pv_cnt / category_pv_cnt |

注意：`exposure_rate` 是商品在类目内部的占比，不是全站曝光占比。全站口径要自己用 pv_cnt 汇总算。

## ads_recommend_list

推荐名单明细，约 46.28 万行，一行是一个「用户 × 商品」对。

| 字段 | 类型 | 含义 |
|---|---|---|
| user_id | BIGINT | 高点击低购买人群的用户 |
| item_id | BIGINT | 该用户有行为的商品 |
| category_id | BIGINT | 商品所属类目 |
| pv_cnt | BIGINT | 该用户对该商品的浏览次数 |
| cart_cnt | BIGINT | 该用户对该商品的加购次数 |
| fav_cnt | BIGINT | 该用户对该商品的收藏次数 |
| buy_cnt | BIGINT | 该用户对该商品的购买次数 |

名单生成规则：用户取高点击低购买人群；商品只保留该用户窗口内有行为的商品，且商品类目属于类目转化率前 25%。

注意：这是历史窗口的回测名单，不是线上实时推荐结果。名单里包含用户已经买过的商品对，算转化时按「有购买的对 / 有浏览的对」处理。

## ads_recommend_effect

推荐效果汇总，只有 1 行。

| 字段 | 类型 | 含义 |
|---|---|---|
| rec_item_cnt | BIGINT | 名单内用户商品对数量，462,840 |
| exposure_uv | BIGINT | 名单内被曝光的去重用户数，41,771 |
| buy_uv | BIGINT | 名单内产生购买的去重用户数，8,169 |
| exposure_rate | DECIMAL(10,4) | M3-2，名单曝光覆盖率 = exposure_uv / 高点击低购买人群 uv，84.53% |
| buy_rate | DECIMAL(10,4) | M3-1，名单行为转化率 = 有购买的对数 / 有浏览的对数，1.97% |

注意：`buy_rate` 的分母是用户商品对（次数口径），`buy_uv` 是人数。这两个不能相除。想看人数转化要用 buy_uv / exposure_uv，那是另一个口径。

## 指标与表对应

| 指标 | 取哪张表 | 怎么算 |
|---|---|---|
| M0 行为转化率 | ads_daily_trend | sum(buy_cnt) / sum(pv_cnt)，全窗口 2.25% |
| M1 购买渗透率 | ads_overall_conversion | pv_buy_rate，68.06% |
| M2-1 高点击低购买人群转化 | ads_user_segment | segment_name='高点击低购买' 的 buy_rate，0.51% |
| M2-2 加购后购买率 | ads_user_segment | segment_name='全站' 的 cart_buy_rate，23.15% |
| M2-3 高流量低转化商品曝光率 | ads_item_high_traffic | 该批商品 sum(pv_cnt) / 类目 pv，加权 0.34% |
| M3-1 推荐商品转化率 | ads_recommend_effect | buy_rate，1.97% |
| M3-2 名单曝光覆盖率 | ads_recommend_effect | exposure_rate，84.53% |
| M3-3 商品加购收藏转化 | ads_item_high_traffic | buy_cnt / cart_fav_cnt，加权 7.33% |

## 常用取数

FineBI 或 ClickHouse 里建数据集，一律直接 select 表，不要再写 `select 49413+256012` 这种硬编码。

策略目标人群合计：

```sql
select sum(user_cnt) as cnt
from ads_user_segment
where segment_name in ('高点击低购买','高意向未成交');
```

全窗口行为转化率：

```sql
select sum(buy_cnt) / sum(pv_cnt) as buy_rate
from ads_daily_trend;
```

人群对比（按人数降序）：

```sql
select segment_name, user_cnt, pv_uv, buy_uv
from ads_user_segment
order by user_cnt desc;
```

商品 Top5（按浏览降序，只要前几条，避免拉全表）：

```sql
select item_id, category_id, pv_cnt, buy_cnt, buy_rate
from ads_item_high_traffic
order by pv_cnt desc
limit 5;
```

百分比字段存的是小数，0.0225 就是 2.25%。BI 里显示成百分比要么在图表格式里设，要么 SQL 里乘 100。

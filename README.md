# 电商数据分析项目

两个电商数据分析项目，一个看淘宝用户行为转化，一个看多平台店铺订单的 RFM 分层。每个项目一个目录，包含 SQL、Python、指标口径和报表。

## 项目索引

| 项目 | 业务问题 | 数据 | 方法 | 报表 |
|:--|:--|:--|:--|:--|
| [淘宝用户行为分析](./user-behavior-conversion/) | 浏览到购买的转化漏点在哪，人群和商品怎么拆 | 淘宝用户行为数据，约 1 亿行，2017-11-25 ~ 2017-12-03 | Hive 分层、漏斗、分位数分层、帕累托、四象限、回测 | [分析报表 PDF](./user-behavior-conversion/img/分析报表.pdf) |
| [电商店铺订单 RFM 用户分层分析](./rfm-analysis/) | 谁在撑起 GMV，谁正在离开 | 47.2 万条店铺订单明细，6 个平台，2024-01 ~ 2026-06 | RFM 八分层、新客与渠道拆解、数据质量校验 | [HTML 报表](./rfm-analysis/rfm-user-segmentation/rfm-user-segmentation.html) |

## 目录结构

```text
ecommerce-data-analysis/
├─ user-behavior-conversion/   淘宝用户行为分析
│  ├─ doc/                     分析思路、数据描述、ADS 字段说明
│  ├─ hsql/                    ODS、DWD、DWS、ADS 四层 SQL
│  └─ img/                     分析报表 PDF
└─ rfm-analysis/               电商店铺订单 RFM 用户分层分析
   ├─ data/metrics/            指标结果 CSV
   ├─ doc/                     OSM、指标体系、数据说明
   ├─ py/                      数据清洗、EDA、入库、指标运行
   ├─ rfm-user-segmentation/   HTML 报表与图表资源
   └─ sql/                     建表、校验、新客、RFM、沉睡用户 SQL
```

## 技术栈

Hive SQL、MySQL、Python（pandas）、FineBI、ECharts、Git。

## 阅读顺序

先看两个项目各自的 README，再进 `doc/` 看指标口径和分析思路，最后打开报表。每个项目的结论都放在报表开头，图表只作为证据。

## 数据说明

两个项目的原始数据都没有入库，原因是体积大。下载地址、字段说明和放置路径写在各自项目的 README 里。

两个项目都基于公开数据集做站内分析，结论用于展示分析过程，不代表真实业务大盘。淘宝项目的推荐回测没有对照组，`1.97%` 是回测值，不是增量。

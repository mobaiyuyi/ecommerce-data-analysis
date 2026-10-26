# 电商数据分析项目

两个电商数据分析项目，一个看淘宝用户行为转化，一个看多平台店铺订单的 RFM 分层。每个项目一个目录，包含 SQL、Python、指标口径和报表。

## 项目索引

| 项目 | 业务问题 | 数据 | 方法 | 报表 |
|:--|:--|:--|:--|:--|
| [淘宝用户行为分析](./user-behavior-conversion/) | 浏览到购买的转化漏点在哪，人群和商品怎么拆 | 淘宝用户行为数据，约 1 亿行 | Hive 数仓分层、漏斗、分位数分层、帕累托、四象限、回测 | [分析报表 PDF](./user-behavior-conversion/img/分析报表.pdf) |
| [电商店铺订单 RFM 用户分层分析](./rfm-analysis/) | 谁在撑起 GMV，谁正在离开 | 47.2 万条店铺订单明细，6 个平台 | RFM 八分层、新客与渠道拆解、数据质量校验 | [HTML 报表](./rfm-analysis/rfm-user-segmentation/rfm-user-segmentation.html) |

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




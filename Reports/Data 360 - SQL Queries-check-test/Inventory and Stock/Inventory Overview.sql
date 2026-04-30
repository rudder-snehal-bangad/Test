let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="WITH inventory_current_data AS
(
SELECT
product_id,
product_code,
warehouse,
warehouse_id,
SUM(quantity_on_hand) AS quantity_on_hand,
SUM(quantity_available) AS quantity_available,
SUM(quantity_inbound) AS quantity_inbound,
SUM(quantity_outbound) AS quantity_outbound
FROM " & BasePath & ".inventory_current
GROUP BY product_code, warehouse, warehouse_id, product_id
),

inventory_by_location AS
(
SELECT
product_id,
product_code,
warehouse_id,
warehouse_name AS warehouse,
SUM(quantity_on_hand) AS total_warehouse_qoh
FROM " & BasePath & ".inventory_by_location
GROUP BY product_code, warehouse, warehouse_id, product_id
),

inventory_moves_data AS
(
SELECT
product_id,
product_code,
from_warehouse_name AS warehouse,
from_warehouse AS warehouse_id,
SUM(CASE 
    WHEN to_location_name = 'Reserved Inventory' AND state = 'assigned' 
    THEN quantity ELSE 0 END) AS quantity_reserved,
SUM(CASE 
    WHEN to_location_type = 'storage' AND state = 'assigned' 
    THEN quantity ELSE 0 END) AS quantity_assigned
FROM " & BasePath & ".inventory_moves
WHERE state NOT IN ('cancel', 'done')
GROUP BY product_code, warehouse, product_id, warehouse_id
),


sales_data AS
(
SELECT
linessales.product_code,
product_id,
so.warehouse,
so.warehouse_id,
SUM(CASE WHEN so.state = 'done' AND linessales.line_type = 'sale' THEN linessales.quantity ELSE 0 END) AS quantity_sold,
SUM(CASE
WHEN so.state = 'done'
AND linessales.line_type = 'sale'
AND so.order_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
THEN linessales.quantity
ELSE 0
END) AS quantity_sold_30d,
SUM(CASE WHEN so.state = 'done' AND linessales.line_type = 'sale' THEN linessales.untaxed_amount_cpny_ccy_cache ELSE 0 END) AS gross_sale,
SUM(linessales.cost_price_cpny_ccy_cache) AS cost,
SUM(CASE WHEN so.state != 'cancel' THEN linessales.gross_profit_cpny_ccy_cache ELSE 0 END) AS gross_profit,
SUM(CASE WHEN so.state != 'cancel' AND linessales.line_type = 'return' THEN linessales.untaxed_amount_cpny_ccy_cache ELSE 0 END) AS credit
FROM " & BasePath & ".sales_orders so,
UNNEST(lines) AS linessales
WHERE so.order_date >= DATE_ADD(CURRENT_DATE(), INTERVAL -1 YEAR)
GROUP BY linessales.product_code, so.warehouse, product_id, so.warehouse_id
),

-- ✅ NEW CTEs (your logic)
sales_cte AS (
SELECT
so.order_date,
SUM(lines.quantity) AS quantity_sold,
lines.product_code
FROM " & BasePath & ".sales_orders AS so
LEFT JOIN UNNEST(so.lines) AS lines
WHERE
so.order_date >= DATE_ADD(
DATE_TRUNC(CURRENT_DATE(), MONTH),
INTERVAL -1 YEAR
)
GROUP BY product_code, order_date
),

product_summary AS (
SELECT
product_code,
SUM(quantity_sold) AS total_qty_sold,
MIN(order_date) AS first_order_date,
MAX(order_date) AS last_order_date,
DATE_DIFF(MAX(order_date), MIN(order_date), DAY) + 1 AS num_days
FROM sales_cte
GROUP BY product_code
)

SELECT
COALESCE(icd.product_id, sd.product_id, imd.product_id, ibl.product_id) AS product_id,
COALESCE(icd.product_code, sd.product_code, imd.product_code, ibl.product_code) AS product_code,
COALESCE(icd.warehouse, sd.warehouse, imd.warehouse, ibl.warehouse) AS warehouse,
COALESCE(icd.warehouse_id, sd.warehouse_id, imd.warehouse_id, ibl.warehouse_id) AS warehouse_id,

SUM(IFNULL(ibl.total_warehouse_qoh, 0)) AS total_warehouse_qoh,
SUM(IFNULL(icd.quantity_on_hand, 0)) AS quantity_on_hand,
SUM(IFNULL(icd.quantity_available, 0)) AS quantity_available,
SUM(IFNULL(icd.quantity_inbound, 0)) AS quantity_inbound,
SUM(IFNULL(icd.quantity_outbound, 0)) AS quantity_outbound,
SUM(IFNULL(imd.quantity_reserved, 0)) AS quantity_reserved,
SUM(IFNULL(imd.quantity_assigned, 0)) AS quantity_assigned,
SUM(IFNULL(sd.quantity_sold, 0)) AS quantity_sold,
SUM(IFNULL(sd.gross_sale, 0) - IFNULL(sd.credit, 0)) AS net_sales,
SUM(sd.quantity_sold_30d) AS quantity_sold_30d,

-- ✅ NEW METRICS (safe aggregation)
COALESCE(
    ROUND(SUM(ps.total_qty_sold) / NULLIF(SUM(ps.num_days), 0), 0)
) AS avg_daily_demand,

COALESCE(
    ROUND((SUM(ps.total_qty_sold) / NULLIF(SUM(ps.num_days), 0)) * 7, 0)
) AS weekly_demand

FROM inventory_current_data icd
FULL OUTER JOIN sales_data sd
ON icd.product_id = sd.product_id 
AND icd.product_code = sd.product_code 
AND icd.warehouse = sd.warehouse

FULL OUTER JOIN inventory_moves_data imd
ON COALESCE(icd.product_id, sd.product_id) = imd.product_id
AND COALESCE(icd.product_code, sd.product_code) = imd.product_code
AND COALESCE(icd.warehouse, sd.warehouse) = imd.warehouse

FULL OUTER JOIN inventory_by_location ibl
ON COALESCE(icd.product_id, sd.product_id, imd.product_id) = ibl.product_id
AND COALESCE(icd.product_code, sd.product_code, imd.product_code) = ibl.product_code
AND COALESCE(icd.warehouse, sd.warehouse, imd.warehouse) = ibl.warehouse

-- ✅ SAFE JOIN (product level only)
LEFT JOIN product_summary ps
ON COALESCE(icd.product_code, sd.product_code, imd.product_code, ibl.product_code) = ps.product_code

GROUP BY
COALESCE(icd.product_id, sd.product_id, imd.product_id, ibl.product_id),
COALESCE(icd.product_code, sd.product_code, imd.product_code, ibl.product_code),
COALESCE(icd.warehouse, sd.warehouse, imd.warehouse, ibl.warehouse),
COALESCE(icd.warehouse_id, sd.warehouse_id, imd.warehouse_id, ibl.warehouse_id)
  "
	,
	Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    )
in
    Source
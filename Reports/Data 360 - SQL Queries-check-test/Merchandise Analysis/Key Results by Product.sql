let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery = "
WITH
-- =========================
-- Products (DEDUP + ACTIVE LOGIC)
-- =========================
products_base AS (
  SELECT
    product.*,
    TRIM(product.code) AS product_code_trimmed,
    COUNT(DISTINCT product.id) OVER (PARTITION BY TRIM(product.code)) AS id_count
  FROM `" & BillingProject & "." & Dataset & ".products` product
),

products_final AS (
  SELECT *
  FROM products_base
  WHERE
    (id_count > 1 AND active = TRUE)
    OR id_count = 1
),

-- =========================
-- Sales Orders
-- =========================
sales_base AS (
  SELECT
    TRIM(lines.product_code) AS product_code,
    lines.product_id,
    so.order_date,
    lines.line_type,
    so.state,
    lines.quantity,
    (lines.quantity * lines.list_price) AS gross_sales
  FROM `" & BillingProject & "." & Dataset & ".sales_orders` so
  LEFT JOIN UNNEST(so.lines) AS lines
  WHERE so.order_date BETWEEN DATE_ADD(CURRENT_DATE(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
),

sales_final AS (
  SELECT
    product_code,
    COALESCE(SUM(CASE WHEN state = 'processing' THEN quantity ELSE 0 END), 0) AS open_so_qty,
    COALESCE(SUM(CASE WHEN state = 'processing' THEN gross_sales ELSE 0 END), 0) AS open_so_value,
    --COALESCE(SUM(CASE WHEN state IN ('done', 'processing') THEN gross_sales ELSE 0 END), 0) AS total_sales,
    COALESCE(
    SUM(
        CASE
           WHEN line_type = 'sale'
     AND state IN ('done', 'processing')
     AND STRPOS(product_code, 'SHIPPING') = 0
            THEN gross_sales
            ELSE 0
        END
    ),
0) AS total_sales,
    COALESCE(SUM(CASE
        WHEN EXTRACT(YEAR FROM order_date) = EXTRACT(YEAR FROM CURRENT_DATE())
        AND order_date <= CURRENT_DATE()
        THEN gross_sales ELSE 0 END), 0) AS ytd_sales,

    COALESCE(SUM(CASE
        WHEN EXTRACT(YEAR FROM order_date) = EXTRACT(YEAR FROM DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR))
        AND EXTRACT(DAYOFYEAR FROM order_date) <= EXTRACT(DAYOFYEAR FROM CURRENT_DATE())
        THEN gross_sales ELSE 0 END), 0) AS pytd_sales,

    COALESCE(SUM(CASE
        WHEN EXTRACT(YEAR FROM order_date) = EXTRACT(YEAR FROM CURRENT_DATE())
        AND EXTRACT(MONTH FROM order_date) = EXTRACT(MONTH FROM CURRENT_DATE())
        THEN gross_sales ELSE 0 END), 0) AS mtd_sales,

    COALESCE(SUM(CASE
        WHEN EXTRACT(YEAR FROM order_date) = EXTRACT(YEAR FROM DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR))
        AND EXTRACT(MONTH FROM order_date) = EXTRACT(MONTH FROM CURRENT_DATE())
        AND EXTRACT(DAY FROM order_date) <= EXTRACT(DAY FROM CURRENT_DATE())
        THEN gross_sales ELSE 0 END), 0) AS pymtd_sales

  FROM sales_base
  GROUP BY product_code
),

-- =========================
-- Inventory
-- =========================
inventory_final AS (
  SELECT
    product_id,
    TRIM(product_code) AS product_code,
    COALESCE(SUM(quantity_on_hand), 0) AS quantity_on_hand,
    COALESCE(SUM(quantity_available), 0) AS quantity_available
  FROM `" & BillingProject & "." & Dataset & ".inventory_current`
  GROUP BY product_id, product_code
),

-- =========================
-- Open POs
-- =========================
open_pos_final AS (
  SELECT
    TRIM(line.product_code) AS product_code,
    COALESCE(SUM(quantity), 0) AS open_po_qty,
    COALESCE(SUM(amount), 0) AS open_po_value
  FROM `" & BillingProject & "." & Dataset & ".purchase_orders` po
  LEFT JOIN UNNEST(lines) AS line
  WHERE po.state IN ('confirmed', 'processing')
    AND po.purchase_date BETWEEN DATE_ADD(CURRENT_DATE(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  GROUP BY product_code
),

-- =========================
-- Attribute Ranking (NEW)
-- =========================
attribute_ranked AS (
  SELECT
    product.id,
    attr.attribute_name,
    attr.value,
    DENSE_RANK() OVER (
      PARTITION BY product.id
      ORDER BY attr.attribute_name
    ) - 1 AS attribute_index
  FROM products_final product
  LEFT JOIN UNNEST(product.attributes) AS attr
)

-- =========================
-- Final Select
-- =========================
SELECT
  product.id AS product_id,
  product.product_code_trimmed AS product_code,
  product.variant_name,
  product.template_name,
  product.category_name,
  product.brand_name,
  product.product_type,
  product.active,

MAX(IF(ar.attribute_index = 0, ar.value, NULL)) AS Attribute_0,
MAX(IF(ar.attribute_index = 1, ar.value, NULL)) AS Attribute_1,
MAX(IF(ar.attribute_index = 2, ar.value, NULL)) AS Attribute_2,
MAX(IF(ar.attribute_index = 3, ar.value, NULL)) AS Attribute_3,
MAX(IF(ar.attribute_index = 4, ar.value, NULL)) AS Attribute_4,
MAX(IF(ar.attribute_index = 5, ar.value, NULL)) AS Attribute_5,
MAX(IF(ar.attribute_index = 6, ar.value, NULL)) AS Attribute_6,
MAX(IF(ar.attribute_index = 7, ar.value, NULL)) AS Attribute_7,
MAX(IF(ar.attribute_index = 8, ar.value, NULL)) AS Attribute_8,
MAX(IF(ar.attribute_index = 9, ar.value, NULL)) AS Attribute_9,
MAX(IF(ar.attribute_index = 10, ar.value, NULL)) AS Attribute_10,
MAX(IF(ar.attribute_index = 11, ar.value, NULL)) AS Attribute_11,
MAX(IF(ar.attribute_index = 12, ar.value, NULL)) AS Attribute_12,
MAX(IF(ar.attribute_index = 13, ar.value, NULL)) AS Attribute_13,
MAX(IF(ar.attribute_index = 14, ar.value, NULL)) AS Attribute_14,
MAX(IF(ar.attribute_index = 15, ar.value, NULL)) AS Attribute_15,
MAX(IF(ar.attribute_index = 16, ar.value, NULL)) AS Attribute_16,
MAX(IF(ar.attribute_index = 17, ar.value, NULL)) AS Attribute_17,
MAX(IF(ar.attribute_index = 18, ar.value, NULL)) AS Attribute_18,
MAX(IF(ar.attribute_index = 19, ar.value, NULL)) AS Attribute_19,
MAX(IF(ar.attribute_index = 20, ar.value, NULL)) AS Attribute_20, 

  COALESCE(inv.quantity_on_hand, 0) AS quantity_on_hand,
  COALESCE(inv.quantity_available, 0) AS quantity_available,
  COALESCE(inv.quantity_on_hand, 0) * COALESCE(co.cost, 0) AS qty_on_hand_value,
  COALESCE(inv.quantity_available, 0) * COALESCE(co.cost, 0) AS qty_available_value,
  COALESCE(po.open_po_qty, 0) AS open_po_qty,
  COALESCE(po.open_po_value, 0) AS open_po_value,
  COALESCE(so.open_so_qty, 0) AS open_so_qty,
  COALESCE(so.open_so_value, 0) AS open_so_value,
  COALESCE(so.total_sales, 0) AS total_sales,
  COALESCE(so.ytd_sales, 0) AS ytd_sales,
  COALESCE(so.pytd_sales, 0) AS pytd_sales,
  COALESCE(so.mtd_sales, 0) AS mtd_sales,
  COALESCE(so.pymtd_sales, 0) AS pymtd_sales

FROM products_final product
LEFT JOIN UNNEST(product.costs) AS co

LEFT JOIN attribute_ranked ar
  ON ar.id = product.id

LEFT JOIN inventory_final inv
  ON inv.product_id = product.id
 AND inv.product_code = product.product_code_trimmed

LEFT JOIN open_pos_final po
  ON po.product_code = product.product_code_trimmed

LEFT JOIN sales_final so
  ON so.product_code = product.product_code_trimmed

GROUP BY
  product.id,
  product.product_code_trimmed,
  product.variant_name,
  product.template_name,
  product.category_name,
  product.brand_name,
  product.product_type,
  product.active,
  co.cost,
  inv.quantity_on_hand,
  inv.quantity_available,
  po.open_po_qty,
  po.open_po_value,
  so.open_so_qty,
  so.open_so_value,
  so.total_sales,
  so.ytd_sales,
  so.pytd_sales,
  so.mtd_sales,
  so.pymtd_sales
",

    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProject, UseStorageApi = false]
            ){[Name = BillingProject]}[Data],
            SQLQuery,
            null,
            [EnableFolding = true]
        )
in
    Source
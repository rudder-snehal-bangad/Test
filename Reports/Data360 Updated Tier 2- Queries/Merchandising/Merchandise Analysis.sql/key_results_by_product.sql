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
    so.state,
    lines.quantity,
    (lines.quantity * lines.list_price) AS gross_sales
  FROM `" & BillingProject & "." & Dataset & ".sales_orders` so
  LEFT JOIN UNNEST(so.lines) AS lines
  WHERE so.order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
),

sales_final AS (
  SELECT
    product_code,
    COALESCE(SUM(CASE WHEN state = 'processing' THEN quantity ELSE 0 END), 0) AS open_so_qty,
    COALESCE(SUM(CASE WHEN state = 'processing' THEN gross_sales ELSE 0 END), 0) AS open_so_value,
    COALESCE(SUM(CASE WHEN state IN ('done', 'processing') THEN gross_sales ELSE 0 END), 0) AS total_sales,
    COALESCE(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = EXTRACT(YEAR FROM CURRENT_DATE()) AND order_date <= CURRENT_DATE() THEN gross_sales ELSE 0 END), 0) AS ytd_sales,
    COALESCE(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = EXTRACT(YEAR FROM DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR))
        AND EXTRACT(DAYOFYEAR FROM order_date) <= EXTRACT(DAYOFYEAR FROM CURRENT_DATE()) THEN gross_sales ELSE 0 END), 0) AS pytd_sales,
    COALESCE(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = EXTRACT(YEAR FROM CURRENT_DATE())
        AND EXTRACT(MONTH FROM order_date) = EXTRACT(MONTH FROM CURRENT_DATE()) THEN gross_sales ELSE 0 END), 0) AS mtd_sales,
    COALESCE(SUM(CASE WHEN EXTRACT(YEAR FROM order_date) = EXTRACT(YEAR FROM DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR))
        AND EXTRACT(MONTH FROM order_date) = EXTRACT(MONTH FROM CURRENT_DATE())
        AND EXTRACT(DAY FROM order_date) <= EXTRACT(DAY FROM CURRENT_DATE()) THEN gross_sales ELSE 0 END), 0) AS pymtd_sales
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
    AND po.purchase_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  GROUP BY product_code
)

-- =========================
-- Final Select (UNCHANGED LOGIC)
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

  MAX(IF(attr.attribute_name = 'color', attr.value, NULL)) AS color,
  MAX(IF(attr.attribute_name = 'brand', attr.value, NULL)) AS brand,
  MAX(IF(attr.attribute_name = 'material', attr.value, NULL)) AS material,
  MAX(IF(attr.attribute_name = 'Hoodie Size', attr.value, NULL)) AS hoodie_size,
  MAX(IF(attr.attribute_name = 'title', attr.value, NULL)) AS title,
  MAX(IF(attr.attribute_name = 'subscription-type', attr.value, NULL)) AS subscription_type,
  MAX(IF(attr.attribute_name = 'Class', attr.value, NULL)) AS class,
  MAX(IF(attr.attribute_name = 'denominations', attr.value, NULL)) AS denominations,
  MAX(IF(attr.attribute_name = 'merchandising classification', attr.value, NULL)) AS merch_classification,
  MAX(IF(attr.attribute_name = 'size', attr.value, NULL)) AS size,
  MAX(IF(attr.attribute_name = 'gender', attr.value, NULL)) AS gender,
  MAX(IF(attr.attribute_name = 'style', attr.value, NULL)) AS style,
  MAX(IF(attr.attribute_name = 'Product Phase', attr.value, NULL)) AS product_phase,
  MAX(IF(attr.attribute_name = 'section', attr.value, NULL)) AS section,
  MAX(IF(attr.attribute_name = 'Sleeve Print', attr.value, NULL)) AS sleeve_print,
  MAX(IF(attr.attribute_name = 'Department', attr.value, NULL)) AS department,
  MAX(IF(attr.attribute_name = 'Classification', attr.value, NULL)) AS classification,
  MAX(IF(attr.attribute_name = 'Theme', attr.value, NULL)) AS theme,
  MAX(IF(attr.attribute_name = 'Subtheme', attr.value, NULL)) AS subtheme,
  MAX(IF(attr.attribute_name = 'Franchise', attr.value, NULL)) AS franchise,

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
LEFT JOIN UNNEST(product.attributes) AS attr
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
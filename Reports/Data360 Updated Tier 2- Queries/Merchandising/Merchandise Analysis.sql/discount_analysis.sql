let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery = "
WITH base_data AS (
  SELECT
    so.order_id,
    DATE(so.order_date) AS order_date,
    line.line_type,
    so.state,
    LOWER(line.product_code) AS product_code,
    line.quantity,
    line.list_price,
    line.unit_price,
    --line.gross_profit_cpny_ccy_cache as gross_profit,    
    CASE
     -- WHEN lines.line_type = 'sale'
        WHEN so.state IN ('done', 'processing')
        -- AND (
        --   STRPOS(lines.product_code, 'SHIPPING') = 0
        --   OR lines.product_code IS NULL
        -- )
      THEN  line.gross_profit_cpny_ccy_cache 
      ELSE 0
    END AS gross_profit,
    --line.untaxed_amount_cpny_ccy_cache AS gross_sales,
    (line.quantity * line.list_price) AS gross_sales,
    line.cost_price_cpny_ccy_cache AS cost_price,
    so.shipment_country_name,
    so.channel_name,
    so.warehouse_name,
    so.customer_name,
    so.sales_person_name,
    LOWER(line.product_code) LIKE '%ship%' AS is_shipping
  FROM `" & BillingProject & "." & Dataset & ".sales_orders` AS so,
    UNNEST(so.lines) AS line
  WHERE so.order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()

),


final_cte AS (
  SELECT
    product_code,
    order_date,
    shipment_country_name,
    channel_name,
    warehouse_name,
    customer_name,
    sales_person_name,
    COUNT(DISTINCT CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND NOT is_shipping THEN product_code END) AS products,
    COUNT(DISTINCT CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND NOT is_shipping THEN order_id END) AS orders,
    SUM(CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND NOT is_shipping THEN quantity ELSE 0 END) AS quantity,
    --SUM(CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND NOT is_shipping THEN (list_price - unit_price) * quantity ELSE 0 END) AS discount,
    COALESCE(SUM(CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND NOT is_shipping THEN (list_price - unit_price) *quantity ELSE 0 END), 0) AS discount,
   -- AVG(CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND NOT is_shipping AND list_price > 0 THEN (list_price - unit_price) / list_price ELSE NULL END) AS discount_percent,
   COALESCE(AVG(CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND NOT is_shipping AND list_price > 0 THEN (list_price - unit_price) / list_price ELSE 0 END), 0) AS discount_percent,
    SUM(CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND NOT is_shipping THEN gross_sales ELSE 0 END) AS product_sales,
    SUM(gross_profit) AS gross_profit
  FROM base_data
  GROUP BY
    product_code,
    order_date,
    shipment_country_name,
    channel_name,
    warehouse_name,
    customer_name,
    sales_person_name
)


SELECT
  product_code AS prod_code,
  order_date,
  shipment_country_name,
  channel_name,
  warehouse_name,
  customer_name,
  sales_person_name,
  products,
  orders,
  quantity,
  discount,
  discount_percent,
  CASE
    WHEN discount_percent BETWEEN 0 AND 1 THEN
      CASE
        WHEN discount_percent * 100 < 90 THEN
          CONCAT(CAST(FLOOR(discount_percent * 100 / 10) * 10 AS STRING), '% - ',
                 CAST(FLOOR(discount_percent * 100 / 10) * 10 + 10 AS STRING), '%')
        ELSE '90% - 100%'
      END
    ELSE NULL
  END AS discount_bucket,
  product_sales,
  gross_profit,
  CASE WHEN product_sales > 0 THEN gross_profit / product_sales ELSE 0 END AS gross_profit_margin
FROM final_cte
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
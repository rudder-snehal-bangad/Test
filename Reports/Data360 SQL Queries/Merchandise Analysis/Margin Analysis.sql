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
   -- line.line_type,

    CASE
      WHEN so.state IN ('done', 'processing')
      THEN line.gross_profit_cpny_ccy_cache
      ELSE 0
    END AS gross_profit,

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

    COUNT(DISTINCT CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND LOWER(product_code) NOT LIKE '%ship%'  THEN product_code END) AS products,

    COUNT(DISTINCT CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND LOWER(product_code) NOT LIKE '%ship%'  THEN order_id END) AS orders,

    SUM(CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND LOWER(product_code) NOT LIKE '%ship%'  THEN quantity ELSE 0 END) AS quantity,

    SUM(CASE WHEN line_type = 'sale' AND state IN ('done', 'processing') AND LOWER(product_code) NOT LIKE '%ship%'  THEN gross_sales ELSE 0 END) AS product_sales,

    SUM(gross_profit) AS gross_profit,

    -- ✅ COGS
    SUM(CASE
        WHEN line_type = 'sale'
        AND state IN ('done','processing')
        AND product_code NOT LIKE '%ship%'
        THEN cost_price ELSE 0 END
    ) AS cogs,

    -- ✅ Shipping
    SUM(CASE
        WHEN line_type = 'sale'
        AND state IN ('done','processing')
        AND product_code LIKE '%ship%'
        THEN gross_sales ELSE 0 END
    ) AS shipping,

    -- ✅ Returns
    SUM(CASE
        WHEN line_type = 'return'
        AND state IN ('done','processing')
        THEN ABS(gross_sales) ELSE 0 END
    ) AS returned,

      SUM(
  CASE 
    WHEN list_price > unit_price 
      AND list_price IS NOT NULL 
      AND LOWER(product_code) NOT LIKE '%ship%' 
    THEN (list_price - unit_price) * quantity
    ELSE 0 
  END
) AS discount,

  FROM base_data
  GROUP BY
    product_code,
    order_date,
    shipment_country_name,
    channel_name,
    warehouse_name,
    customer_name,
    sales_person_name
),

final_output AS (
  SELECT *,
    SAFE_DIVIDE(gross_profit, product_sales) AS gross_profit_margin
  FROM final_cte
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

  CASE
    WHEN gross_profit_margin IS NULL THEN 'No Sales'
    WHEN gross_profit_margin < 0 THEN 'Negative Margin'
    WHEN gross_profit_margin >= 1 THEN 'Above 100%'
    ELSE CONCAT(
      CAST(FLOOR(gross_profit_margin * 100 / 10) * 10 AS STRING), '% - ',
      CAST(FLOOR(gross_profit_margin * 100 / 10) * 10 + 10 AS STRING), '%'
    )
  END AS margin_bucket,


ROUND(product_sales - discount - returned, 2) AS net_sales,

  ROUND(product_sales,2) as product_sales,
  ROUND(gross_profit,2) as gross_profit,
  ROUND(gross_profit_margin,2) as gross_profit_margin,

  -- ✅ Added to final output
  ROUND(cogs,2) as cogs,
  ROUND(shipping,2) as shipping,
  ROUND(returned,2) as returned,
  ROUND(discount,2) AS discount

FROM final_output
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
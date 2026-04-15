let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery = "
WITH base AS (
  SELECT
    so.order_date,
    so.order_id,
    so.order_number,
    so.channel_name,
    so.warehouse,
    so.state,
    lines.line_type AS sale_type,
    lines.quantity,
    (lines.quantity * lines.list_price) AS gross_sales,
    lines.product_code,
    lines.product_id,
    so.customer_id,
    so.customer_name,
    so.shipment_region_name,
    so.shipment_country_name,
    so.shipment_address_city,
    so.sales_person_name,
    lines.list_price AS list_price,
    lines.unit_price AS unit_price,
    lines.cost_price_cpny_ccy_cache AS cost_price,
 
    CASE
      WHEN lines.line_type = 'sale'
        AND so.state IN ('done', 'processing')
      THEN (lines.quantity * lines.list_price)
      ELSE 0
    END AS gross_sales_calc,
 
    CASE
      WHEN lines.line_type = 'sale'
        AND so.state IN ('done', 'processing')
        AND (
          STRPOS(lines.product_code, 'SHIPPING') = 0
          OR lines.product_code IS NULL
        )
      THEN lines.cost_price_cpny_ccy_cache
      ELSE 0
    END AS cost_of_goods_sold,
 
    CASE
      WHEN lines.line_type = 'sale'
        AND so.state IN ('done', 'processing')
        AND (
          STRPOS(lines.product_code, 'SHIPPING') = 0
          OR lines.product_code IS NULL
        )
      THEN (lines.list_price - lines.unit_price) * lines.quantity
      ELSE 0
    END AS discount_query,
 
    ROUND(
      CASE
        WHEN lines.line_type = 'sale'
          AND so.state IN ('done', 'processing')
          AND (
            STRPOS(lines.product_code, 'SHIPPING') = 0
            OR lines.product_code IS NULL
          )
        THEN SAFE_DIVIDE(
               lines.list_price - lines.unit_price,
               lines.list_price
             )
        ELSE 0
      END,
      4
    ) AS discount_pct,
 
    CASE
     -- WHEN lines.line_type = 'sale'
        WHEN so.state IN ('done', 'processing')
        -- AND (
        --   STRPOS(lines.product_code, 'SHIPPING') = 0
        --   OR lines.product_code IS NULL
        -- )
      THEN  lines.gross_profit_cpny_ccy_cache 
      ELSE 0
    END AS gross_profit,
 
    CASE
      WHEN lines.cost_price_cpny_ccy_cache IS NULL
        OR lines.cost_price_cpny_ccy_cache = 0
      THEN 'Zero'
      ELSE 'Non-Zero'
    END AS is_cost_zero,
 
    CASE
      WHEN lines.line_type = 'sale'
        AND so.state IN ('done', 'processing')
        AND (
          STRPOS(lines.product_code, 'SHIPPING') = 0
          OR lines.product_code IS NULL
        )
      THEN (lines.quantity * lines.list_price)
      ELSE 0
    END AS product_sales,
 
    CASE
      WHEN lines.line_type = 'sale'
        AND so.state IN ('done', 'processing')
        AND (
          STRPOS(lines.product_code, 'SHIPPING') = 0
          OR lines.product_code IS NULL
        )
      THEN lines.quantity
      ELSE 0
    END AS units_query
 
  FROM " & BillingProject & "." & Dataset & ".sales_orders so
  LEFT JOIN UNNEST(so.lines) AS lines
  WHERE so.order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
)
 
SELECT
  *,
  CASE
    WHEN discount_pct = 1 THEN '90% - 100%'
    WHEN discount_pct >= 0
      AND discount_pct < 1
      AND discount_pct IS NOT NULL
    THEN CONCAT(
           CAST(DIV(CAST(discount_pct * 100 AS INT64), 10) * 10 AS STRING),
           '% - ',
           CAST(DIV(CAST(discount_pct * 100 AS INT64), 10) * 10 + 10 AS STRING),
           '%'
         )
    ELSE NULL
  END AS discount_pct_bucket
FROM base
",

    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProject, UseStorageApi = false]
            ){[Name = BillingProject]}[Data],
            SQLQuery,
            null,
            [EnableFolding = true]
        ),

    #"Renamed Columns" =
        Table.RenameColumns(
            Source,
            {
                {"cost_of_goods_sold", "Cost of Goods Sold"},
                {"discount_query", "Discount"},
                {"discount_pct", "Discount %"},
                {"discount_pct_bucket", "Discount% Bucket"},
                {"gross_profit", "Gross Profit"},
                {"gross_sales", "gross_sales"},
                {"gross_sales_calc", "Gross Sales"},
                {"is_cost_zero", "Is Cost Zero?"},
                {"product_sales", "Product Sales"},
                {"units_query", "Units"}
            }
        )
in
    #"Renamed Columns"
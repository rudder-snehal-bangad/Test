let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery ="WITH products_data AS (
  SELECT
    prod.active,
    prod.id AS product_id,
    prod.code AS product_code,
    prod.variant_name AS variant_name, 
    Date(create_date) as launch_date, 
    lp.list_price,
    cp.cost as cost_price,
  FROM " & BasePath & ".products prod
      LEFT JOIN UNNEST(prod.list_prices) as lp
      LEFT JOIN UNNEST(prod.costs) as cp
),

sales_base AS (
  SELECT
    order_date, so.id,
    l.product_id,
    l.product_code,
    SUM(CASE WHEN line_type = 'sale' AND quantity >= 0 THEN quantity ELSE 0 END) AS gross_sales_u,
    SUM(CASE WHEN line_type = 'sale' and list_price <> 0.0 AND quantity >= 0 THEN (list_price * quantity) ELSE 0 END) AS gross_sales_dol,
    SUM(CASE WHEN line_type = 'sale' and list_price <> 0.0 AND quantity >= 0 THEN ((list_price - unit_price)*quantity) ELSE 0 END) AS discount_dol,
    ABS(SUM(CASE WHEN line_type = 'return' AND quantity < 0 THEN quantity ELSE 0 END)) AS return_u,
    ABS(SUM(CASE WHEN line_type = 'return' AND state IN ('done', 'processing') AND quantity < 0 THEN untaxed_amount_cpny_ccy_cache ELSE 0 END)) AS return_dol,
    SUM(CASE WHEN line_type = 'sale' THEN cost_price_cpny_ccy_cache ELSE 0 END) AS cost_dol
  FROM " & BasePath & ".sales_orders so
    LEFT JOIN UNNEST(lines) l
  WHERE state in ('done', 'processing') 
    AND NOT (LOWER(l.product_code) LIKE '%ship%' OR LOWER(l.product_code) LIKE '%service%') 
    AND order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  GROUP BY 1,2,3,4
)

  SELECT
    pd.product_id as id,
    pd.product_code, 
    order_date,
    pd.launch_date, 
    gross_sales_u, gross_sales_dol,
    discount_dol,
    return_u, return_dol,
    gross_sales_u - return_u as net_u,
    gross_sales_dol - return_dol - discount_dol as net_dol,
    cost_dol,
    (gross_sales_dol - cost_dol) AS gross_margin_dol,
    (gross_sales_dol - discount_dol - return_dol - cost_dol) AS net_margin_dol,
    DENSE_RANK() OVER (ORDER BY pd.launch_date DESC) AS launch_sort_order,
  FROM products_data pd
    LEFT JOIN sales_base sb on pd.product_code = sb.product_code
  WHERE pd.launch_date <= CURRENT_DATE() AND order_date BETWEEN launch_date AND launch_date + 90
AND launch_date >='2023-10-03'",
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
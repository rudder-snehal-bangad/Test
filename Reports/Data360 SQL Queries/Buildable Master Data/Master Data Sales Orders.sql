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
    l.product_code,so.channel_name as sales_channel,so.channel_segment,
    SUM(CASE WHEN line_type = 'sale' AND state IN ('done','processing') AND lower(product_code) NOT LIKE'%ship%' THEN quantity ELSE 0 END) AS gross_sales_u,
    SUM(CASE
        WHEN line_type='sale' AND state IN ('done','processing') AND lower(product_code) NOT LIKE'%ship%'
        THEN (l.list_price * l.quantity) ELSE 0 END
    ) AS gross_sales_dol,
    SUM(CASE when list_price > unit_price and list_price is not null and lower(product_code) NOT LIKE'%ship%' then (list_price - unit_price)*quantity
    ELSE 0 END) as discount_dol,
    SUM(CASE
        WHEN line_type='return'
        AND state IN ('done','processing')
        THEN ABS(quantity) ELSE 0 END
    ) AS return_u,
    SUM(CASE
        WHEN line_type='return'
        AND state IN ('done','processing')
        THEN ABS((l.list_price * l.quantity)) ELSE 0 END
    ) AS return_dol,
    SUM(CASE
        WHEN lower(product_code) NOT LIKE'%ship%'
        AND line_type='sale'
        AND state IN ('done','processing')
        THEN cost_price_cpny_ccy_cache ELSE 0 END
    ) AS cost_dol
  FROM " & BasePath & ".sales_orders so
    LEFT JOIN UNNEST(lines) l
    where order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  GROUP BY 1,2,3,4,5,6
)

  SELECT
    pd.product_id as id,
    sb.id as so_id,
    pd.product_code, 
    order_date,sales_channel,channel_segment,
    pd.launch_date, 
    gross_sales_u, gross_sales_dol,
    discount_dol,
    return_u, return_dol,
    gross_sales_u - return_u as net_u,
    gross_sales_dol - return_dol - discount_dol as net_dol,
    cost_dol,
    (gross_sales_dol - cost_dol) AS gross_margin_dol,
    (gross_sales_dol - discount_dol - return_dol - cost_dol) AS net_margin_dol
  FROM products_data pd
    LEFT JOIN sales_base sb on pd.product_code = sb.product_code
  WHERE pd.launch_date <= CURRENT_DATE()+7"
	,
	Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
    #"Removed Columns" = Table.RemoveColumns(Source,{"product_code"})
in
    #"Removed Columns"
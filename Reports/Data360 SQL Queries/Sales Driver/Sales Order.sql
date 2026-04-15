let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),

    // Dynamic table paths
    SalesOrdersTable = "`" & BillingProject & "." & Dataset & ".sales_orders`",
    ShipmentsTable = "`" & BillingProject & "." & Dataset & ".shipments`",

    SQLQuery = "
WITH base_sales AS (
    SELECT
        so.order_date,
        so.order_id,
        so.order_number,
        so.channel_name,
        lines.product_code,
        so.state,
        so.shipping_start_date,
        so.shipping_end_date,
        lines.line_type AS sale_type,
        lines.quantity,
        (lines.list_price * lines.quantity) AS gross_sales,
        lines.gross_profit_cpny_ccy_cache AS gross_profit,
        lines.cost_price_cpny_ccy_cache,
        lines.product_id,
        lines.id AS sale_line_id,
        so.customer_id,
        so.customer_name,
        so.shipment_address_city,
        so.shipment_region_name,
        so.shipment_country_name,
        so.sales_person_name,
        lines.list_price,
        lines.unit_price
    FROM " & SalesOrdersTable & " so
    LEFT JOIN UNNEST(lines) AS lines
    WHERE so.order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
),
min_customer_order AS (
    SELECT
        so.customer_id,
        MIN(so.order_date) AS first_order_date
    FROM " & SalesOrdersTable & " so
    LEFT JOIN UNNEST(so.lines) l
    WHERE l.line_type = 'sale'
        AND so.state IN ('done', 'processing')
        AND lower(product_code) NOT LIKE'%ship%'
    GROUP BY so.customer_id
),
metrics AS (
SELECT
    sale_line_id,
    SUM(CASE
        WHEN sale_type='sale' AND state IN ('done','processing') AND lower(product_code) NOT LIKE'%ship%'
        THEN gross_sales ELSE 0 END
    ) AS gross_sales,

    SUM(CASE when list_price > unit_price and list_price is not null and lower(product_code) NOT LIKE'%ship%' then (list_price - unit_price)*quantity
    ELSE 0 END) as discounts,

    SUM(CASE
        WHEN sale_type='sale' AND state IN ('done','processing') AND lower(product_code) NOT LIKE'%ship%'
        THEN gross_profit ELSE 0 END
    ) AS gross_profit,

    SUM(CASE
        WHEN lower(product_code) NOT LIKE'%ship%'
        AND sale_type='sale'
        AND state IN ('done','processing')
        THEN cost_price_cpny_ccy_cache ELSE 0 END
    ) AS cogs,

    SUM(CASE
        WHEN sale_type='sale'
        AND state IN ('done','processing')
        AND lower(product_code) LIKE '%ship%'
        THEN gross_sales ELSE 0 END
    ) AS shipping,

    SUM(CASE
        WHEN sale_type='return'
        AND state IN ('done','processing')
        THEN ABS(gross_sales) ELSE 0 END
    ) AS returned,

    SUM(CASE
        WHEN sale_type='sale'
        AND state IN ('done','processing')
        AND lower(product_code) NOT LIKE'%ship%'
        THEN quantity ELSE 0 END
    ) AS quantity_units,

    SUM(CASE
        WHEN sale_type='return'
        AND state IN ('done','processing')
        THEN ABS(quantity) ELSE 0 END
    ) AS returned_units,

    SUM(CASE
        WHEN sale_type='sale'
        AND state='done'
        THEN gross_sales ELSE 0 END
    ) AS value_shipped,

    SUM(CASE
        WHEN sale_type='sale'
        AND state='processing'
        AND lower(product_code) NOT LIKE'%ship%'
        THEN quantity ELSE 0 END
    ) AS quantity_open_orders,

    SUM(CASE
        WHEN sale_type='sale'
        AND state='cancel'
        AND lower(product_code) NOT LIKE'%ship%'
        THEN quantity ELSE 0 END
    ) AS quantity_cancel_orders,

    SUM(CASE
        WHEN sale_type='sale'
        AND state='cancel'
        THEN gross_sales ELSE 0 END
    ) AS gross_cancel_orders

FROM base_sales
GROUP BY sale_line_id
),
customer_shipments AS (
SELECT
    m.order_line_id,
    MIN(s.shipped_at) AS shipped_at
FROM " & ShipmentsTable & " s
LEFT JOIN UNNEST(moves) AS m
WHERE s.state NOT LIKE 'cancel'
GROUP BY m.order_line_id
),
final AS (
SELECT
   bs.* EXCEPT(quantity, gross_sales, gross_profit, cost_price_cpny_ccy_cache),
    m.gross_sales,
    m.discounts,
    m.gross_profit,
    m.quantity_units as quantity,
    m.cogs,
    m.shipping,
    m.returned,
    SAFE_DIVIDE((m.gross_profit), m.gross_sales) AS profit_margin,
    m.quantity_units,
    m.returned_units,
    m.value_shipped,
    m.quantity_open_orders,
    m.gross_cancel_orders,
    m.quantity_cancel_orders,
    CASE WHEN cs.shipped_at IS NULL then 'Sales (Open Orders)'
    ELSE 'Sales (Shipped)' END AS legend,
    CASE WHEN bs.order_date = mco.first_order_date THEN 0 ELSE 1 END AS new_vs_returning
FROM base_sales bs
LEFT JOIN metrics m
ON m.sale_line_id = bs.sale_line_id
LEFT JOIN customer_shipments cs
ON cs.order_line_id = bs.sale_line_id
LEFT JOIN min_customer_order mco
ON mco.customer_id = bs.customer_id
)
SELECT
*
FROM final
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
let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    // Dynamic table path
    SalesOrdersTable = "`" & BillingProject & "." & Dataset & ".sales_orders`",
    ShipmentsTable = "`" & BillingProject & "." & Dataset & ".shipments`",

    SQLQuery = "WITH base_sales AS (
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
   --FROM fulfil-data-warehouse-227710.gruntstyle.sales_orders so
    LEFT JOIN UNNEST(lines) AS lines
    -- WHERE so.order_date BETWEEN '2025-12-10' AND '2026-01-08'
    WHERE so.order_date BETWEEN DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
),

metrics AS (
SELECT
    sale_line_id,

    SUM(CASE
        WHEN sale_type='sale' AND state IN ('done','processing') AND lower(product_code) NOT LIKE'%ship%'
        THEN gross_sales ELSE 0 END
    ) AS gross_sales,

    SUM(CASE 
        WHEN list_price > unit_price AND list_price IS NOT NULL AND lower(product_code) NOT LIKE'%ship%' 
        THEN (list_price - unit_price)*quantity
        ELSE 0 
    END) AS discounts,
 
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
    --FROM fulfil-data-warehouse-227710.gruntstyle.shipments s
FROM " & ShipmentsTable & " s
LEFT JOIN UNNEST(s.moves) AS m
WHERE s.state != 'cancel'
GROUP BY m.order_line_id
),

final AS (
SELECT
   bs.* EXCEPT(quantity, gross_sales, gross_profit, cost_price_cpny_ccy_cache),
    m.gross_sales,
    m.discounts,
    m.gross_profit,
    m.quantity_units AS quantity,
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

    -- Order Aging
    CASE 
        WHEN bs.state = 'processing' 
        THEN DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY)
        ELSE NULL
    END AS order_age_days,

    -- ================= BUCKETS =================

    -- 15 Days
    CASE 
        WHEN bs.state != 'processing' THEN NULL
        WHEN DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY) >= 120 THEN '120+'
        ELSE FORMAT('%d-%d',
            (SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/15) AS INT64)*15)+1,
            (SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/15) AS INT64)+1)*15
        )
    END AS days_15,

    -- 30 Days
    CASE 
        WHEN bs.state != 'processing' THEN NULL
        WHEN DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY) >= 180 THEN '180+'
        ELSE FORMAT('%d-%d',
            (SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/30) AS INT64)*30)+1,
            (SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/30) AS INT64)+1)*30
        )
    END AS days_30,

    -- 60 Days
    CASE 
        WHEN bs.state != 'processing' THEN NULL
        WHEN DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY) >= 240 THEN '240+'
        ELSE FORMAT('%d-%d',
            (SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/60) AS INT64)*60)+1,
            (SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/60) AS INT64)+1)*60
        )
    END AS days_60,

    -- 90 Days
    CASE 
        WHEN bs.state != 'processing' THEN NULL
        WHEN DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY) >= 360 THEN '360+'
        ELSE FORMAT('%d-%d',
            (SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/90) AS INT64)*90)+1,
            (SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/90) AS INT64)+1)*90
        )
    END AS days_90,

    -- ================= SORT =================

    CASE 
        WHEN DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY) >= 120 THEN 8
        ELSE SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/15) AS INT64)
    END AS days_15_sort,

    CASE 
        WHEN DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY) >= 180 THEN 6
        ELSE SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/30) AS INT64)
    END AS days_30_sort,

    CASE 
        WHEN DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY) >= 240 THEN 4
        ELSE SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/60) AS INT64)
    END AS days_60_sort,

    CASE 
        WHEN DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY) >= 360 THEN 4
        ELSE SAFE_CAST(FLOOR((GREATEST(DATE_DIFF(CURRENT_DATE(), bs.order_date, DAY),1)-1)/90) AS INT64)
    END AS days_90_sort,

    CASE 
        WHEN cs.shipped_at IS NULL THEN 'Sales (Open Orders)'
        ELSE 'Sales (Shipped)' 
    END AS legend

FROM base_sales bs
LEFT JOIN metrics m
ON m.sale_line_id = bs.sale_line_id
LEFT JOIN customer_shipments cs
ON cs.order_line_id = bs.sale_line_id
)

SELECT * FROM final
",

    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProject, UseStorageApi = false]
            ){[Name = BillingProject]}[Data],
            SQLQuery,
            null,
            [EnableFolding = true]
        ), #"Renamed Columns" = Table.RenameColumns(Source,{{"legend", "legends"}})
in
    #"Renamed Columns"
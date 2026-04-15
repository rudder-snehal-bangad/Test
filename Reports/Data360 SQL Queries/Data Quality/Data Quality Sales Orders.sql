let
    // Build full table reference dynamically
    FullTableName_shipments = 
        "`" & BillingProjectID & "." & DatasetName & ".shipments`",
    FullTableName_sales_orders = 
        "`" & BillingProjectID & "." & DatasetName & ".sales_orders`",
	Period = Number.ToText(#"Analysis Period (Years)"),
    // Build dynamic SQL
    SQLStatement = 
		" WITH shipments AS (
			  SELECT
				cs.id AS shipment_id,
				cs.number AS shipment_number,
				shipped_at,
				cs_mo.order_id
			  FROM " & FullTableName_shipments &"  cs
			  LEFT JOIN UNNEST(moves) cs_mo
			),
			sales_orders_with_index AS (
			  SELECT
				so.id,
				so.order_number,
				so.state,
				so.create_date,
				so.order_date,
				so.channel_name,
				so.customer_name,
				shipments.shipment_number,
				shipments.shipment_id,
				shipments.shipped_at,
				lines.id AS sale_line_id,
				lines.product_id,
				lines.product_code,
				SUM(lines.quantity) AS quantity_sold,
				SUM(Round(lines.unit_price,2)) AS unit_price,
				SUM(Round(lines.list_price,2)) AS list_price,
				ROW_NUMBER() OVER (PARTITION BY so.id ORDER BY so.order_date, lines.product_code) AS idx
			  FROM " & FullTableName_sales_orders & " so  
			  LEFT JOIN UNNEST(lines) lines
			  LEFT JOIN shipments
				ON shipments.order_id = so.id
			  WHERE so.order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
			  GROUP BY
				so.id,
				so.order_number,
				so.state,
				so.create_date,
				so.order_date,
				so.channel_name,
				so.customer_name,
				shipments.shipment_number,
				shipments.shipment_id,
				shipments.shipped_at,
				lines.id,
				lines.product_id,
				lines.product_code
			)
			SELECT *,
			  CASE
				WHEN id IS NULL THEN 0
				WHEN idx = 1 THEN 1
				ELSE NULL
			  END AS order_id_data
			FROM sales_orders_with_index
		",
    // Connect to BigQuery using parameter
    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProjectID, UseStorageApi = false]
            ){[Name = BillingProjectID]}[Data],
            SQLStatement,
            null,
            [EnableFolding = true]
        )
in
    Source
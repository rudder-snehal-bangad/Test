let
    // Build full table reference dynamically
    FullTableName_inv_current = 
        "`" & BillingProjectID & "." & DatasetName & ".inventory_current`",
    FullTableName_inv_moves= 
        "`" & BillingProjectID & "." & DatasetName & ".inventory_moves`",
    FullTableName_sales_orders= 
        "`" & BillingProjectID & "." & DatasetName & ".sales_orders`",		

    // Build dynamic SQL
    SQLStatement = 
		" WITH inventory_current_data AS
			(
			  SELECT 
				product_id,
				product_code, 
				warehouse,
				SUM(quantity_on_hand) AS quantity_on_hand, 
				SUM(quantity_available) AS quantity_available,
				SUM(quantity_inbound) AS quantity_inbound,
				SUM(quantity_outbound) AS quantity_outbound
			  FROM " & FullTableName_inv_current & "
			  GROUP BY product_code, warehouse, product_id
			),

			inventory_moves_data AS
			(
			  SELECT 
				product_id,
				product_code, 
				from_warehouse_name AS warehouse,
				/*SUM(CASE WHEN to_location_type = 'storage' AND from_location_type IN ('view', 'storage') AND state = 'draft' AND shipment_type = 'stock.shipment.out' THEN quantity ELSE 0 END) AS quantity_outbound,*/
				SUM(CASE WHEN to_location_type = 'storage' AND state = 'assigned' THEN quantity ELSE 0 END) AS quantity_assigned
			  FROM " & FullTableName_inv_moves & "
			  WHERE state NOT IN ('cancel', 'done')
			  GROUP BY product_code, warehouse, product_id
			),

			sales_data AS
			(
			  SELECT  
				linessales.product_code,
				product_id, 
				so.warehouse,
				SUM(CASE WHEN so.state = 'done' AND linessales.line_type = 'sale' THEN linessales.quantity ELSE 0 END) AS quantity_sold,
				SUM(CASE WHEN so.state = 'done' AND linessales.line_type = 'sale' THEN linessales.untaxed_amount_cpny_ccy_cache ELSE 0 END) AS gross_sale,
				SUM(linessales.cost_price_cpny_ccy_cache) AS cost,
				SUM(CASE WHEN so.state != 'cancel' THEN linessales.gross_profit_cpny_ccy_cache ELSE 0 END) AS gross_profit,
				SUM(CASE WHEN so.state != 'cancel' AND linessales.line_type = 'return' THEN linessales.untaxed_amount_cpny_ccy_cache ELSE 0 END) AS credit
			  FROM " & FullTableName_sales_orders & " so,
			  UNNEST(lines) AS linessales
			  WHERE so.order_date >= DATE_ADD(CURRENT_DATE(), INTERVAL -1 YEAR)
			  GROUP BY linessales.product_code, so.warehouse, product_id
			)

			SELECT
			  COALESCE(icd.product_id, sd.product_id, imd.product_id) AS product_id,
			  COALESCE(icd.product_code, sd.product_code, imd.product_code) AS product_code,
			  COALESCE(icd.warehouse, sd.warehouse, imd.warehouse) AS warehouse,
			  
			  SUM(IFNULL(icd.quantity_on_hand, 0)) AS quantity_on_hand,
			  SUM(IFNULL(icd.quantity_available, 0)) AS quantity_available,
			  SUM(IFNULL(icd.quantity_inbound, 0)) AS quantity_inbound,
			  SUM(IFNULL(icd.quantity_outbound, 0)) AS quantity_outbound,
			  
			  SUM(IFNULL(imd.quantity_assigned, 0)) AS quantity_assigned,
			  
			  SUM(IFNULL(sd.quantity_sold, 0)) AS quantity_sold,
			  SUM(IFNULL(sd.gross_sale, 0) - IFNULL(sd.credit, 0)) AS net_sales
			  
			FROM inventory_current_data icd
			FULL OUTER JOIN sales_data sd
			  ON icd.product_id = sd.product_id AND icd.product_code = sd.product_code AND icd.warehouse = sd.warehouse
			FULL OUTER JOIN inventory_moves_data imd
			  ON COALESCE(icd.product_id, sd.product_id) = imd.product_id 
			  AND COALESCE(icd.product_code, sd.product_code) = imd.product_code
			  AND COALESCE(icd.warehouse, sd.warehouse) = imd.warehouse
			  
			GROUP BY 
			  COALESCE(icd.product_id, sd.product_id, imd.product_id),
			  COALESCE(icd.product_code, sd.product_code, imd.product_code),
			  COALESCE(icd.warehouse, sd.warehouse, imd.warehouse)
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
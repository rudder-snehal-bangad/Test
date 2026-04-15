let
    // Build full table reference dynamically
    FullTableName_supplier_shipments = 
        "`" & BillingProjectID & "." & DatasetName & ".supplier_shipments`",
    FullTableName_manufacturing_orders = 
        "`" & BillingProjectID & "." & DatasetName & ".manufacturing_orders`",
    FullTableName_purchase_orders = 
        "`" & BillingProjectID & "." & DatasetName & ".purchase_orders`",
	Period = Number.ToText(#"Analysis Period (Years)"),
    // Build dynamic SQL
    SQLStatement = 
		" WITH ss AS (
			  SELECT 
				ss.effective_date, 
				ss_mov.order_line_id AS purchase_line_id
			  FROM " & FullTableName_supplier_shipments & "  ss  
			  LEFT JOIN UNNEST(moves) ss_mov
			),
			mo_po as (
			  select 
			  number,
			  effective_date
			   FROM " & FullTableName_manufacturing_orders & "  
			),
			purchase_order_with_index as (
			SELECT 
			  po.id, 
			  po.number, 
			  po.purchase_date, 
			  po.state, 
			  po.supplier_name, 
			  po.requested_shipping_date, 
			  po.requested_delivery_date, 
			  po.create_date, 
			  SUM(po_line.quantity) AS quantity, 
			  CASE 
			  when ss.effective_date is not null then ss.effective_date
			  else mo_po.effective_date 
			  END as effective_date,
			  row_number() over (partition by po.id order by po.purchase_date) as idx
			FROM " & FullTableName_purchase_orders & "  po
			LEFT JOIN UNNEST(lines) po_line
			LEFT JOIN ss ON po_line.id = ss.purchase_line_id
			LEFT JOIN mo_po on po.reference = mo_po.number
			WHERE po.purchase_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
			GROUP BY 
			  po.id, 
			  po.number, 
			  po.purchase_date, 
			  po.state, 
			  po.supplier_name, 
			  po.requested_shipping_date, 
			  po.requested_delivery_date, 
			  po.create_date, 
			  effective_date)
			  SELECT *,
			  CASE
				WHEN id IS NULL THEN 0
				WHEN idx = 1 THEN 1
				ELSE NULL
			  END AS order_number_data
			FROM purchase_order_with_index
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
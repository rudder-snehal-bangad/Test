let
    // Build full table reference dynamically
    FullTableName = 
        "`" & BillingProjectID & "." & DatasetName & ".shipments`",
	Period = Number.ToText(#"Analysis Period (Years)"),
    // Build dynamic SQL
    SQLStatement = 
		" WITH customer_shipment_with_index as (
			SELECT
			  cs.id AS shipment_id,
			  cs.picker,
			  cs.packer,
			  cs.shipper,
			  cs.customer_name,
			  cs.tracking_number,
			  DATE(cs.create_date) AS create_date,  
			  cs.warehoused_date,
			  cs.planned_date,
			  cs.requested_delivery_date,
			  cs.carrier_service,
			  cs.carrier,
			  cs.shipment_address_city,
			  cs.shipment_region_name,
			  cs.shipment_country_name,
			  cs.assigned_time,
			  cs.shipped_at,
			  cs.delivered_at,
			  mov.order_line_id AS sale_line_id,
			  mov.quantity,
			  mov.product_code,
			  mov.order_number,
			  mov.state,
			  pkg.box_weight_lbs,
			  ROW_NUMBER() over( partition by cs.id order by cs.create_date, mov.product_code) as idx
			FROM " & FullTableName & " cs
			LEFT JOIN UNNEST(moves) mov
			LEFT JOIN UNNEST(packages) pkg
			WHERE DATE(cs.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
			)
			Select *,
			case when shipment_id is null then 0
			when idx = 1 then 1
			else null
			end as invoice_number_data
			from customer_shipment_with_index
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
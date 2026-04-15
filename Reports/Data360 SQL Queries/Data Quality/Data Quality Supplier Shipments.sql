let
    // Build full table reference dynamically
    FullTableName = 
        "`" & BillingProjectID & "." & DatasetName & ".supplier_shipments`",
	Period = Number.ToText(#"Analysis Period (Years)"),
    // Build dynamic SQL
    SQLStatement = 
		" WITH supplier_shipment_with_index AS (
			SELECT
			  ss.id,
			  ss.number,
			  ss.carrier,
			  ss.carrier_service,
			  ss.supplier_name,
			  ss.tracking_number,
			  DATE(ss.create_date) AS create_date,
			  ss.warehoused_date,
			  mov.from_location_name,
			  mov.to_location_name,
			  mov.effective_date,
			  mov.quantity,
			  mov.weight,
			  mov.planned_date,
			  mov.state,
			  row_number() over(partition by ss.id order by ss.tracking_number) as idx
			FROM " & FullTableName & "  ss
			LEFT JOIN UNNEST(moves) mov
			WHERE DATE(ss.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE())
			select *, 
			case when id =0 then 0
			when idx = 1 then 1
			else null
			end as shipment_order_data
			 from supplier_shipment_with_index

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
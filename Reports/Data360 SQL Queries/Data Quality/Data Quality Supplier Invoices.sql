let
    // Build full table reference dynamically
    FullTableName_account_invoices = 
        "`" & BillingProjectID & "." & DatasetName & ".account_invoices`",
    FullTableName_purchase_orders = 
        "`" & BillingProjectID & "." & DatasetName & ".purchase_orders`",
	Period = Number.ToText(#"Analysis Period (Years)"),
    // Build dynamic SQL
    SQLStatement = 
		" 
		WITH Purchase_order_with_index as (
		SELECT
		  ai.invoice_number,ai.invoice_id,
		  ai.invoice_date,
		  ai.state,
		  ai_lines.product_code,
		  po.supplier_name,
		  ai.invoice_country_name,
		  ai.invoice_country_code,
		  ai.invoice_region_name,
		  ai.invoice_region_code,
		  ai.invoice_address_city,
		  ai.payment_term_name,
		  ROUND(ai_lines.amount,2) as amount,
		  ai_lines.quantity,
		  Row_number() over (partition by ai.invoice_number order by  ai.invoice_number,ai_lines.product_code) as idx
		FROM " & FullTableName_account_invoices & "  ai
		LEFT JOIN UNNEST(lines) ai_lines
		LEFT JOIN (
		  SELECT 
			po_lines.id AS purchase_line_id, 
			supplier_name
		  FROM " & FullTableName_purchase_orders & "  po,
		  UNNEST(lines) AS po_lines
		) po
		ON ai_lines.purchase_line_id = po.purchase_line_id
		WHERE ai.invoice_type = 'in'
		AND DATE(ai.invoice_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
		)
		select *,
		case when invoice_number is null then 0
		 when idx = 1 then 1
		else null
		end as invoice_number_data
		from Purchase_order_with_index

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
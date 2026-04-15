let
    // Build full table reference dynamically
    FullTableName_account_invoices = 
        "`" & BillingProjectID & "." & DatasetName & ".account_invoices`",
    FullTableName_sales_orders = 
        "`" & BillingProjectID & "." & DatasetName & ".sales_orders`",
	Period = Number.ToText(#"Analysis Period (Years)"),
    // Build dynamic SQL
    SQLStatement = 
		" WITH invoice_lines_with_index AS (
		  SELECT
			ai.invoice_number, ai.invoice_id,
			ai.invoice_date,
			ai.state,
			ai_lines.product_code,
			so.customer_name,
			ai.invoice_country_name,
			ai.invoice_country_code,
			ai.invoice_region_name,
			ai.invoice_region_code,
			ai.invoice_address_city,
			so.channel_name,
			ai.payment_term_name,
			ROUND(ai_lines.amount,2) as amount,
			ai_lines.quantity,
			ROW_NUMBER() OVER (PARTITION BY ai.invoice_number ORDER BY ai.invoice_date, ai_lines.product_code) AS idx
		  FROM " & FullTableName_account_invoices & " ai 
		  LEFT JOIN UNNEST(ai.lines) ai_lines
		  LEFT JOIN (
			SELECT 
			  so.id as sale_order_id,
			  customer_name, 
			  channel_name, 
			  channel_code
			FROM " & FullTableName_sales_orders & " so 
		  ) so
		  ON ai_lines.sale_order_id = so.sale_order_id
		  WHERE ai.invoice_type = 'out'
			AND DATE(ai.invoice_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
		)
		SELECT *,
		  CASE
			WHEN invoice_number IS NULL OR invoice_number = '' THEN 0
			WHEN idx = 1 THEN 1
			ELSE NULL
		  END AS invoice_number_data
		FROM invoice_lines_with_index
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
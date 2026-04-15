let
	Period = Number.ToText(#"Analysis Period (Years)"),
    // Build full table reference dynamically

    FullTableName = 

        "`" & BillingProjectID & "." & DatasetName & ".account_invoices`",
 
    // Build dynamic SQL

    SQLStatement = 

		" SELECT

		  l.sale_order_channel_name AS channel,

		  l.sale_order_number as order_number,

		  inv_line.invoice_number,

		  l.sale_order_reference AS ref_number,

		  inv_line.contact_name AS party_name,

		  l.id as invoice_line_id,

		  inv_line.id as invoice_id,

		  FROM " & FullTableName & "  inv_line

		  LEFT JOIN UNNEST(inv_line.lines) AS l

		  WHERE inv_line.invoice_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()

		GROUP BY

		  l.sale_order_channel_name,

		  l.sale_order_number,

		  inv_line.invoice_number,

		  l.sale_order_reference,

		  inv_line.contact_name,

		  l.id ,

		  inv_line.id

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
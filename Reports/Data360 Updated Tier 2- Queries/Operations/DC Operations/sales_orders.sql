let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery = "
SELECT
  so.id AS sales_order_id,
  so.order_number,
  so.state AS sales_state,
  so.order_date AS sales_order_date,
  lines.product_id,
  -- lines.quantity
FROM " & BillingProject & "." & Dataset & ".sales_orders so 
LEFT JOIN UNNEST(lines) lines
WHERE DATE(so.order_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  AND so.state != 'draft'
GROUP BY so.id, so.order_number, so.state, lines.product_id, so.order_date, lines.quantity
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
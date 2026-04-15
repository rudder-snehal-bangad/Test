let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    // Dynamic table path
    AccountInvoicesTable = "`" & BillingProject & "." & Dataset & ".account_invoices`",

    // Build SQL dynamically
    SQLQuery = "
SELECT 
    ai.invoice_id,
    MIN(l.sale_order_date) AS sale_order_date,
    ANY_VALUE(ai.tax_amount) AS tax
FROM " & AccountInvoicesTable & " ai
CROSS JOIN UNNEST(ai.lines) AS l
WHERE ai.state = 'paid'
  AND ai.invoice_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  AND LOWER(l.product_code) NOT LIKE '%ship%'
GROUP BY ai.invoice_id
",

    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    )

in
    Source
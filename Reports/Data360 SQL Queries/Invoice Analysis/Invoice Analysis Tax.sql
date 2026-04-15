let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    // Dynamic table path
    AccountInvoicesTable = "`" & BillingProject & "." & Dataset & ".account_invoices`",

    SQLQuery = "
SELECT
    ai.invoice_number,
    ai.invoice_date,
    ai.tax_amount
FROM " & AccountInvoicesTable & " ai
WHERE invoice_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
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
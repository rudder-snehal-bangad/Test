let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery = "
SELECT
number as po_number, 
purchase_date, state,
supplier_name,
quantity, 
amount, 
product_code, line.requested_delivery_date,
line.requested_shipping_date
FROM " & BillingProject & "." & Dataset & ".purchase_orders po
LEFT JOIN unnest(lines) line
WHERE purchase_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
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
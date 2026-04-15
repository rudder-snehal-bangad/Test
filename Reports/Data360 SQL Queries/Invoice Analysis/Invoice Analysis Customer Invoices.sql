let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    // Dynamic table paths
    InvoicesTable = "`" & BillingProject & "." & Dataset & ".account_invoices`",
    SalesOrdersTable = "`" & BillingProject & "." & Dataset & ".sales_orders`",

    SQLQuery = "
SELECT
    invoice_date, invoice_id,
    invoice_number,
    state,
    invoice_address_city,
    invoice_region_name,
    invoice_country_name,
    tax_amount,
    lines.product_code,
    lines.quantity,
    lines.unit_price,
    lines.amount,
    lines.sale_line_id,
    sales.* EXCEPT (sale_line_id),
    payment_term_name
FROM " & InvoicesTable & " inv
LEFT JOIN UNNEST(lines) as lines
LEFT JOIN
(
    SELECT
        lines_s.id as sale_line_id,
        order_date,
        customer_name,
        channel_name,
        customer_id,
        so.shipment_region_name,
        so.shipment_country_name
    FROM " & SalesOrdersTable & " so,
    UNNEST(lines) as lines_s
    WHERE order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
) sales
ON lines.sale_line_id = sales.sale_line_id
WHERE invoice_type = 'out'
AND invoice_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
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
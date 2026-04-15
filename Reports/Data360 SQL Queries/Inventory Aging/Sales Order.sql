let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery ="
    SELECT so.order_date,  
    lines.product_code,
    so.state,
    lines.line_type as sale_type,
    sum(lines.quantity) as quantity,
    sum(lines.quantity * lines.list_price) AS gross_sales,
    invoice_region_name,invoice_country_name,invoice_address_city
    FROM `" & BasePath & ".sales_orders` so
    LEFT JOIN UNNEST(lines) as lines
    WHERE so.order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
    GROUP BY so.order_date, lines.product_code, so.state, lines.line_type,invoice_region_name,invoice_country_name,invoice_address_city",
    Source = Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProject, UseStorageApi = false]
            ){[Name = BillingProject]}[Data],
            SQLQuery,
            null,
            [EnableFolding = true]
    ),
    #"Renamed Columns" = Table.RenameColumns(Source,{{"quantity", "quantity 1"}})
in
    #"Renamed Columns"
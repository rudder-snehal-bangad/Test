let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery = "
SELECT so.order_date,
so.order_id,
so.order_number,
so.channel_name,
so.warehouse,
so.state,
lines.return_reason,
lines.line_type as sale_type,
lines.quantity,
(lines.quantity * lines.list_price) AS gross_sales,
lines.gross_profit_cpny_ccy_cache as gross_profit,
lines.product_code,
lines.product_id,
so.customer_id,
so.customer_name,
so.shipment_address_city,
so.shipment_region_code,
so.shipment_region_name,
so.shipment_address_zip,
so.shipment_country_code,
so.shipment_country_name,
so.sales_person_name,
lines.list_price as list_price,
lines.unit_price as unit_price,
lines.cost_price_cpny_ccy_cache as cost_price
FROM " & BillingProject & "." & Dataset & ".sales_orders so
left join UNNEST(lines) as lines
where so.order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
",

    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProject, UseStorageApi = false]
            ){[Name = BillingProject]}[Data],
            SQLQuery,
            null,
            [EnableFolding = true]
        ),

    #"Columns removed by Measure Killer"= Table.RemoveColumns(Source,{"shipment_address_city", "shipment_region_name", "shipment_region_code", "return_reason", "shipment_country_code", "shipment_address_zip", "order_number", "gross_profit", "cost_price"})
in
    #"Columns removed by Measure Killer"
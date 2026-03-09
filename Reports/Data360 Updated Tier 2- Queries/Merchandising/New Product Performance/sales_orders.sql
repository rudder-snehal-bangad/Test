let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery ="SELECT so.order_date,
so.order_id,
so.channel_name,
so.warehouse,
so.state,
lines.line_type as sale_type,
lines.quantity,
lines.list_price as list_price,
(lines.quantity * lines.list_price) AS gross_sales,
lines.product_code,
lines.product_id,
lines.product_name,
so.customer_id,
so.customer_name,
so.shipment_region_name,
so.shipment_country_name,
so.shipment_address_city,
so.sales_person_name,
lines.unit_price as unit_price,
lines.cost_price_cpny_ccy_cache as cogs
FROM `" & BasePath & ".sales_orders` so
left join UNNEST(lines) as lines
WHERE so.order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()"
	,
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
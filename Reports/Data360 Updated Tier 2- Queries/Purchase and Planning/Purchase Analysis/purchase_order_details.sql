let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery ="
    SELECT 
po.id as purchase_id, create_date,
number as po_number, 
purchase_date, state,
supplier_name,
invoice_address_city, invoice_region_name, 
invoice_country_name,
shipment_country_code,
line.id as purchase_line_id, quantity, 
amount,
product_code, line.requested_delivery_date,
line.requested_shipping_date
FROM `" & BasePath & ".purchase_orders` po
LEFT JOIN unnest(lines) line
WHERE purchase_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
AND line.line_type = 'purchase'"
	,
	Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
     #"Changed Type" = Table.TransformColumnTypes(Source,{{"purchase_date", type datetime}})
in
    #"Changed Type"



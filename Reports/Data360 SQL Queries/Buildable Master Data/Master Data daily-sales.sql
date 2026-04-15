let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery ="
  SELECT
    order_date, so.id,
    l.product_id,
    l.product_code,so.channel_name as sales_channel,so.channel_segment,
    so.shipment_country_name,so.shipment_region_name,so.shipment_address_city,so.customer_name,
    so.warehouse_name,so.warehouse_id
  FROM " & BasePath & ".sales_orders so
    LEFT JOIN UNNEST(lines) l
    where order_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  "
	,
	Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
    #"Removed Columns" = Table.RemoveColumns(Source,{"product_code"})
in
    #"Removed Columns"
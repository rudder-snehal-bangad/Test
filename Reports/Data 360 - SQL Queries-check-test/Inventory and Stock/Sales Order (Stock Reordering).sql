let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="SELECT so.order_date,
    so.order_id,  
so.channel_name,
lines.product_id,
lines.product_code,
so.state,
lines.line_type as sale_type,
SUM(lines.quantity) AS quantity_sold

FROM `" & BasePath & ".sales_orders` so
left join UNNEST(lines) as lines
where so.order_date >= DATE_ADD(DATE_TRUNC(current_date(), MONTH), INTERVAL -2 YEAR)
GROUP BY 
  so.order_date,
  so.order_id,
  so.channel_name,
  lines.product_id,
  lines.product_code,
  so.state,
  lines.line_type"
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
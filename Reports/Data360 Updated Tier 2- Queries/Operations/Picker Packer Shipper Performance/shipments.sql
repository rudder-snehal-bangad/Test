let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    // Dynamic table path
    ShipmentsTable = "`" & BillingProject & "." & Dataset & ".shipments`",

    SQLQuery = "
SELECT 
  CURRENT_TIMESTAMP() AS current_time_UTC,
  cs_mo.order_id AS sales_order_id,
  cs.id,
  cs.shipping_batch_number,
  cs.number,
  cs.customer_name,
  cs.state,
  cs.is_on_hold,
  cs.picker,
  cs.packer,
  cs.shipper,
  DATE(cs.create_date) AS create_date,
  cs.picked_at,
  cs.packed_at,
  cs.shipped_at,
  cs.planned_date,
  SUM(cs_mo.quantity) AS quantity,
  SUM(cs_mo.unit_price) as unit_price,
  cs_mo.order_channel_name,
  cs.assigned_time,
  cs.warehouse
FROM " & ShipmentsTable & " AS cs
LEFT JOIN UNNEST(moves) AS cs_mo
WHERE cs.state != 'cancel'
  AND DATE(cs.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  AND cs_mo.move_type = 'outgoing'
GROUP BY 
  sales_order_id,
  cs.id,
  cs.shipping_batch_number,
  cs.number,
  cs.customer_name,
  cs.state,
  cs.is_on_hold,
  cs.picker,
  cs.packer,
  cs.shipper,
  create_date,
  cs.picked_at,
  cs.packed_at,
  cs.shipped_at,
  cs.planned_date,
  cs_mo.order_channel_name,
  cs.assigned_time,
  cs.warehouse
",

    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),

    #"Changed Type" = Table.TransformColumnTypes(Source,{
        {"shipped_at", type date},
        {"quantity", Int64.Type},
        {"current_time_UTC", type date},
        {"picked_at", type date},
        {"packed_at", type date},
        {"assigned_time", type date}
    })

in
    #"Changed Type"
let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
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
  cs.warehouse_id,
  cs.warehouse,
  cs.shipment_address_city,
  cs.shipment_region_name,
  cs.shipment_country_name
FROM " & BillingProject & "." & Dataset & ".shipments AS cs 
LEFT JOIN UNNEST(moves) AS cs_mo
WHERE cs.state != 'cancel'
  AND DATE(cs.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  AND cs_mo.move_type = 'outgoing'
GROUP BY 
  sales_order_id, cs.id, cs.number, cs.state, cs.is_on_hold, cs.picker, cs.packer, cs.shipper,
  create_date,
  cs.picked_at, cs.packed_at, cs.shipped_at, cs.planned_date,
  cs_mo.order_channel_name, cs.assigned_time, cs.warehouse, cs.warehouse_id, cs.customer_name, cs.shipping_batch_number, cs.shipment_address_city,
  cs.shipment_region_name,
  cs.shipment_country_name
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

    #"Changed Type" = Table.TransformColumnTypes(Source,{{"quantity", Int64.Type}, {"shipped_at", type date}, {"packed_at", type date}, {"picked_at", type date}})
in
    #"Changed Type"
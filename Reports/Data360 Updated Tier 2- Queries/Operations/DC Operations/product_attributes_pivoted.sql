let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery = "
SELECT
  im.planned_date AS planned_date,
  im.effective_date AS effective_date,
  -- im.uuid AS uuid,
  im.product_code AS product_code,
  im.product_name AS variant,
  im.id AS line_moves,
  -- im.product_template_name,
  im.quantity,
  -- im.from_warehouse AS from_warehouse,
  -- im.to_warehouse AS to_warehouse,
  im.from_warehouse_name as warehouse_name,
  im.from_location_name AS from_location,
  im.to_location_name AS to_location,
  im.create_user_name AS create_user_name,
  im.state
FROM
  " & BillingProject & "." & Dataset & ".inventory_moves im
WHERE
  im.from_warehouse = im.to_warehouse  -- Internal bin-to-bin transfers
  AND NOT LOWER(im.from_location_name) LIKE '%input zone%'  -- Exclude putaway
  AND NOT LOWER(im.to_location_name) LIKE '%output zone%'   -- Exclude picking
  AND im.state = 'assigned'
  AND im.effective_date IS NULL
  AND im.planned_date IS NOT NULL
  AND DATE(im.planned_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()

UNION ALL

SELECT
  im.planned_date AS planned_date,
  im.effective_date AS effective_date,
  -- im.uuid AS uuid,
  im.product_code AS product_code,
  im.product_name AS variant,
  im.id AS line_moves,
  -- im.product_template_name,
  im.quantity,
  -- im.from_warehouse AS from_warehouse,
  -- im.to_warehouse AS to_warehouse,
  im.from_warehouse_name as warehouse_name,
  im.from_location_name AS from_location,
  im.to_location_name AS to_location,
  im.create_user_name AS create_user_name,
  im.state
FROM
  " & BillingProject & "." & Dataset & ".inventory_moves im
WHERE
  im.from_warehouse = im.to_warehouse  -- Internal bin-to-bin transfers
  AND NOT LOWER(im.from_location_name) LIKE '%input zone%'  -- Exclude putaway
  AND NOT LOWER(im.to_location_name) LIKE '%output zone%'   -- Exclude picking
  AND im.state = 'done'
  AND im.effective_date IS NOT NULL
  AND DATE(im.effective_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
ORDER BY
  quantity DESC
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

    #"Changed Type" = Table.TransformColumnTypes(Source,{{"quantity", Int64.Type}})
in
    #"Changed Type"
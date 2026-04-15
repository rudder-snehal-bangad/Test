let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="WITH qty_available AS(
  SELECT
    product_id,
    SUM(quantity_available) AS quantity_available
  FROM `" & BasePath & ".inventory_current`

  GROUP BY 1
),
 products as (
SELECT
    p.id,
    p.code,
    l.channel_name,
    l.sku AS listing_sku,
    l.inventory_level_cutback_type,
    CASE
        WHEN l.inventory_level_cutback_type = 'percentage'
          THEN l.inventory_level_cutback_value * COALESCE(i.quantity_available, 0)
        ELSE l.inventory_level_cutback_value
      END AS cutback_value,
    Row_number() over(partition by p.id,code,channel_name) as row_no
FROM `" & BasePath & ".products` p

LEFT JOIN UNNEST(p.listings) AS l
LEFT JOIN qty_available i ON p.id = i.product_id
where l.state ='active' 
ORDER BY p.id, l.channel_name)

select * from products where row_no = 1",
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
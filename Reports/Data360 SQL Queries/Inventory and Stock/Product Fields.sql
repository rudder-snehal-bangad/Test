let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery =
	"WITH qty_available AS (
  SELECT
    product_id,
    SUM(quantity_available) AS quantity_available
  FROM `" & BasePath & ".inventory_current`
  GROUP BY product_id
),

listing_values AS (
  SELECT
    p.id,
    --p.product_code,
    MAX(
      CASE
        WHEN ls.inventory_level_cutback_type = 'percentage'
          THEN ls.inventory_level_cutback_value * COALESCE(i.quantity_available, 0)
        ELSE ls.inventory_level_cutback_value
      END
    ) AS cutback_value
  FROM `" & BasePath & ".products` p
  LEFT JOIN UNNEST(p.listings) AS ls
  LEFT JOIN qty_available i
    ON p.id = i.product_id
  WHERE ls.state = 'active'
    AND ls.inventory_level_cutback_type IN ('fixed_quantity','percentage')
    --AND LOWER(p.product_code) NOT LIKE '%ship%'
  GROUP BY p.id
)

SELECT
  product.id,
  product.code AS product_code,
  product.variant_name,
  product.template_name,
  product.category_name,
  product.brand_name,
  product.product_type,
  product.active,
  product.is_gift_card,
  AVG(co.cost) AS cost_price,
  AVG(lp.list_price) AS list_price,
  COALESCE(lv.cutback_value, 0) AS cutback_value,
  product.sellable AS is_sellable,
  product.purchasable AS is_purchasable

FROM `" & BasePath & ".products` product

LEFT JOIN UNNEST(product.costs) AS co
LEFT JOIN UNNEST(product.list_prices) AS lp
LEFT JOIN listing_values lv
  ON product.id = lv.id

WHERE LOWER(product.code) NOT LIKE '%ship%'

GROUP BY
  product.id,
  product.code,
  product.variant_name,
  product.template_name,
  product.category_name,
  product.brand_name,
  product.product_type,
  product.active,
  product.is_gift_card,
  product.sellable,
  product.purchasable,
  lv.cutback_value",
	Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
    #"Removed Columns" = Table.RemoveColumns(Source,{"is_gift_card"})
in
    #"Removed Columns"
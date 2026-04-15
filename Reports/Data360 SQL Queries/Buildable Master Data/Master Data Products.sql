let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="WITH  ProductAttributes AS (
    SELECT 
      prod.id AS product_id,prod.active,
      TRIM(prod.code) AS product_code,
      prod.variant_name AS product_variant_name,
      prod.template_name,
      prod.category_root_name AS parent_product_category,
      prod.category_name,
      prod.brand_name,prod.product_type,
      prod.create_date AS launch_date,
      prod.purchasable,
      prod.consumable,
      prod.sellable,
      prod.manufacturable,
      prod.fulfil_strategy,
      lp.list_price,
      cp.cost as cost_price,
      hs_code, country_of_origin_code,
      l.inventory_level_cutback_value 
    FROM `" & BasePath & ".products` AS prod
      LEFT JOIN UNNEST(prod.list_prices) as lp
      LEFT JOIN UNNEST(prod.costs) as cp
      LEFT JOIN UNNEST(listings) AS l 
      --where l.inventory_level_cutback_value IS NOT NULL
    

)
SELECT
  active,
  product_id,
  product_code,
  product_variant_name,
  template_name,product_type,
  parent_product_category,
  category_name,
  brand_name,
  fulfil_strategy,
  CASE WHEN consumable THEN 'True' ELSE 'False' END AS consumable,
  CASE WHEN purchasable THEN 'True' ELSE 'False' END AS purchasable,
  CASE WHEN sellable    THEN 'True' ELSE 'False' END AS sellable,  
  CASE WHEN manufacturable    THEN 'True' ELSE 'False' END AS manufacturable,
  list_price,
  cost_price,  
  hs_code, 
  country_of_origin_code,
  launch_date,inventory_level_cutback_value
FROM ProductAttributes
QUALIFY
    COUNT(*) OVER (PARTITION BY product_code) = 1
    OR (
        COUNT(*) OVER (PARTITION BY product_code) > 1
        AND active = TRUE
    )",
	Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
    #"Removed Duplicates" = Table.Distinct(Source, {"product_code"}),
    #"Sorted Rows" = Table.Sort(#"Removed Duplicates",{{"product_code", Order.Ascending}})
in
    #"Sorted Rows"
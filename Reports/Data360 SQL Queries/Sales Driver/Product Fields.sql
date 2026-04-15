let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    // Dynamic table path
    ProductsTable = "`" & BillingProject & "." & Dataset & ".products`",

    SQLQuery = "
SELECT
  DISTINCT
  product.id,
  product.code as product_code,
  variant_name,
  product.template_name,
  product.category_name,
  product.brand_name,
  product.product_type
FROM " & ProductsTable & " product
LEFT JOIN UNNEST(costs) as co
LEFT JOIN UNNEST(list_prices) as lp
WHERE category_root_name NOT IN
  ('SERVICE','To be Classified','PACKAGING','OPTIONS_HIDDEN_PRODUCT')
",

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
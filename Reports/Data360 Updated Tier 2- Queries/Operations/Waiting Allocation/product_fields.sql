let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = "`" & BillingProject & "." & Dataset & ".products`",

    SQLQuery = "
SELECT 
  DISTINCT
  product.id,
  product.code AS product_code,
  variant_name,
  product.template_name,
  product.category_name,
  product.brand_name,
  product.product_type
FROM " & BasePath & " product 
LEFT JOIN UNNEST(costs) AS co 
LEFT JOIN UNNEST(list_prices) AS lp
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
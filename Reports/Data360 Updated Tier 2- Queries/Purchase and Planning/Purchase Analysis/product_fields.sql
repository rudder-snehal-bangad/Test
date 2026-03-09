let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="
    WITH base AS (
    SELECT DISTINCT
        product.id,
        TRIM(product.code) AS product_code,
        variant_name,
        product.template_name,
        product.category_name,
        product.brand_name,
        product.product_type,
        product.active
    FROM `" & BasePath & ".products` product
    LEFT JOIN UNNEST(costs) AS co
    LEFT JOIN UNNEST(list_prices) AS lp
    WHERE category_root_name NOT IN (
        'SERVICE',
        'To be Classified',
        'PACKAGING',
        'OPTIONS_HIDDEN_PRODUCT'
    )
)
SELECT
  id,
  product_code,
  variant_name,
  template_name,
  category_name,
  brand_name,
  product_type
FROM base
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
    )
in
    Source


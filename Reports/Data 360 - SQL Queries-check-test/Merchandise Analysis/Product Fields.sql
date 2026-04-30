let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    SQLQuery = "
WITH base AS (
  SELECT DISTINCT
    product.id,
    TRIM(product.code) AS product_code,
    variant_name,
    create_date,
    product.template_name,
    product.category_name,
    product.brand_name,
    product.product_type,
    product.active,
    co.cost AS cost_price,
    lp.list_price AS list_price,
    COUNT(DISTINCT product.id) OVER (PARTITION BY TRIM(product.code)) AS id_count
  FROM " & BillingProject & "." & Dataset & ".products product
  LEFT JOIN UNNEST(product.costs) AS co
  LEFT JOIN UNNEST(product.list_prices) AS lp
)

SELECT *
FROM base
WHERE
  (
    (id_count > 1 AND active = TRUE)
    OR id_count = 1
  )
  --AND product_code IN ('6210-BLACK-L+355C');
",

    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProject, UseStorageApi = false]
            ){[Name = BillingProject]}[Data],
            SQLQuery,
            null,
            [EnableFolding = true]
        )
in
    Source
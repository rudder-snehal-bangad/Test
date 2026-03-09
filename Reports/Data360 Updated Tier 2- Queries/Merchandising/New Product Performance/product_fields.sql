let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery ="WITH base AS (
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
  FROM " & BasePath & ".products product
  LEFT JOIN UNNEST(costs) AS co
  LEFT JOIN UNNEST(list_prices) AS lp
  WHERE Date(create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
)

SELECT *
FROM base
WHERE
  (
    (id_count > 1 AND active = TRUE)
    OR id_count = 1
  )"
	,
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
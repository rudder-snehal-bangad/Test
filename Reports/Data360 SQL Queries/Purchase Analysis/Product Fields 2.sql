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
    



// let
//     Source =
//         Value.NativeQuery(GoogleBigQuery.Database([UseStorageApi=false, BillingProject="rudder-data360-etl"]){[Name="rudder-data360-etl"]}[Data], "with base as(#(lf)SELECT #(lf)distinct product.id,#(lf)(TRIM(product.code)) AS product_code,#(lf)active,#(lf)FROM `rudder-data360-etl.fulfil_gruntstyle_bqdwh.products` product #(lf)where category_root_name not in ('SERVICE','To be Classified','PACKAGING','OPTIONS_HIDDEN_PRODUCT')#(lf))#(lf)SELECT #(lf) product_code, active#(lf)FROM base#(lf)QUALIFY#(lf)  COUNT(*) OVER (PARTITION BY product_code) = 1#(lf)  OR (#(lf)    COUNT(*) OVER (PARTITION BY product_code) > 1#(lf)    AND active = TRUE#(lf)  )", null, [EnableFolding=true])
// in
//     Source
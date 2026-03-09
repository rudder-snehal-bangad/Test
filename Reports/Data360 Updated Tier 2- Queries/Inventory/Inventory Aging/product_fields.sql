let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = "`" & BillingProject & "." & Dataset & ".products`",
    SQLQuery = "WITH base AS (#(lf)  SELECT#(lf)    product.id,#(lf)    (TRIM(product.code)) AS product_code,#(lf)    product.variant_name,#(lf)    product.template_name,#(lf)    product.template_code,#(lf)    product.category_name,#(lf)    product.brand_name,#(lf)    product.product_type,#(lf)    product.active,#(lf)    product.is_salable,#(lf)    product.is_gift_card,#(lf)#(lf)    AVG(co.cost) AS cost_price,#(lf)    AVG(lp.list_price) AS list_price,#(lf)    SUM(ls.inventory_level_cutback_value) AS cutback_value#(lf)#(lf)  FROM " & BasePath & " product#(lf)  LEFT JOIN UNNEST(product.costs) AS co#(lf)  LEFT JOIN UNNEST(product.list_prices) AS lp#(lf)  LEFT JOIN UNNEST(product.listings) AS ls#(lf)#(lf)  GROUP BY#(lf)    product.id,#(lf)    product_code,#(lf)    product.variant_name,#(lf)    product.template_name,#(lf)    product.template_code,#(lf)    product.category_name,#(lf)    product.brand_name,#(lf)    product.product_type,#(lf)    product.active,#(lf)    product.is_salable,#(lf)    product.is_gift_card#(lf))#(lf)#(lf)SELECT *#(lf)FROM base#(lf)QUALIFY#(lf)  COUNT(*) OVER (PARTITION BY product_code) = 1#(lf)  OR (#(lf)    COUNT(*) OVER (PARTITION BY product_code) > 1#(lf)    AND active = TRUE#(lf)  )",
    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
     #"Removed Columns" = Table.RemoveColumns(Source,{"is_gift_card", "is_salable"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Columns",{{"cutback_value", "cutback_value 1"}})
in
    #"Renamed Columns"
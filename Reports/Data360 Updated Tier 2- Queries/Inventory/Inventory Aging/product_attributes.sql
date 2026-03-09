let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = "`" & BillingProject & "." & Dataset & ".products`",
    SQLQuery = "WITH base AS (#(lf)  SELECT#(lf)    product.id,#(lf)    (TRIM(product.code)) AS product_code,#(lf)    product.active,#(lf)    attr.attribute_name,#(lf)    attr.value AS attribute_value#(lf)  FROM " & BasePath & " product#(lf)  LEFT JOIN UNNEST(product.attributes) AS attr#(lf))#(lf)#(lf)SELECT#(lf)  id,#(lf)  product_code,#(lf)  attribute_name,#(lf)  attribute_value#(lf)FROM base#(lf)QUALIFY#(lf)  -- If product_code is unique → keep all rows#(lf)  COUNT(*) OVER (PARTITION BY product_code) = 1#(lf)#(lf)  -- If product_code is duplicated → keep only active rows#(lf)  OR (#(lf)    COUNT(*) OVER (PARTITION BY product_code) > 1#(lf)    AND active = TRUE#(lf)  )",
    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
    #"Replaced Value" = Table.ReplaceValue(Source,"_"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value1" = Table.ReplaceValue(#"Replaced Value","-"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Capitalized Each Word" = Table.TransformColumns(#"Replaced Value1",{{"attribute_name", Text.Proper, type text}}),
    #"Replaced Value2" = Table.ReplaceValue(#"Capitalized Each Word","Sku","SKU",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value3" = Table.ReplaceValue(#"Replaced Value2","Ba","BA",Replacer.ReplaceText,{"attribute_name"}),
    #"Filtered Rows" = Table.SelectRows(#"Replaced Value3", each true),
    #"Removed Columns" = Table.RemoveColumns(#"Filtered Rows",{"id"})

in
    #"Removed Columns"
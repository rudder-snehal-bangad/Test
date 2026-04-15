let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    // BasePath = "`" & BillingProject & "." & Dataset & ".products`",
    // SQLQuery = "WITH base AS (#(lf)  SELECT#(lf)    product.id,#(lf)    (TRIM(product.code)) AS product_code,#(lf)    product.active,#(lf)    attr.attribute_name,#(lf)    attr.value AS attribute_value#(lf)  FROM " & BasePath & " product#(lf)  LEFT JOIN UNNEST(product.attributes) AS attr#(lf))#(lf)#(lf)SELECT#(lf)  id,#(lf)  product_code,#(lf)  attribute_name,#(lf)  attribute_value#(lf)FROM base#(lf)QUALIFY#(lf)  -- If product_code is unique → keep all rows#(lf)  COUNT(*) OVER (PARTITION BY product_code) = 1#(lf)#(lf)  -- If product_code is duplicated → keep only active rows#(lf)  OR (#(lf)    COUNT(*) OVER (PARTITION BY product_code) > 1#(lf)    AND active = TRUE#(lf)  )",
      BasePath = "`" & BillingProject & "." & Dataset & ".products`",

    SQLQuery = "
WITH base AS (
  SELECT
    product.id,
    TRIM(product.code) AS product_code,
    product.active,
    attr.attribute_name,
    attr.value AS attribute_value
  FROM " & BasePath & " product
  LEFT JOIN UNNEST(product.attributes) AS attr
),
filtered AS (
  SELECT *
  FROM base
  QUALIFY
    COUNT(*) OVER (PARTITION BY product_code) = 1
    OR (
      COUNT(*) OVER (PARTITION BY product_code) > 1
      AND active = TRUE
    )
),
attr_map AS (
  SELECT
    attribute_name,
    DENSE_RANK() OVER (ORDER BY attribute_name) AS slot_index,
    CONCAT('attribute_', CAST(DENSE_RANK() OVER (ORDER BY attribute_name) AS STRING)) AS attribute_slot
  FROM (
    SELECT DISTINCT attribute_name
    FROM filtered
    WHERE attribute_name IS NOT NULL
  )
)
SELECT
  f.id,
  f.product_code,
  m.attribute_slot,
  f.attribute_value
FROM filtered f
LEFT JOIN attr_map m
  ON f.attribute_name = m.attribute_name
",
    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
    #"Replaced Value" = Table.ReplaceValue(Source,null,"attribute_0",Replacer.ReplaceValue,{"attribute_slot"}),
    #"Renamed Columns" = Table.RenameColumns(#"Replaced Value",{{"attribute_slot", "attribute_name"}}),
    #"Capitalized Each Word" = Table.TransformColumns(#"Renamed Columns",{{"attribute_name", Text.Proper, type text}}),
    #"Replaced Value1" = Table.ReplaceValue(#"Capitalized Each Word","_"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Removed Columns" = Table.RemoveColumns(#"Replaced Value1",{"id"})

in
    #"Removed Columns"
//     #"Replaced Value" = Table.ReplaceValue(Source,"_"," ",Replacer.ReplaceText,{"attribute_slot"}),
//     #"Replaced Value1" = Table.ReplaceValue(#"Replaced Value","-"," ",Replacer.ReplaceText,{"attribute_slot"}),
//     #"Capitalized Each Word" = Table.TransformColumns(#"Replaced Value1",{{"attribute_slot", Text.Proper, type text}}),
//     #"Replaced Value2" = Table.ReplaceValue(#"Capitalized Each Word","Sku","SKU",Replacer.ReplaceText,{"attribute_slot"}),
//     #"Replaced Value3" = Table.ReplaceValue(#"Replaced Value2","Ba","BA",Replacer.ReplaceText,{"attribute_slot"}),
//     #"Filtered Rows" = Table.SelectRows(#"Replaced Value3", each true),
//     #"Removed Columns" = Table.RemoveColumns(#"Filtered Rows",{"id"})

// in
//     #"Removed Columns"
let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="WITH base AS (
  SELECT
    product.id,
    (TRIM(product.code)) AS product_code,
    product.active,
    attr.attribute_name,
    attr.value AS attribute_value
  FROM `" & BasePath & ".products` product
  LEFT JOIN UNNEST(product.attributes) AS attr
)
 
SELECT
  id,
  product_code,
  attribute_name,
  attribute_value
FROM base
QUALIFY
  -- If product_code is unique → keep all rows
  COUNT(*) OVER (PARTITION BY product_code) = 1
 
  -- If product_code is duplicated → keep only active rows
  OR (
    COUNT(*) OVER (PARTITION BY product_code) > 1
    AND active = TRUE
  )"
	,
	Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
    #"Replaced Value" = Table.ReplaceValue(Source,"_"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Capitalized Each Word" = Table.TransformColumns(#"Replaced Value",{{"attribute_name", Text.Proper, type text}}),
    #"Replaced Value1" = Table.ReplaceValue(#"Capitalized Each Word","-"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value2" = Table.ReplaceValue(#"Replaced Value1","Sku","SKU",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value3" = Table.ReplaceValue(#"Replaced Value2","Ba","BA",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value4" = Table.ReplaceValue(#"Replaced Value3","-"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value5" = Table.ReplaceValue(#"Replaced Value4",null,"(Blank)",Replacer.ReplaceValue,{"attribute_name"}),
    #"Pivoted Column" = Table.Pivot(#"Replaced Value5", List.Distinct(#"Replaced Value5"[attribute_name]), "attribute_name", "attribute_value"),
    #"Replaced Value6" = Table.ReplaceValue(#"Pivoted Column",null,"(Blank)",Replacer.ReplaceValue, List.Skip(Table.ColumnNames(#"Pivoted Column"), 2)),
    #"Unpivoted Other Columns" = Table.UnpivotOtherColumns(#"Replaced Value6", {"id", "product_code"}, "attribute_name", "attribute_value")
in
    #"Unpivoted Other Columns"
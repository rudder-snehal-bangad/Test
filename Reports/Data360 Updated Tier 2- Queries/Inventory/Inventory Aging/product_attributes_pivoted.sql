let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="
    WITH base AS (
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
    #"Replaced Value1" = Table.ReplaceValue(#"Replaced Value","-"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Capitalized Each Word" = Table.TransformColumns(#"Replaced Value1",{{"attribute_name", Text.Proper, type text}}),
    #"Replaced Value2" = Table.ReplaceValue(#"Capitalized Each Word","Sku","SKU",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value3" = Table.ReplaceValue(#"Replaced Value2","Ba","BA",Replacer.ReplaceText,{"attribute_name"}),
    #"Filtered Rows" = Table.SelectRows(#"Replaced Value3", each true),
    #"Removed Columns" = Table.RemoveColumns(#"Filtered Rows",{"id"}),
    #"Replaced Value4" = Table.ReplaceValue(#"Removed Columns",null,"N/A",Replacer.ReplaceValue,{"attribute_name"}),
    #"Pivoted Column" = Table.Pivot(#"Replaced Value4", List.Distinct(#"Replaced Value4"[attribute_name]), "attribute_name", "attribute_value")
in
    #"Pivoted Column"
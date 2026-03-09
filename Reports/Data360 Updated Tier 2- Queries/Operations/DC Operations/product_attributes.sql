let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    SQLQuery = "
SELECT 
product.id,
product.code as product_code,
attr.attribute_name,
attr.value as attribute_value
FROM " & BillingProject & "." & Dataset & ".products product 
left join UNNEST(attributes) as attr
",

    Source =
        Value.NativeQuery(
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
    #"Replaced Value3" = Table.ReplaceValue(#"Replaced Value2","Ba","BA",Replacer.ReplaceText,{"attribute_name"})
in
    #"Replaced Value3"
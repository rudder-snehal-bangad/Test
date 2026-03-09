let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    SQLQuery = "
SELECT DISTINCT
product.id,
product.code as product_code,
attr.attribute_name,
attr.value as attribute_value
FROM " & BillingProject & "." & Dataset & ".products product 
left join UNNEST(attributes) as attr
where category_root_name not in ('SERVICE','To be Classified','PACKAGING','OPTIONS_HIDDEN_PRODUCT')
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
    #"Replaced Value3" = Table.ReplaceValue(#"Replaced Value2","Ba","BA",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value4" = Table.ReplaceValue(#"Replaced Value3","-"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value5" = Table.ReplaceValue(#"Replaced Value4",null,"(Blank)",Replacer.ReplaceValue,{"attribute_name"}),
    #"Pivoted Column" = Table.Pivot(#"Replaced Value5", List.Distinct(#"Replaced Value5"[attribute_name]), "attribute_name", "attribute_value"),
    #"Replaced Value6" = Table.ReplaceValue(#"Pivoted Column",null,"(Blank)",Replacer.ReplaceValue, List.Skip(Table.ColumnNames(#"Pivoted Column"), 2)),
    #"Unpivoted Other Columns" = Table.UnpivotOtherColumns(#"Replaced Value6", {"id", "product_code"}, "attribute_name", "attribute_value")
in
    #"Unpivoted Other Columns"
let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    SQLQuery = "
SELECT 
distinct product.id,
product.code as product_code,
variant_name,
product.template_name,
product.template_code,
product.category_name,
product.brand_name,
product.product_type,
product.active,
product.sellable,
product.manufacturable,
--product.is_gift_card,
product.purchasable,
product.hs_code,
product.create_date,
product.fulfil_strategy,
product.consumable,
product.length,
co.cost as cost_price,
lp.list_price as list_price
FROM " & BillingProject & "." & Dataset & ".products product 
left join unnest(costs) as co 
left join unnest(list_prices) as lp
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
        )
in
    Source
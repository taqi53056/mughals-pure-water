drop index if exists public.finished_goods_one_entry_per_product_date_uidx;

create unique index if not exists finished_goods_one_entry_per_product_uidx
  on public.finished_goods(product_type);

comment on index public.finished_goods_one_entry_per_product_uidx is
  'Only one opening-stock row is allowed per finished product; later stock movements use production or stock adjustments.';

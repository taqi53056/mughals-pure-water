alter table public.unassigned_19l_deliveries alter column worker_id drop not null;
alter table public.unassigned_19l_deliveries add column if not exists performed_by_owner boolean not null default false;
alter table public.unassigned_19l_deliveries add column if not exists owner_labor_saving numeric generated always as (case when performed_by_owner then coalesce(empty_bottles_returned,0)::numeric*20 else 0 end) stored;
alter table public.unassigned_19l_deliveries add constraint unassigned_19l_owner_worker_choice_check check ((performed_by_owner and worker_id is null) or (not performed_by_owner and worker_id is not null));

create or replace function public.sync_unassigned_19l_worker_ledger()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_labor numeric;
begin
 if tg_op in ('UPDATE','DELETE') then
  delete from public.worker_ledger where source_table='unassigned_19l_deliveries' and source_id=old.id;
 end if;
 if tg_op='DELETE' then return old; end if;
 if new.performed_by_owner then
  if new.worker_id is not null then raise exception 'مالک کی سپلائی میں ورکر منتخب نہیں ہونا چاہیے۔' using errcode='23514'; end if;
  return new;
 end if;
 if new.worker_id is null or not exists(select 1 from public.workers w where w.id=new.worker_id and w.is_active and not w.is_owner and w.work_categories @> array['19L delivery']::text[]) then
  raise exception 'منتخب ورکر فعال نہیں یا 19L ڈیلیوری کے لیے مقرر نہیں۔' using errcode='23514';
 end if;
 v_labor:=coalesce(new.empty_bottles_returned,0)::numeric*20;
 if v_labor>0 then
  insert into public.worker_ledger(worker_id,entry_date,entry_type,work_category,amount,note,source_table,source_id,entered_by,request_id)
  values(new.worker_id,new.delivery_date,'earning','19L delivery',v_labor,'غیر منسلک 19L سپلائی — '||coalesce(new.empty_bottles_returned,0)||' کامیاب بوتلیں','unassigned_19l_deliveries',new.id,new.entered_by,new.request_id);
 end if;
 return new;
end $$;
revoke all on function public.sync_unassigned_19l_worker_ledger() from public,anon,authenticated;

drop function public.record_unassigned_19l_delivery(date,bigint,integer,integer,text,uuid,integer);
create function public.record_unassigned_19l_delivery(p_delivery_date date,p_worker_id bigint,p_bottles_delivered integer,p_empty_bottles_returned integer default 0,p_details text default null,p_request_id uuid default null,p_damaged_caps integer default 0,p_performed_by_owner boolean default false)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
 v_existing public.unassigned_19l_deliveries%rowtype;
 v_id bigint; v_available numeric:=0; v_consumed numeric:=0;
 v_today date:=(now() at time zone 'Asia/Karachi')::date;
 v_worker public.workers%rowtype; v_labor_amount numeric:=0;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'صرف مجاز ایڈمن یہ اندراج کر سکتا ہے۔' using errcode='42501'; end if;
 if p_request_id is null then raise exception 'درخواست کی شناخت موجود نہیں۔' using errcode='22023'; end if;
 if p_delivery_date is null or p_delivery_date>v_today then raise exception 'مستقبل کی تاریخ پر سپلائی درج نہیں ہو سکتی۔' using errcode='22023'; end if;
 if p_bottles_delivered is null or p_bottles_delivered<=0 then raise exception 'بوتلوں کی تعداد ایک یا زیادہ ہونی چاہیے۔' using errcode='22023'; end if;
 if coalesce(p_empty_bottles_returned,0)<0 or coalesce(p_empty_bottles_returned,0)>p_bottles_delivered then raise exception 'واپس آنے والی خالی بوتلوں کی تعداد درست درج کریں۔' using errcode='22023'; end if;
 if coalesce(p_damaged_caps,0)<0 then raise exception 'خراب ڈھکنوں کی تعداد صفر یا زیادہ ہونی چاہیے۔' using errcode='22023'; end if;
 if p_performed_by_owner then
  if p_worker_id is not null then raise exception 'مالک کی سپلائی کے ساتھ ورکر منتخب نہیں کیا جا سکتا۔' using errcode='22023'; end if;
 else
  select * into v_worker from public.workers where id=p_worker_id and is_active and not is_owner and work_categories @> array['19L delivery']::text[];
  if not found then raise exception 'منتخب ورکر فعال نہیں یا 19L ڈیلیوری کے لیے مقرر نہیں۔' using errcode='22023'; end if;
 end if;
 v_labor_amount:=case when p_performed_by_owner then 0 else coalesce(p_empty_bottles_returned,0)::numeric*20 end;
 select * into v_existing from public.unassigned_19l_deliveries where request_id=p_request_id;
 if found then
  if v_existing.delivery_date<>p_delivery_date or v_existing.worker_id is distinct from p_worker_id or v_existing.performed_by_owner<>p_performed_by_owner or v_existing.bottles_delivered<>p_bottles_delivered or v_existing.empty_bottles_returned<>coalesce(p_empty_bottles_returned,0) or v_existing.damaged_caps<>coalesce(p_damaged_caps,0) or v_existing.details is distinct from nullif(btrim(p_details),'') then
   raise exception 'یہ درخواست پہلے مختلف تفصیل کے ساتھ محفوظ ہو چکی ہے۔' using errcode='23505';
  end if;
  return jsonb_build_object('id',v_existing.id,'worker_id',v_existing.worker_id,'performed_by_owner',v_existing.performed_by_owner,'owner_labor_saving',v_existing.owner_labor_saving,'bottles_delivered',v_existing.bottles_delivered,'successful_bottles',v_existing.empty_bottles_returned,'damaged_caps',v_existing.damaged_caps,'labor_amount',v_existing.labor_amount,'already_saved',true);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('mpw-month-close-'||date_trunc('month',p_delivery_date)::date::text,0));
 if exists(select 1 from public.business_month_closings c where c.month_start=date_trunc('month',p_delivery_date)::date and c.status='closed') then raise exception 'یہ مہینہ بند ہو چکا ہے؛ اس تاریخ کا اندراج ممکن نہیں۔' using errcode='55000'; end if;
 perform pg_advisory_xact_lock(hashtextextended('water-pool-shop',0));
 select coalesce((select sum(tanker_count*1000) from public.water_tanker_purchases where water_use='shop_counter' and purchase_date<=p_delivery_date),0)+coalesce((select sum(litres) from public.water_opening_stock where water_use='shop_counter' and as_of_date<=p_delivery_date),0) into v_available;
 select coalesce((select sum(bottles_delivered*19) from public.customer_19l_deliveries where delivery_date<=p_delivery_date),0)+coalesce((select sum(total_litres) from public.counter_water_sales where sale_date<=p_delivery_date),0)+coalesce((select sum(quantity*6) from public.production where product_type='6L' and production_date<=p_delivery_date),0)+coalesce((select sum(bottles_delivered*19) from public.unassigned_19l_deliveries where delivery_date<=p_delivery_date),0) into v_consumed;
 if v_available-v_consumed<p_bottles_delivered*19 then raise exception 'دکان والی ٹنکی کا پانی ناکافی ہے۔ دستیاب لیٹر: %، درکار: %',greatest(v_available-v_consumed,0),p_bottles_delivered*19 using errcode='23514'; end if;
 insert into public.unassigned_19l_deliveries(delivery_date,worker_id,performed_by_owner,bottles_delivered,empty_bottles_returned,damaged_caps,details,request_id,entered_by)
 values(p_delivery_date,p_worker_id,p_performed_by_owner,p_bottles_delivered,coalesce(p_empty_bottles_returned,0),coalesce(p_damaged_caps,0),nullif(btrim(p_details),''),p_request_id,auth.uid()) returning id into v_id;
 if v_labor_amount>0 then
  insert into public.worker_ledger(worker_id,entry_date,entry_type,work_category,amount,note,source_table,source_id,entered_by,request_id)
  values(p_worker_id,p_delivery_date,'earning','19L delivery',v_labor_amount,'غیر منسلک 19L سپلائی — '||coalesce(p_empty_bottles_returned,0)||' کامیاب بوتلیں','unassigned_19l_deliveries',v_id,auth.uid(),p_request_id);
 end if;
 return jsonb_build_object('id',v_id,'worker_id',p_worker_id,'performed_by_owner',p_performed_by_owner,'owner_labor_saving',case when p_performed_by_owner then coalesce(p_empty_bottles_returned,0)*20 else 0 end,'bottles_delivered',p_bottles_delivered,'successful_bottles',coalesce(p_empty_bottles_returned,0),'damaged_caps',coalesce(p_damaged_caps,0),'labor_amount',v_labor_amount,'already_saved',false);
end $$;
revoke all on function public.record_unassigned_19l_delivery(date,bigint,integer,integer,text,uuid,integer,boolean) from public,anon;
grant execute on function public.record_unassigned_19l_delivery(date,bigint,integer,integer,text,uuid,integer,boolean) to authenticated;

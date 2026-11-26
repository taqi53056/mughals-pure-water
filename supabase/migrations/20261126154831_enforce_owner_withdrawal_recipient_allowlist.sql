create or replace function private.enforce_owner_withdrawal_recipient_allowlist()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.entry_type='owner_withdrawal'
    and new.counterparty not in ('M. Muzamil Mughal','M.Taqi Mughal','M.Usama Mughal','M. Rafi Mughal') then
    raise exception 'مالک کی نکاسی کے لیے صرف مقررہ چار وصول کنندگان منتخب کیے جا سکتے ہیں۔'
      using errcode='23514';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_owner_withdrawal_recipient_allowlist on public.business_finance_ledger;
create trigger enforce_owner_withdrawal_recipient_allowlist
before insert or update of entry_type,counterparty
on public.business_finance_ledger
for each row
execute function private.enforce_owner_withdrawal_recipient_allowlist();

comment on function private.enforce_owner_withdrawal_recipient_allowlist() is
'Restricts new owner-withdrawal records to the three admins and the separate non-admin withdrawal participant.';
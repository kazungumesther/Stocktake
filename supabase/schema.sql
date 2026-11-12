

create table stock_items (
  -- The app creates the id on the device, so items can exist before they sync.
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  quantity integer not null default 0,
  unit text not null default 'pcs',
  location text,
  notes text,
  -- When the user made the edit (set by the device). Last-write-wins compares this.
  updated_at timestamptz not null,
  -- Soft delete, so deletions can sync to other devices.
  deleted_at timestamptz,
  -- When the server stored the change (set below). The app asks for "changes since".
  server_updated_at timestamptz not null default clock_timestamp()
);

create index stock_items_user_changes_idx on stock_items (user_id, server_updated_at);

alter table stock_items enable row level security;

create policy "Users manage their own stock items"
  on stock_items for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on stock_items to authenticated;

-- Conflict rule enforced by the database itself:
-- an older edit never overwrites a newer one, and every accepted write gets a
-- fresh server timestamp so other devices can find it.
create or replace function stock_items_before_write() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null; -- ignore the stale write
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger stock_items_before_write
  before insert or update on stock_items
  for each row execute function stock_items_before_write();

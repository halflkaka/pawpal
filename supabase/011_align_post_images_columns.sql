do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'post_images'
      and column_name = 'image_url'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'post_images'
      and column_name = 'url'
  ) then
    alter table post_images rename column image_url to url;
  end if;
end $$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'post_images'
      and column_name = 'sort_order'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'post_images'
      and column_name = 'position'
  ) then
    alter table post_images rename column sort_order to position;
  end if;
end $$;

alter table post_images
  add column if not exists url text;

alter table post_images
  add column if not exists position int not null default 0;

update post_images
set url = image_url
where url is null
  and exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'post_images'
      and column_name = 'image_url'
  );

update post_images
set position = sort_order
where exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'post_images'
      and column_name = 'sort_order'
  );

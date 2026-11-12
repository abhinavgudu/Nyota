-- Gift images storage bucket + policies
-- Images live at paths: <user-uuid>/<entry-uuid>/<filename>
insert into storage.buckets (id, name, public)
values ('gift-images', 'gift-images', true)
on conflict (id) do update set public = true;

-- Allow authenticated users to upload only inside their own folder
drop policy if exists "gift_images_insert_own_folder" on storage.objects;
create policy "gift_images_insert_own_folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'gift-images'
    and (storage.foldername(name))[1] = auth.uid ()::text
  );

drop policy if exists "gift_images_select_public" on storage.objects;
create policy "gift_images_select_public" on storage.objects
  for select using (bucket_id = 'gift-images');

drop policy if exists "gift_images_update_own_folder" on storage.objects;
create policy "gift_images_update_own_folder" on storage.objects
  for update to authenticated
  using (bucket_id = 'gift-images' and (storage.foldername(name))[1] = auth.uid ()::text)
  with check (bucket_id = 'gift-images' and (storage.foldername(name))[1] = auth.uid ()::text);

drop policy if exists "gift_images_delete_own_folder" on storage.objects;
create policy "gift_images_delete_own_folder" on storage.objects
  for delete to authenticated
  using (bucket_id = 'gift-images' and (storage.foldername(name))[1] = auth.uid ()::text);

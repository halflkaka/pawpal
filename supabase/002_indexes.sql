create index if not exists idx_pets_owner_user_id on pets(owner_user_id);
create index if not exists idx_posts_owner_user_id on posts(owner_user_id);
create index if not exists idx_posts_pet_id on posts(pet_id);
create index if not exists idx_posts_created_at on posts(created_at desc);
create index if not exists idx_post_images_post_id on post_images(post_id);
create index if not exists idx_follows_follower_user_id on follows(follower_user_id);
create index if not exists idx_follows_followed_user_id on follows(followed_user_id);

-- MORP.IO v2 — kole tout script sa a nan Supabase > SQL Editor epi klike RUN.
-- Li ka kouri plizyè fwa san danje (idempotent). Done ki deja egziste yo rete.
-- ADMIN: chanje imèl admin an nan fonksyon create_profile_for si se pa sa a.

------------------------------------------------------------------ TABLES
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  email text,
  phone text,
  avatar_url text,
  provider text not null default 'email',
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_uidx on public.profiles (upper(username));

create table if not exists public.app_settings (
  key text primary key,
  value text not null default '',
  updated_at timestamptz not null default now()
);
insert into public.app_settings(key, value) values
 ('rules', E'Morp.io se yon jwèt 5 nan yon liy sou yon tablo ki pa gen limit.\n\n1. X kòmanse premye, answit chak jwè jwe yon sèl fwa chak tou.\n2. Premye jwè ki aliyen 5 mòpyon (orizontal, vètikal oswa dyagonal) genyen.\n3. Ou gen 60 segonn pou chak kou. Si w depase tan an, w pèdi.\n4. Si w kite match la, se yon forfè epi advèsè w la genyen.\n5. Match ak lajan an kòmanse sèlman lè administratè a valide de peman yo.'),
 ('welcome_message', 'Byenveni nan Morp.io HT! Objektif la se mete 5 mak youn apre lòt pou genyen. X kòmanse, epi chak jwè gen 60 segonn pou jwe. Ou ka jwe ak òdinatè, chèche yon etranje, oswa antre kòd yon zanmi. Pou yon match ak lajan, tou de jwè yo dwe voye menm kantite lajan an epi tann administratè a konfime peman yo. Ou ka reponn mesaj sa a si w bezwen èd.'),
 ('push_vapid_public_key', ''),
 ('natcash', '+509 55 67 9002')
on conflict (key) do nothing;

create table if not exists public.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  start_text text,
  max_players int not null default 8 check (max_players between 2 and 256),
  fee int not null default 0 check (fee >= 0),
  payment_info text,
  prize1 text, prize2 text, prize3 text,
  winner1 uuid, winner2 uuid, winner3 uuid,
  note text,
  status text not null default 'open' check (status in ('open','finished')),
  created_at timestamptz not null default now()
);

create table if not exists public.tournament_entries (
  id bigserial primary key,
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','paid')),
  payment_submitted_at timestamptz not null default now(),
  paid_at timestamptz,
  validated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (tournament_id, user_id)
);

alter table public.tournaments
  add column if not exists started_at timestamptz,
  add column if not exists finished_at timestamptz;

create table if not exists public.tournament_matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  round_name text not null default 'Premye match',
  position integer not null default 1,
  p1_id uuid references public.profiles(id) on delete set null,
  p2_id uuid references public.profiles(id) on delete set null,
  p1_name text,
  p2_name text,
  p1_ready boolean not null default false,
  p2_ready boolean not null default false,
  status text not null default 'waiting' check (status in ('waiting','playing','finished','cancelled')),
  game_id uuid,
  winner_id uuid references public.profiles(id) on delete set null,
  winner_name text,
  next_match_id uuid,
  next_slot integer check (next_slot in (1,2)),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  unique (tournament_id, round_name, position)
);

alter table public.tournament_entries
  add column if not exists payment_submitted_at timestamptz not null default now(),
  add column if not exists paid_at timestamptz,
  add column if not exists validated_by uuid references public.profiles(id);

alter table public.tournament_matches
  add column if not exists game_id uuid;

create table if not exists public.admin_messages (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  from_admin boolean not null default true,
  read boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.admin_messages add column if not exists from_admin boolean not null default true;
create index if not exists admin_messages_conversation_idx on public.admin_messages (user_id, created_at desc, id desc);

create table if not exists public.player_chat_messages (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index if not exists player_chat_user_id_idx on public.player_chat_messages (user_id, id desc);

create table if not exists public.push_subscriptions (
  endpoint text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  subscription jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_id_idx on public.push_subscriptions (user_id);

-- Tab ki te deja la yo (pa efase done yo)
create table if not exists public.games (id uuid primary key default gen_random_uuid(), p1_name text not null, created_at timestamptz not null default now());
create table if not exists public.game_secrets (game_id uuid primary key references public.games(id) on delete cascade, token text not null default replace(gen_random_uuid()::text,'-',''));
create table if not exists public.moves (id bigserial primary key, game_id uuid not null references public.games(id) on delete cascade, r int not null, c int not null, mark text not null);
create table if not exists public.match_history (id bigserial primary key, game_id uuid not null unique, p1_name text not null, p2_name text not null, winner_name text not null, winner_mark text not null, move_count integer not null default 0, finished_at timestamptz not null default now());
create table if not exists public.players (name text primary key, created_at timestamptz not null default now());

alter table public.games
  add column if not exists code text,
  add column if not exists p2_name text,
  add column if not exists amount text,
  add column if not exists seeking boolean not null default false,
  add column if not exists expires_at timestamptz,
  add column if not exists status text not null default 'waiting',
  add column if not exists p1_paid boolean not null default false,
  add column if not exists p2_paid boolean not null default false,
  add column if not exists turn text not null default 'X',
  add column if not exists turn_started_at timestamptz,
  add column if not exists winner text,
  add column if not exists finish_reason text,
  add column if not exists mailed boolean not null default false,
  add column if not exists last_seen timestamptz not null default now(),
  add column if not exists p1_id uuid references public.profiles(id) on delete set null,
  add column if not exists p2_id uuid references public.profiles(id) on delete set null;
alter table public.games
  add column if not exists is_friend_match boolean not null default false;

alter table public.match_history
  add column if not exists finish_reason text not null default 'win',
  add column if not exists p1_id uuid references public.profiles(id) on delete set null,
  add column if not exists p2_id uuid references public.profiles(id) on delete set null,
  add column if not exists is_friend_match boolean not null default false,
  add column if not exists amount text;

update public.games set is_friend_match = true
 where code is not null or status = 'pending_payment';

alter table public.games drop constraint if exists games_finish_reason_check;
alter table public.games add constraint games_finish_reason_check check (finish_reason is null or finish_reason in ('win','forfeit','timeout'));
alter table public.match_history drop constraint if exists match_history_finish_reason_check;
alter table public.match_history add constraint match_history_finish_reason_check check (finish_reason in ('win','forfeit','timeout'));
alter table public.match_history drop constraint if exists match_history_winner_mark_check;
alter table public.match_history add constraint match_history_winner_mark_check check (winner_mark in ('X','O'));

create unique index if not exists moves_game_cell_uidx on public.moves (game_id, r, c);
create index if not exists match_history_finished_at_idx on public.match_history (finished_at desc);
create index if not exists games_status_idx on public.games (status);
create index if not exists tournament_matches_tournament_idx on public.tournament_matches (tournament_id, round_name, position);
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'tournament_matches_game_id_fkey'
  ) then
    alter table public.tournament_matches
      add constraint tournament_matches_game_id_fkey
      foreign key (game_id) references public.games(id) on delete set null;
  end if;
end $$;

-- Netwaye kòd ak done peman ki rete sou match ki deja fini
delete from public.moves m using public.match_history h where m.game_id = h.game_id;
delete from public.game_secrets s using public.match_history h where s.game_id = h.game_id;
update public.games g set code=null, amount=null, seeking=false, expires_at=null, p1_paid=false, p2_paid=false, mailed=false
 where g.status='finished' or exists (select 1 from public.match_history h where h.game_id=g.id);

------------------------------------------------------------------ SIKIRITE (RLS)
alter table public.profiles enable row level security;
alter table public.app_settings enable row level security;
alter table public.tournaments enable row level security;
alter table public.tournament_entries enable row level security;
alter table public.tournament_matches enable row level security;
alter table public.admin_messages enable row level security;
alter table public.player_chat_messages enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.games enable row level security;
alter table public.moves enable row level security;
alter table public.game_secrets enable row level security;
alter table public.match_history enable row level security;
alter table public.players enable row level security;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public, pg_temp
as $$ select coalesce((select is_admin from public.profiles where id = auth.uid()), false) $$;

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists "read settings" on public.app_settings;
create policy "read settings" on public.app_settings for select to anon, authenticated using (true);
drop policy if exists "read tournaments" on public.tournaments;
create policy "read tournaments" on public.tournaments for select to anon, authenticated using (true);
drop policy if exists "read tournament matches" on public.tournament_matches;
create policy "read tournament matches" on public.tournament_matches for select to anon, authenticated using (true);
drop policy if exists "own messages" on public.admin_messages;
create policy "own messages" on public.admin_messages for select to authenticated using (user_id = auth.uid());
drop policy if exists "read games" on public.games;
create policy "read games" on public.games for select to anon, authenticated using (true);
drop policy if exists "read moves" on public.moves;
create policy "read moves" on public.moves for select to anon, authenticated using (true);
drop policy if exists "read match history" on public.match_history;
create policy "read match history" on public.match_history for select to anon, authenticated using (true);

revoke all on table public.profiles, public.app_settings, public.tournaments, public.tournament_entries, public.tournament_matches, public.admin_messages,
  public.player_chat_messages, public.push_subscriptions,
  public.games, public.moves, public.game_secrets, public.match_history, public.players from anon, authenticated;
grant select on table public.profiles, public.admin_messages to authenticated;
grant select on table public.app_settings, public.tournaments, public.games, public.moves, public.match_history to anon, authenticated;
grant select on table public.tournament_matches to anon, authenticated;
grant usage on schema public to anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_publication where pubname='supabase_realtime') then create publication supabase_realtime; end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='games') then
    alter publication supabase_realtime add table public.games; end if;
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='moves') then
    alter publication supabase_realtime add table public.moves; end if;
end $$;

------------------------------------------------------------------ PWOFIL
create or replace function public.unique_username(p_base text, p_uid uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare b text := left(trim(regexp_replace(coalesce(p_base,''), '[[:space:]]+', ' ', 'g')), 30); n text; i int := 1;
begin
  if b = '' then b := 'Jwe'; end if;
  n := b;
  while exists (select 1 from public.profiles where upper(username) = upper(n) and id is distinct from p_uid) loop
    i := i + 1; n := left(b, 26) || ' ' || i;
  end loop;
  return n;
end $$;

create or replace function public.create_profile_for(p_id uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare u auth.users; meta jsonb; created_id uuid; welcome_text text;
begin
  select * into u from auth.users where id = p_id;
  if not found then return; end if;
  meta := coalesce(u.raw_user_meta_data, '{}'::jsonb);
  insert into public.profiles(id, username, email, phone, avatar_url, provider, is_admin)
  values (p_id,
    public.unique_username(coalesce(nullif(meta->>'full_name',''), nullif(meta->>'name',''), split_part(coalesce(u.email,''),'@',1)), p_id),
    u.email, nullif(meta->>'whatsapp',''), coalesce(nullif(meta->>'avatar_url',''), nullif(meta->>'picture','')),
    coalesce(u.raw_app_meta_data->>'provider','email'),
    lower(coalesce(u.email,'')) = lower('alexisbigy509@gmail.com'))
  on conflict (id) do nothing returning id into created_id;
  if created_id is not null then
    select coalesce((select nullif(trim(value),'') from public.app_settings where key = 'welcome_message'),
      'Byenveni nan Morp.io HT! Objektif la se mete 5 mak youn apre lòt pou genyen. X kòmanse, epi chak jwè gen 60 segonn pou jwe. Ou ka jwe ak òdinatè, chèche yon etranje, oswa antre kòd yon zanmi. Pou yon match ak lajan, tou de jwè yo dwe voye menm kantite lajan an epi tann administratè a konfime peman yo. Ou ka reponn mesaj sa a si w bezwen èd.')
      into welcome_text;
    insert into public.admin_messages(user_id, body, from_admin) values (created_id, welcome_text, true);
  end if;
end $$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$ begin perform public.create_profile_for(new.id); return new; end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Admin: si kont lan egziste deja
select public.create_profile_for(id) from auth.users;
update public.profiles set is_admin = true where lower(email) = lower('alexisbigy509@gmail.com');

create or replace function public.update_my_profile(p_username text, p_phone text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); n text := trim(regexp_replace(coalesce(p_username,''), '[[:space:]]+', ' ', 'g')); ph text := nullif(trim(coalesce(p_phone,'')), '');
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  if char_length(n) < 2 or char_length(n) > 30 then raise exception 'Non an dwe genyen ant 2 ak 30 karaktè.'; end if;
  if ph is not null and ph !~ '^\+?[0-9 ]{8,16}$' then raise exception 'Nimewo WhatsApp la pa valab.'; end if;
  if exists (select 1 from public.profiles where upper(username) = upper(n) and id <> uid) then raise exception 'Non sa a deja pran.'; end if;
  update public.profiles set username = n, phone = ph where id = uid;
  update public.games set p1_name = n where p1_id = uid;
  update public.games set p2_name = n where p2_id = uid;
  update public.match_history set p1_name = n where p1_id = uid;
  update public.match_history set p2_name = n where p2_id = uid;
  update public.match_history set winner_name = case when winner_mark = 'X' then p1_name else p2_name end where p1_id = uid or p2_id = uid;
end $$;

create or replace function public.my_overview() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); p public.profiles;
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  select * into p from public.profiles where id = uid;
  if not found then perform public.create_profile_for(uid); select * into p from public.profiles where id = uid; end if;
  return jsonb_build_object(
    'profile', to_jsonb(p),
    'matches', (select count(*) from public.match_history h where h.p1_id = uid or h.p2_id = uid),
    'wins', (select count(*) from public.match_history h where (h.winner_mark='X' and h.p1_id=uid) or (h.winner_mark='O' and h.p2_id=uid)),
    'history', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('id', h.id, 'opponent', case when h.p1_id = uid then h.p2_name else h.p1_name end,
          'won', (h.winner_mark='X' and h.p1_id=uid) or (h.winner_mark='O' and h.p2_id=uid),
          'reason', h.finish_reason, 'moves', h.move_count, 'finished_at', h.finished_at) x
        from public.match_history h where h.p1_id = uid or h.p2_id = uid order by h.finished_at desc limit 200) s),
    'messages', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'body', m.body, 'created_at', m.created_at) order by m.created_at desc), '[]'::jsonb)
        from public.admin_messages m where m.user_id = uid and m.from_admin and not m.read));
end $$;

create or replace function public.mark_messages_read() returns void language sql security definer set search_path = public, pg_temp
as $$ update public.admin_messages set read = true where user_id = auth.uid() and from_admin and not read $$;

create or replace function public.my_message_thread() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  update public.admin_messages set read = true where user_id = uid and from_admin and not read;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'body', m.body, 'from_admin', m.from_admin,
      'read', m.read, 'created_at', m.created_at) order by m.created_at, m.id), '[]'::jsonb)
    from (select id, body, from_admin, read, created_at from public.admin_messages
      where user_id = uid order by created_at desc, id desc limit 200) m);
end $$;

create or replace function public.send_user_message(p_body text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); body_text text := trim(coalesce(p_body,''));
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  if char_length(body_text) not between 1 and 500 then raise exception 'Mesaj la dwe genyen ant 1 ak 500 karaktè.'; end if;
  if not exists (select 1 from public.profiles where id = uid) then raise exception 'Pwofil la pa jwenn.'; end if;
  insert into public.admin_messages(user_id, body, from_admin) values (uid, body_text, false);
end $$;

create or replace function public.get_player_chat_messages(p_after_id bigint default 0) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); after_id bigint := coalesce(p_after_id, 0);
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  if after_id < 0 then raise exception 'Pozisyon mesaj la pa valab.'; end if;
  if not exists (select 1 from public.profiles where id = uid) then raise exception 'Pwofil la pa jwenn.'; end if;
  if after_id = 0 then
    return (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'user_id', m.user_id,
        'username', m.username, 'body', m.body, 'created_at', m.created_at) order by m.id), '[]'::jsonb)
      from (select c.id, c.user_id, p.username, c.body, c.created_at
        from public.player_chat_messages c join public.profiles p on p.id = c.user_id
        order by c.id desc limit 100) m);
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'user_id', m.user_id,
      'username', m.username, 'body', m.body, 'created_at', m.created_at) order by m.id), '[]'::jsonb)
    from (select c.id, c.user_id, p.username, c.body, c.created_at
      from public.player_chat_messages c join public.profiles p on p.id = c.user_id
      where c.id > after_id order by c.id limit 100) m);
end $$;

create or replace function public.send_player_chat_message(p_body text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); body_text text := trim(coalesce(p_body,'')); last_sent timestamptz;
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  if char_length(body_text) not between 1 and 500 then raise exception 'Mesaj la dwe genyen ant 1 ak 500 karaktè.'; end if;
  if not exists (select 1 from public.profiles where id = uid) then raise exception 'Pwofil la pa jwenn.'; end if;
  perform pg_advisory_xact_lock(hashtext('player-chat:' || uid::text));
  select created_at into last_sent from public.player_chat_messages
    where user_id = uid order by id desc limit 1;
  if last_sent > clock_timestamp() - interval '2 seconds' then
    raise exception 'Tann de segonn anvan ou voye yon lòt mesaj.';
  end if;
  insert into public.player_chat_messages(user_id, body, created_at)
    values (uid, body_text, clock_timestamp());
end $$;

create or replace function public.get_push_vapid_public_key() returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select nullif(trim(value),'') from public.app_settings where key = 'push_vapid_public_key'
$$;

create or replace function public.save_push_subscription(p_subscription jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); endpoint_value text := coalesce(p_subscription->>'endpoint','');
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  if not exists (select 1 from public.profiles where id = uid) then raise exception 'Pwofil la pa jwenn.'; end if;
  if jsonb_typeof(p_subscription) <> 'object'
    or coalesce(jsonb_typeof(p_subscription->'keys'),'') <> 'object'
    or char_length(endpoint_value) > 2048
    or endpoint_value !~* '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|push\.services\.mozilla\.com|web\.push\.apple\.com|[a-z0-9-]+\.notify\.windows\.com)(/|$)'
    or coalesce(p_subscription->'keys'->>'p256dh','') = ''
    or coalesce(p_subscription->'keys'->>'auth','') = '' then
    raise exception 'Abònman notifikasyon sa a pa valab.';
  end if;
  insert into public.push_subscriptions(endpoint, user_id, subscription, created_at)
    values (endpoint_value, uid, p_subscription, now())
    on conflict (endpoint) do update set user_id = excluded.user_id,
      subscription = excluded.subscription, created_at = now();
end $$;

create or replace function public.remove_push_subscription(p_endpoint text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Ou dwe konekte.'; end if;
  delete from public.push_subscriptions where user_id = auth.uid() and endpoint = p_endpoint;
end $$;

-- Meyè jwè: plis viktwa, answit mwens defèt, answit pi ansyen kont.
-- Telefòn nan retounen sèlman si moun k ap mande a gen omwen 20 viktwa epi li pa li menm meyè jwè a.
create or replace function public.best_player() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); b record; my_wins int;
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  select count(*) into my_wins from public.match_history h where (h.winner_mark='X' and h.p1_id=uid) or (h.winner_mark='O' and h.p2_id=uid);
  select p.id, p.username, p.phone,
    (select count(*) from public.match_history h where (h.winner_mark='X' and h.p1_id=p.id) or (h.winner_mark='O' and h.p2_id=p.id)) wins,
    (select count(*) from public.match_history h where h.p1_id=p.id or h.p2_id=p.id) matches, p.created_at
  into b from public.profiles p
  order by 4 desc, (5 - 4) asc, p.created_at asc limit 1;
  if not found or b.wins = 0 then return jsonb_build_object('exists', false, 'my_wins', my_wins); end if;
  if b.id = uid then return jsonb_build_object('exists', true, 'is_me', true, 'my_wins', my_wins, 'name', b.username); end if;
  if my_wins < 20 then return jsonb_build_object('exists', true, 'is_me', false, 'my_wins', my_wins); end if;
  return jsonb_build_object('exists', true, 'is_me', false, 'my_wins', my_wins, 'name', b.username, 'phone', b.phone, 'wins', b.wins);
end $$;

------------------------------------------------------------------ JWÈT
create or replace function public.cleanup_stale() returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from public.games where status in ('waiting','failed') and created_at < now() - interval '30 minutes';
  delete from public.games where status = 'waiting' and seeking and last_seen < now() - interval '2 minutes';
  delete from public.games where status = 'finished' and last_seen < now() - interval '2 hours';
end $$;

create or replace function public.finish_game(p_game uuid, p_winner text, p_reason text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games;
begin
  if p_winner not in ('X','O') or p_reason not in ('win','forfeit','timeout') then raise exception 'Rezilta match la pa valab.'; end if;
  select * into g from public.games where id = p_game for update;
  if not found or g.status <> 'playing' then raise exception 'Match sa a pa an kou.'; end if;
  insert into public.match_history(game_id, p1_name, p2_name, p1_id, p2_id, winner_name, winner_mark, finish_reason, move_count, finished_at, is_friend_match, amount)
  values (g.id, g.p1_name, g.p2_name, g.p1_id, g.p2_id, case when p_winner='X' then g.p1_name else g.p2_name end, p_winner, p_reason,
          (select count(*)::int from public.moves where game_id = p_game), now(), g.is_friend_match, g.amount)
  on conflict (game_id) do nothing;
  update public.games set status='finished', winner=p_winner, finish_reason=p_reason, code=null, amount=null, seeking=false,
    expires_at=null, turn_started_at=null, p1_paid=false, p2_paid=false, mailed=false, last_seen=now() where id = p_game;
  delete from public.moves where game_id = p_game;
  delete from public.game_secrets where game_id = p_game;
  perform public.finish_tournament_match(p_game, p_winner);
end $$;

drop function if exists public.register_player(text);
drop function if exists public.enter_code(text, text, text);
drop function if exists public.seek_random(text, text, uuid);
drop function if exists public.play(uuid, text, int, int);
drop function if exists public.forfeit_game(uuid, text);
drop function if exists public.timeout_game(uuid, text);
drop function if exists public.cancel_search(uuid, text);

-- Zanmi: menm kòd. Lè 2 jwè konekte, kòd la efase. Si gen lajan, match la tann peman.
create or replace function public.enter_code(p_code text, p_amount text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); me public.profiles; g public.games;
  c text := upper(regexp_replace(trim(coalesce(p_code,'')), '[[:space:]]+', '', 'g'));
  raw_a text := coalesce(p_amount,'');
  a text;
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  select * into me from public.profiles where id = uid;
  if not found then raise exception 'Pwofil la pa jwenn.'; end if;
  if c = '' or char_length(c) > 12 then raise exception 'Kòd la dwe genyen ant 1 ak 12 karaktè.'; end if;
  if raw_a = '' then
    a := '';
  else
    if raw_a !~ '^[0-9]+$' then raise exception 'Kantite lajan an dwe gen chif sèlman.'; end if;
    if char_length(raw_a) > 7 then raise exception 'Kantite lajan an two gwo.'; end if;
    a := coalesce(nullif(ltrim(raw_a,'0'),''),'0');
    if a::numeric < 25 then raise exception 'Kantite minimòm lan se 25 Goud.'; end if;
  end if;
  perform public.cleanup_stale();
  perform pg_advisory_xact_lock(hashtext('code:' || c));

  if exists (select 1 from public.games where code = c and status = 'waiting' and p2_id is null and p1_id = uid) then
    raise exception 'Ou deja kreye yon match ak kòd sa a. Zanmi w dwe itilize yon lòt kont pou konekte.';
  end if;
  select * into g from public.games where code = c and status = 'waiting' and p2_id is null and p1_id <> uid order by created_at limit 1 for update;
  if found then
    if coalesce(g.amount,'') <> a then raise exception 'Kantite lajan an pa menm ak sa zanmi w la mete a.'; end if;
    if a = ''
      and exists (
        select 1 from unnest(array[uid, g.p1_id]) as participant(user_id)
        where (select count(*) from public.match_history h
          where h.is_friend_match and nullif(trim(h.amount),'') is null
            and (h.p1_id = participant.user_id or h.p2_id = participant.user_id)) >= 3
      )
      and not (
        exists (select 1 from public.match_history h
          where h.is_friend_match and nullif(trim(h.amount),'') is not null
            and (h.p1_id in (uid, g.p1_id) or h.p2_id in (uid, g.p1_id)))
        or exists (select 1 from public.games paid
          where paid.is_friend_match and nullif(trim(paid.amount),'') is not null
            and paid.status in ('pending_payment','playing')
            and ((paid.p1_id in (uid, g.p1_id) and paid.p1_paid)
              or (paid.p2_id in (uid, g.p1_id) and paid.p2_paid)))
        or exists (select 1 from public.tournament_entries e
          join public.tournaments t on t.id = e.tournament_id
          where e.user_id in (uid, g.p1_id) and e.status = 'paid' and t.fee > 0)
      )
    then
      raise exception 'Apre 3 match gratis, omwen youn nan de jwè yo dwe gen yon peman valide sou sit la pou kontinye jwe gratis ak zanmi.';
    end if;
    update public.games set p2_id = uid, p2_name = me.username, code = null, seeking = false, is_friend_match = true, last_seen = now(),
      status = case when g.amount is null then 'playing' else 'pending_payment' end,
      turn_started_at = case when g.amount is null then now() else null end
    where id = g.id returning * into g;
    return jsonb_build_object('game', to_jsonb(g), 'role', 'O');
  end if;

  delete from public.games where p1_id = uid and status = 'waiting';
  insert into public.games(code, p1_id, p1_name, amount, is_friend_match) values (c, uid, me.username, nullif(a,''), true) returning * into g;
  insert into public.game_secrets(game_id) values (g.id);
  return jsonb_build_object('game', to_jsonb(g), 'role', 'X');
end $$;

-- Etranje: sèlman moun ki ap chèche etranje kounye a (battement < 15 segonn).
create or replace function public.seek_random(p_game uuid default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); me public.profiles; g public.games; o public.games;
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  select * into me from public.profiles where id = uid;
  if not found then raise exception 'Pwofil la pa jwenn.'; end if;
  perform public.cleanup_stale();
  perform pg_advisory_xact_lock(hashtext('seek_random'));

  if p_game is not null then
    select * into g from public.games where id = p_game and p1_id = uid for update;
    if not found then raise exception 'Rechèch la pa egziste ankò.'; end if;
    if g.status <> 'waiting' then return jsonb_build_object('game', to_jsonb(g), 'role', 'X'); end if;
    update public.games set last_seen = now() where id = p_game returning * into g;
  end if;

  select * into o from public.games
  where status = 'waiting' and seeking and code is null and p2_id is null and p1_id <> uid
    and last_seen > now() - interval '15 seconds' and id is distinct from p_game
  order by created_at limit 1 for update skip locked;

  if found then
    update public.games set p2_id = uid, p2_name = me.username, status = 'playing', seeking = false, turn_started_at = now(), last_seen = now()
    where id = o.id returning * into o;
    delete from public.games where p1_id = uid and status = 'waiting';
    return jsonb_build_object('game', to_jsonb(o), 'role', 'O');
  end if;

  if p_game is null then
    delete from public.games where p1_id = uid and status = 'waiting';
    insert into public.games(p1_id, p1_name, seeking, expires_at) values (uid, me.username, true, now() + interval '3 minutes') returning * into g;
  end if;
  return jsonb_build_object('game', to_jsonb(g), 'role', 'X');
end $$;

create or replace function public.count_seekers() returns int language sql stable security definer set search_path = public, pg_temp
as $$ select count(*)::int from public.games where status='waiting' and seeking and code is null and p2_id is null
      and p1_id is distinct from auth.uid() and last_seen > now() - interval '15 seconds' $$;

-- Kite rechèch / match ki poko kòmanse (pa touche match ki gen peman deja voye)
create or replace function public.cancel_search(p_game uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; uid uuid := auth.uid();
begin
  select * into g from public.games where id = p_game for update;
  if not found or uid is null or (g.p1_id is distinct from uid and g.p2_id is distinct from uid) then return false; end if;
  if g.status = 'waiting' or (g.status = 'pending_payment' and not g.p1_paid and not g.p2_paid) then
    delete from public.games where id = p_game; return true;
  end if;
  return false;
end $$;

create or replace function public.my_active_game() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; uid uuid := auth.uid();
begin
  select * into g from public.games where status in ('playing','pending_payment') and (p1_id = uid or p2_id = uid) order by created_at desc limit 1;
  if not found then return null; end if;
  return jsonb_build_object('game', to_jsonb(g), 'role', case when g.p1_id = uid then 'X' else 'O' end);
end $$;

create or replace function public.play(p_game uuid, p_r int, p_c int) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; role text; dirs int[][] := array[[1,0],[0,1],[1,1],[1,-1]]; i int; n int; k int;
begin
  if auth.uid() is null then raise exception 'Ou dwe konekte.'; end if;
  if p_r not between -2000 and 2000 or p_c not between -2000 and 2000 then raise exception 'Kou a pa valab.'; end if;
  select * into g from public.games where id = p_game for update;
  if not found or g.status <> 'playing' then raise exception 'Match sa a pa an kou.'; end if;
  role := case when g.p1_id = auth.uid() then 'X' when g.p2_id = auth.uid() then 'O' end;
  if role is null then raise exception 'Ou pa nan match sa a.'; end if;
  if g.turn <> role then raise exception 'Se pa tou ou.'; end if;
  if exists (select 1 from public.moves where game_id = p_game and r = p_r and c = p_c) then raise exception 'Kazye sa a pran deja.'; end if;
  insert into public.moves(game_id, r, c, mark) values (p_game, p_r, p_c, role);
  for i in 1..4 loop
    n := 1; k := 1;
    while exists (select 1 from public.moves where game_id=p_game and mark=role and r = p_r + k*dirs[i][1] and c = p_c + k*dirs[i][2]) loop n := n+1; k := k+1; end loop;
    k := 1;
    while exists (select 1 from public.moves where game_id=p_game and mark=role and r = p_r - k*dirs[i][1] and c = p_c - k*dirs[i][2]) loop n := n+1; k := k+1; end loop;
    if n >= 5 then perform public.finish_game(p_game, role, 'win'); return; end if;
  end loop;
  update public.games set turn = case when role='X' then 'O' else 'X' end, turn_started_at = now() where id = p_game;
end $$;

create or replace function public.forfeit_game(p_game uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games; role text;
begin
  select * into g from public.games where id = p_game for update;
  if not found or g.status <> 'playing' then raise exception 'Match sa a pa an kou.'; end if;
  role := case when g.p1_id = auth.uid() then 'X' when g.p2_id = auth.uid() then 'O' end;
  if role is null then raise exception 'Ou pa nan match sa a.'; end if;
  perform public.finish_game(p_game, case when role='X' then 'O' else 'X' end, 'forfeit');
end $$;

create or replace function public.timeout_game(p_game uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare g public.games;
begin
  select * into g from public.games where id = p_game for update;
  if not found or g.status <> 'playing' then raise exception 'Match sa a pa an kou.'; end if;
  if auth.uid() is distinct from g.p1_id and auth.uid() is distinct from g.p2_id then raise exception 'Ou pa nan match sa a.'; end if;
  if g.turn_started_at is null or g.turn_started_at > now() - interval '60 seconds' then raise exception 'Tan pou jwe a poko fini.'; end if;
  perform public.finish_game(p_game, case when g.turn='X' then 'O' else 'X' end, 'timeout');
end $$;

-- Lè 2 peman yo valide, match la kòmanse (sa mache tou ak lyen imèl edge function lan)
create or replace function public.on_paid() returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if new.status = 'pending_payment' and new.p1_paid and new.p2_paid and new.p2_id is not null then
    new.status := 'playing'; new.turn_started_at := now(); new.code := null;
  end if;
  return new;
end $$;
drop trigger if exists t_paid on public.games;
create trigger t_paid before update of p1_paid, p2_paid on public.games for each row execute function public.on_paid();

-- Match ki te kole nan ansyen sistèm peman an
update public.games set status='playing', turn_started_at=coalesce(turn_started_at, now()) where status='pending_payment' and p2_name is not null and p1_id is null;

------------------------------------------------------------------ TOUNWA (jwè)
create or replace function public.list_tournaments() returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'name', t.name, 'start_text', t.start_text, 'max_players', t.max_players, 'fee', t.fee, 'payment_info', t.payment_info,
    'prize1', t.prize1, 'prize2', t.prize2, 'prize3', t.prize3, 'winner1', t.winner1, 'winner2', t.winner2, 'winner3', t.winner3,
    'note', t.note, 'status', t.status, 'created_at', t.created_at, 'started_at', t.started_at, 'finished_at', t.finished_at,
    'participants', (select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'uid', e.user_id, 'name', p.username, 'status', e.status,
      'payment_submitted_at', e.payment_submitted_at, 'paid_at', e.paid_at) order by e.created_at), '[]'::jsonb)
        from public.tournament_entries e join public.profiles p on p.id = e.user_id where e.tournament_id = t.id),
    'my_status', (select e.status from public.tournament_entries e where e.tournament_id = t.id and e.user_id = auth.uid())
  ) order by t.created_at desc), '[]'::jsonb) from public.tournaments t $$;

create or replace function public.join_tournament(p_tournament uuid) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare t public.tournaments; uid uuid := auth.uid(); st text;
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  select * into t from public.tournaments where id = p_tournament for update;
  if not found or t.status <> 'open' then raise exception 'Tounwa sa a pa disponib ankò.'; end if;
  if exists (select 1 from public.tournament_entries where tournament_id = p_tournament and user_id = uid) then raise exception 'Ou deja nan tounwa sa a.'; end if;
  if (select count(*) from public.tournament_entries where tournament_id = p_tournament) >= t.max_players then raise exception 'Tounwa a plen.'; end if;
  st := case when t.fee = 0 then 'paid' else 'pending' end;
  insert into public.tournament_entries(tournament_id, user_id, status) values (p_tournament, uid, st);
  return st;
end $$;

create or replace function public.leave_tournament(p_tournament uuid) returns void language sql security definer set search_path = public, pg_temp
as $$ delete from public.tournament_entries where tournament_id = p_tournament and user_id = auth.uid() and status = 'pending' $$;

create or replace function public.list_tournament_matches(p_tournament uuid default null) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', m.id, 'tournament_id', m.tournament_id, 'round_name', m.round_name, 'position', m.position,
    'p1_id', m.p1_id, 'p2_id', m.p2_id, 'p1_name', m.p1_name, 'p2_name', m.p2_name,
    'p1_ready', m.p1_ready, 'p2_ready', m.p2_ready, 'status', m.status, 'game_id', m.game_id,
    'winner_id', m.winner_id, 'winner_name', m.winner_name, 'started_at', m.started_at,
    'finished_at', m.finished_at
  ) order by m.created_at, m.position), '[]'::jsonb)
  from public.tournament_matches m
  where (p_tournament is null or m.tournament_id = p_tournament)
    and (p_tournament is not null or auth.uid() is not null);
$$;

create or replace function public.admin_set_tournament_match(p_match uuid, p_p1 uuid, p_p2 uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.tournament_matches;
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  select * into m from public.tournament_matches where id = p_match for update;
  if not found then raise exception 'Match tounwa a pa jwenn.'; end if;
  if m.status <> 'waiting' then raise exception 'Match sa a pa ka modifye ankò.'; end if;
  if p_p1 is not null and not exists (
    select 1 from public.tournament_entries
    where tournament_id = m.tournament_id and user_id = p_p1 and status = 'paid'
  ) then raise exception 'Pwpremye jwè a pa valab.'; end if;
  if p_p2 is not null and not exists (
    select 1 from public.tournament_entries
    where tournament_id = m.tournament_id and user_id = p_p2 and status = 'paid'
  ) then raise exception 'Dezyem jwè a pa valab.'; end if;
  if p_p1 is not null and p_p1 = p_p2 then raise exception 'De jwè yo dwe diferan.'; end if;
  update public.tournament_matches set
    p1_id = p_p1,
    p2_id = p_p2,
    p1_name = (select username from public.profiles where id = p_p1),
    p2_name = (select username from public.profiles where id = p_p2),
    p1_ready = false,
    p2_ready = false
  where id = p_match;
end $$;

create or replace function public.ready_tournament_match(p_match uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); m public.tournament_matches; g public.games;
begin
  if uid is null then raise exception 'Ou dwe konekte.'; end if;
  select * into m from public.tournament_matches where id = p_match for update;
  if not found then raise exception 'Match tounwa a pa jwenn.'; end if;
  if m.status <> 'waiting' then raise exception 'Match sa a pa ap tann jwè ankò.'; end if;
  if uid <> m.p1_id and uid <> m.p2_id then raise exception 'Ou pa fè pati match sa a.'; end if;

  if uid = m.p1_id then
    update public.tournament_matches set p1_ready = true where id = p_match;
  else
    update public.tournament_matches set p2_ready = true where id = p_match;
  end if;
  select * into m from public.tournament_matches where id = p_match;

  if m.p1_ready and m.p2_ready and m.p1_id is not null and m.p2_id is not null then
    insert into public.games(p1_name, p1_id, p2_name, p2_id, status, turn, turn_started_at, is_friend_match, last_seen)
      values (m.p1_name, m.p1_id, m.p2_name, m.p2_id, 'playing', 'X', now(), false, now())
      returning * into g;
    update public.tournament_matches
      set status = 'playing', game_id = g.id, started_at = now()
      where id = p_match;
  end if;
  return public.list_tournament_matches(m.tournament_id);
end $$;

create or replace function public.finish_tournament_match(p_game uuid, p_winner text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.tournament_matches; g public.games;
begin
  select * into m from public.tournament_matches where game_id = p_game for update;
  if not found then return; end if;
  select * into g from public.games where id = p_game;
  update public.tournament_matches set
    status = 'finished',
    winner_id = case when p_winner = 'X' then m.p1_id else m.p2_id end,
    winner_name = case when p_winner = 'X' then m.p1_name else m.p2_name end,
    finished_at = now()
  where id = m.id
  returning * into m;

  if m.next_match_id is not null then
    if m.next_slot = 1 then
      update public.tournament_matches
        set p1_id = m.winner_id, p1_name = m.winner_name,
            p1_ready = false
        where id = m.next_match_id;
    else
      update public.tournament_matches
        set p2_id = m.winner_id, p2_name = m.winner_name,
            p2_ready = false
        where id = m.next_match_id;
    end if;
  else
    update public.tournaments set status = 'finished', finished_at = now()
      where id = m.tournament_id;
    update public.tournaments set winner1 = m.winner_id
      where id = m.tournament_id;
  end if;
end $$;

create or replace function public.admin_start_tournament(p_tournament uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  t public.tournaments;
  paid_count int;
  round_no int;
  first_round_size int;
  next_round_size int;
  current_round text;
  next_round text;
  i int;
  j int;
  match_id uuid;
  next_match_id uuid;
  participant record;
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  select * into t from public.tournaments where id = p_tournament for update;
  if not found then raise exception 'Tounwa a pa jwenn.'; end if;
  if t.status = 'finished' then raise exception 'Tounwa a fini deja.'; end if;

  select count(*) into paid_count from public.tournament_entries
    where tournament_id = p_tournament and status = 'paid';
  if paid_count < 2 then raise exception 'Tounwa a bezwen omwen 2 jwè ki gen peman valide.'; end if;

  delete from public.tournament_matches where tournament_id = p_tournament;
  update public.tournaments set status = 'open', started_at = now(), finished_at = null where id = p_tournament;

  if paid_count <= 2 then first_round_size := 1;
  elsif paid_count <= 4 then first_round_size := 2;
  elsif paid_count <= 8 then first_round_size := 4;
  elsif paid_count <= 16 then first_round_size := 8;
  elsif paid_count <= 32 then first_round_size := 16;
  elsif paid_count <= 64 then first_round_size := 32;
  elsif paid_count <= 128 then first_round_size := 64;
  else first_round_size := 128;
  end if;

  current_round := case
    when first_round_size = 1 then 'Final'
    when first_round_size = 2 then 'Semi-final'
    else 'Etap 1'
  end;
  for i in 1..first_round_size loop
    insert into public.tournament_matches(tournament_id, round_name, position)
      values (p_tournament, current_round, i) returning id into match_id;
  end loop;

  for i in 1..paid_count loop
    select p.id, p.username into participant
      from public.tournament_entries e join public.profiles p on p.id = e.user_id
      where e.tournament_id = p_tournament and e.status = 'paid'
      order by e.created_at, e.id
      offset i - 1 limit 1;
    if found then
      if i <= first_round_size * 2 then
        if i % 2 = 1 then
          update public.tournament_matches
            set p1_id = participant.id, p1_name = participant.username
            where tournament_id = p_tournament and round_name = current_round
              and position = ((i + 1) / 2);
        else
          update public.tournament_matches
            set p2_id = participant.id, p2_name = participant.username
            where tournament_id = p_tournament and round_name = current_round
              and position = (i / 2);
        end if;
      end if;
    end if;
  end loop;

  next_round_size := first_round_size / 2;
  round_no := 2;
  while next_round_size >= 1 loop
    next_round := case
      when next_round_size = 1 then 'Final'
      when next_round_size = 2 then 'Semi-final'
      else 'Etap ' || round_no
    end;
    for i in 1..next_round_size loop
      insert into public.tournament_matches(tournament_id, round_name, position)
        values (p_tournament, next_round, i) returning id into next_match_id;
      select id into match_id from public.tournament_matches
        where tournament_id = p_tournament and round_name = current_round
          and position = i * 2 - 1;
      update public.tournament_matches set next_match_id = next_match_id, next_slot = 1 where id = match_id;
      select id into match_id from public.tournament_matches
        where tournament_id = p_tournament and round_name = current_round
          and position = i * 2;
      update public.tournament_matches set next_match_id = next_match_id, next_slot = 2 where id = match_id;
    end loop;
    current_round := next_round;
    round_no := round_no + 1;
    next_round_size := next_round_size / 2;
  end loop;

  update public.tournaments set status = 'open', started_at = now() where id = p_tournament;
  return jsonb_build_object('started', true, 'matches', paid_count);
end $$;

------------------------------------------------------------------ ADMIN
create or replace function public.admin_overview() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare tz text := 'America/Port-au-Prince';
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  return jsonb_build_object(
    'players', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'email', p.email, 'phone', p.phone, 'provider', p.provider,
        'is_admin', p.is_admin, 'created_at', p.created_at,
        'wins', (select count(*) from public.match_history h where (h.winner_mark='X' and h.p1_id=p.id) or (h.winner_mark='O' and h.p2_id=p.id)),
        'matches', (select count(*) from public.match_history h where h.p1_id=p.id or h.p2_id=p.id)) order by p.username), '[]'::jsonb) from public.profiles p),
    'pending_games', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'p1_name', g.p1_name, 'p2_name', g.p2_name, 'amount', g.amount,
        'p1_paid', g.p1_paid, 'p2_paid', g.p2_paid, 'created_at', g.created_at) order by g.created_at), '[]'::jsonb)
        from public.games g where g.status = 'pending_payment'),
    'pending_entries', (select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'name', p.username, 'tournament', t.name, 'fee', t.fee,
        'payment_submitted_at', e.payment_submitted_at, 'paid_at', e.paid_at, 'validated_at', e.paid_at) order by e.created_at), '[]'::jsonb)
        from public.tournament_entries e join public.profiles p on p.id = e.user_id join public.tournaments t on t.id = e.tournament_id where e.status = 'pending'),
    'live_games', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'p1_name', g.p1_name, 'p2_name', g.p2_name, 'amount', g.amount, 'created_at', g.created_at,
        'moves', (select count(*) from public.moves m where m.game_id = g.id)) order by g.created_at desc), '[]'::jsonb)
        from public.games g where g.status = 'playing'),
    'history', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select jsonb_build_object('id', h.id, 'p1_name', h.p1_name, 'p2_name', h.p2_name, 'winner_name', h.winner_name, 'reason', h.finish_reason,
          'moves', h.move_count, 'finished_at', h.finished_at, 'today', ((h.finished_at at time zone tz)::date = (now() at time zone tz)::date)) x
        from public.match_history h order by h.finished_at desc limit 300) s));
end $$;

create or replace function public.admin_set_paid(p_game uuid, p_slot int, p_paid boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  if p_slot = 1 then update public.games set p1_paid = p_paid where id = p_game and status = 'pending_payment';
  elsif p_slot = 2 then update public.games set p2_paid = p_paid where id = p_game and status = 'pending_payment';
  else raise exception 'Jwè a pa valab.'; end if;
end $$;

create or replace function public.admin_reject_game(p_game uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  delete from public.games where id = p_game and status in ('pending_payment','waiting');
end $$;

create or replace function public.admin_validate_entry(p_entry bigint, p_ok boolean) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  if p_ok then update public.tournament_entries set status = 'paid', paid_at = now(), validated_by = auth.uid() where id = p_entry;
  else delete from public.tournament_entries where id = p_entry; end if;
end $$;

create or replace function public.admin_save_tournament(p jsonb) returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare tid uuid := nullif(p->>'id','')::uuid;
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  if trim(coalesce(p->>'name','')) = '' then raise exception 'Non tounwa a obligatwa.'; end if;
  if tid is null then
    insert into public.tournaments(name, start_text, max_players, fee, payment_info, prize1, prize2, prize3, note)
    values (trim(p->>'name'), nullif(trim(coalesce(p->>'start_text','')),''), coalesce((p->>'max_players')::int, 8), coalesce((p->>'fee')::int, 0),
      nullif(trim(coalesce(p->>'payment_info','')),''), nullif(trim(coalesce(p->>'prize1','')),''), nullif(trim(coalesce(p->>'prize2','')),''),
      nullif(trim(coalesce(p->>'prize3','')),''), nullif(trim(coalesce(p->>'note','')),'')) returning id into tid;
  else
    update public.tournaments set name = trim(p->>'name'), start_text = nullif(trim(coalesce(p->>'start_text','')),''),
      max_players = coalesce((p->>'max_players')::int, max_players), fee = coalesce((p->>'fee')::int, fee),
      payment_info = nullif(trim(coalesce(p->>'payment_info','')),''), prize1 = nullif(trim(coalesce(p->>'prize1','')),''),
      prize2 = nullif(trim(coalesce(p->>'prize2','')),''), prize3 = nullif(trim(coalesce(p->>'prize3','')),''), note = nullif(trim(coalesce(p->>'note','')),''),
      winner1 = nullif(p->>'winner1','')::uuid, winner2 = nullif(p->>'winner2','')::uuid, winner3 = nullif(p->>'winner3','')::uuid,
      status = coalesce(nullif(p->>'status',''), status)
    where id = tid;
  end if;
  return tid;
end $$;

create or replace function public.admin_delete_tournament(p_id uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  delete from public.tournaments where id = p_id;
end $$;

create or replace function public.admin_send_message(p_user uuid, p_body text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare body_text text := trim(coalesce(p_body,''));
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  if char_length(body_text) not between 1 and 500 then raise exception 'Mesaj la dwe genyen ant 1 ak 500 karaktè.'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'Kont jwè a pa jwenn.'; end if;
  insert into public.admin_messages(user_id, body, from_admin) values (p_user, body_text, true);
end $$;

create or replace function public.admin_message_inbox() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', p.id, 'username', p.username, 'email', p.email, 'last_body', latest.body,
      'last_at', latest.created_at,
      'unread', (select count(*)::int from public.admin_messages unread
        where unread.user_id = p.id and not unread.from_admin and not unread.read)
    ) order by latest.created_at desc), '[]'::jsonb)
    from public.profiles p
    join lateral (
      select m.body, m.created_at from public.admin_messages m
      where m.user_id = p.id order by m.created_at desc, m.id desc limit 1
    ) latest on true);
end $$;

create or replace function public.admin_message_thread(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'Kont jwè a pa jwenn.'; end if;
  update public.admin_messages set read = true where user_id = p_user and not from_admin and not read;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'body', m.body, 'from_admin', m.from_admin,
      'read', m.read, 'created_at', m.created_at) order by m.created_at, m.id), '[]'::jsonb)
    from (select id, body, from_admin, read, created_at from public.admin_messages
      where user_id = p_user order by created_at desc, id desc limit 200) m);
end $$;

create or replace function public.admin_delete_player(p_user uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  if p_user = auth.uid() then raise exception 'Ou pa ka efase pwòp kont ou.'; end if;
  delete from public.games where (p1_id = p_user or p2_id = p_user) and status <> 'finished';
  delete from auth.users where id = p_user;
end $$;

create or replace function public.admin_delete_history(p_ids bigint[]) returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  delete from public.games where status = 'finished'
    and id in (select game_id from public.match_history where id = any(p_ids));
  delete from public.match_history where id = any(p_ids);
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.admin_clear_history(p_before timestamptz default null) returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  delete from public.games g where g.status = 'finished'
    and (p_before is null or g.last_seen < p_before
      or exists (select 1 from public.match_history h where h.game_id = g.id and h.finished_at < p_before));
  delete from public.match_history where p_before is null or finished_at < p_before;
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.admin_set_setting(p_key text, p_value text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  if p_key not in ('rules','natcash','push_vapid_public_key') then raise exception 'Paramèt sa a pa valab.'; end if;
  insert into public.app_settings(key, value, updated_at) values (p_key, coalesce(p_value,''), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;

create or replace function public.admin_update_welcome_message(p_body text, p_send_existing boolean) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare body_text text := trim(coalesce(p_body,'')); sent_count int := 0;
begin
  if not public.is_admin() then raise exception 'Aksè refize.'; end if;
  if char_length(body_text) not between 1 and 500 then raise exception 'Mesaj la dwe genyen ant 1 ak 500 karaktè.'; end if;
  insert into public.app_settings(key, value, updated_at)
    values ('welcome_message', body_text, now())
    on conflict (key) do update set value = excluded.value, updated_at = now();
  if coalesce(p_send_existing, false) then
    insert into public.admin_messages(user_id, body, from_admin)
      select id, body_text, true from public.profiles where not is_admin;
    get diagnostics sent_count = row_count;
  end if;
  return sent_count;
end $$;

create or replace function public.admin_reset_database() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid();
  deleted_profiles int;
  deleted_users int;
  deleted_matches int;
  deleted_games int;
  deleted_tournaments int;
  push_public_key text;
begin
  if uid is null or not public.is_admin() then raise exception 'Aksè refize.'; end if;

  lock table auth.users, public.profiles, public.app_settings, public.tournaments, public.tournament_entries, public.tournament_matches,
    public.admin_messages, public.player_chat_messages, public.push_subscriptions,
    public.games, public.moves, public.game_secrets, public.match_history, public.players
    in access exclusive mode;

  delete from public.match_history;
  get diagnostics deleted_matches = row_count;
  delete from public.games;
  get diagnostics deleted_games = row_count;
  delete from public.tournament_entries;
  delete from public.tournament_matches;
  delete from public.tournaments;
  get diagnostics deleted_tournaments = row_count;
  delete from public.admin_messages;
  delete from public.player_chat_messages;
  delete from public.players;
  delete from public.profiles where id <> uid;
  get diagnostics deleted_profiles = row_count;
  delete from auth.users where id <> uid;
  get diagnostics deleted_users = row_count;
  update public.profiles set is_admin = true where id = uid;

  select value into push_public_key from public.app_settings where key = 'push_vapid_public_key';
  delete from public.app_settings;
  insert into public.app_settings(key, value) values
    ('rules', E'Morp.io se yon jwèt 5 nan yon liy sou yon tablo ki pa gen limit.\n\n1. X kòmanse premye, answit chak jwè jwe yon sèl fwa chak tou.\n2. Premye jwè ki aliyen 5 mòpyon (orizontal, vètikal oswa dyagonal) genyen.\n3. Ou gen 60 segonn pou chak kou. Si w depase tan an, w pèdi.\n4. Si w kite match la, se yon forfè epi advèsè w la genyen.\n5. Match ak lajan an kòmanse sèlman lè administratè a valide de peman yo.'),
    ('welcome_message', 'Byenveni nan Morp.io HT! Objektif la se mete 5 mak youn apre lòt pou genyen. X kòmanse, epi chak jwè gen 60 segonn pou jwe. Ou ka jwe ak òdinatè, chèche yon etranje, oswa antre kòd yon zanmi. Pou yon match ak lajan, tou de jwè yo dwe voye menm kantite lajan an epi tann administratè a konfime peman yo. Ou ka reponn mesaj sa a si w bezwen èd.'),
    ('push_vapid_public_key', coalesce(push_public_key,'')),
    ('natcash', '+509 55 67 9002');

  alter sequence public.moves_id_seq restart with 1;
  alter sequence public.match_history_id_seq restart with 1;
  alter sequence public.admin_messages_id_seq restart with 1;
  alter sequence public.player_chat_messages_id_seq restart with 1;
  alter sequence public.tournament_entries_id_seq restart with 1;

  return jsonb_build_object('profiles_deleted', deleted_profiles, 'users_deleted', deleted_users,
    'matches_deleted', deleted_matches, 'games_deleted', deleted_games, 'tournaments_deleted', deleted_tournaments);
end $$;

------------------------------------------------------------------ STATISTIK PIBLIK
-- Chak jwè parèt yon sèl fwa (gwoupe pa non an majiskil).
create or replace view public.player_stats as
with names as (
  select upper(username) as k, username as name from public.profiles
  union select upper(p1_name), p1_name from public.match_history
  union select upper(p2_name), p2_name from public.match_history
), uniq as (select k, min(name) as name from names group by k),
played as (
  select upper(p1_name) as k, (winner_mark = 'X') as won from public.match_history
  union all select upper(p2_name), (winner_mark = 'O') from public.match_history
), active as (
  select upper(p1_name) as k from public.games where status = 'playing'
  union all select upper(p2_name) from public.games where status = 'playing' and p2_name is not null
)
select u.name,
  (select count(*) from played p where p.k = u.k)::int as matches,
  (select count(*) from played p where p.k = u.k and p.won)::int as wins,
  (select count(*) from active a where a.k = u.k)::int as active,
  exists (select 1 from public.profiles p where upper(p.username) = u.k and nullif(trim(p.email),'') is not null) as registered
from uniq u;
grant select on public.player_stats to anon, authenticated;

------------------------------------------------------------------ PÈMISYON FONKSYON
do $$
declare f text;
begin
  foreach f in array array[
    'is_admin()','unique_username(text,uuid)','create_profile_for(uuid)','handle_new_user()','update_my_profile(text,text)','my_overview()','mark_messages_read()',
    'my_message_thread()','send_user_message(text)',
    'get_player_chat_messages(bigint)','send_player_chat_message(text)',
    'get_push_vapid_public_key()','save_push_subscription(jsonb)','remove_push_subscription(text)',
    'best_player()','cleanup_stale()','finish_game(uuid,text,text)','enter_code(text,text)','seek_random(uuid)','count_seekers()','cancel_search(uuid)',
    'my_active_game()','play(uuid,int,int)','forfeit_game(uuid)','timeout_game(uuid)','on_paid()','list_tournaments()','join_tournament(uuid)','leave_tournament(uuid)',
    'list_tournament_matches(uuid)','admin_start_tournament(uuid)','admin_set_tournament_match(uuid,uuid,uuid)','ready_tournament_match(uuid)','finish_tournament_match(uuid,text)',
    'admin_overview()','admin_set_paid(uuid,int,boolean)','admin_reject_game(uuid)','admin_validate_entry(bigint,boolean)','admin_save_tournament(jsonb)',
    'admin_delete_tournament(uuid)','admin_send_message(uuid,text)','admin_message_inbox()','admin_message_thread(uuid)',
    'admin_delete_player(uuid)','admin_delete_history(bigint[])','admin_clear_history(timestamptz)',
    'admin_set_setting(text,text)','admin_update_welcome_message(text,boolean)','admin_reset_database()']
  loop execute format('revoke all on function public.%s from public, anon, authenticated', f); end loop;
  foreach f in array array[
    'is_admin()','update_my_profile(text,text)','my_overview()','mark_messages_read()','my_message_thread()','send_user_message(text)',
    'get_player_chat_messages(bigint)','send_player_chat_message(text)',
    'get_push_vapid_public_key()','save_push_subscription(jsonb)','remove_push_subscription(text)',
    'best_player()','enter_code(text,text)','seek_random(uuid)','count_seekers()',
    'cancel_search(uuid)','my_active_game()','play(uuid,int,int)','forfeit_game(uuid)','timeout_game(uuid)','list_tournaments()','join_tournament(uuid)',
    'leave_tournament(uuid)','list_tournament_matches(uuid)','admin_start_tournament(uuid)','admin_set_tournament_match(uuid,uuid,uuid)','ready_tournament_match(uuid)',
    'admin_overview()','admin_set_paid(uuid,int,boolean)','admin_reject_game(uuid)','admin_validate_entry(bigint,boolean)',
    'admin_save_tournament(jsonb)','admin_delete_tournament(uuid)','admin_send_message(uuid,text)','admin_message_inbox()','admin_message_thread(uuid)',
    'admin_delete_player(uuid)','admin_delete_history(bigint[])',
    'admin_clear_history(timestamptz)','admin_set_setting(text,text)','admin_update_welcome_message(text,boolean)','admin_reset_database()']
  loop execute format('grant execute on function public.%s to authenticated', f); end loop;
  grant execute on function public.list_tournaments() to anon;
end $$;

notify pgrst, 'reload schema';

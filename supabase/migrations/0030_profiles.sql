-- ============================================================================
--  م88 — جدول profiles: سجلُّ مستخدمٍ يُملأ تلقائياً عند كل دخول
-- ============================================================================
--
--  الغرض
--  ─────
--  عند تسجيل الدخول (بـGoogle أو بالبريد)، يُنشأ/يُحدَّث صفٌّ في `profiles`
--  يحمل الاسم والبريد والصورة — بلا تدخّل من العميل. مصدرُ البيانات هو
--  `auth.users.raw_user_meta_data` الذي يملؤه مزوّد OAuth (Google يضع
--  `full_name`/`name` و`avatar_url`/`picture`).
--
--  لماذا تريغر لا كتابةٌ من العميل
--  ────────────────────────────────
--  التريغر `SECURITY DEFINER` يضمن إنشاء الصف **ذرّياً مع إنشاء المستخدم**،
--  فلا سباقَ ولا صفٌّ ناقص لو انقطع العميل بعد الدخول مباشرةً. وهو المصدر
--  الوحيد للكتابة عند الإنشاء، فلا يُزوِّر عميلٌ بيانات ملفٍّ ليس له.
--
--  الأمان: مالكُ الصف هو `auth.uid()` — نفس نمط `sync_rows` حرفياً
--  (‏`user_id = (select auth.uid())`), فلا يقرأ أحدٌ ملفَّ غيره ولا يعدّله.
--  وربطُ الحساب (Google فوق بريدٍ قائم) لا يُنشئ صفاً مكرراً لأن `id` هو
--  مفتاحُ `auth.users` نفسه: هويةٌ واحدة ⇒ صفُّ profile واحد.

-- ── الجدول ─────────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  full_name  text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'م88 — سجلّ المستخدم (اسم/بريد/صورة) يُملأ تلقائياً من auth.users عبر تريغر.';

alter table public.profiles enable row level security;

-- ── RLS: المالك auth.uid() — نظير sync_rows حرفياً ──────────────────────────
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select using (id = (select auth.uid()));

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert with check (id = (select auth.uid()));
-- لا سياسة حذف: الملف يُحذف تعاقبياً مع المستخدم فقط (on delete cascade).

-- ── دالة الملء: تقرأ الاسم والصورة من بيانات المزوّد بأسمائها المتعددة ──────
create or replace function public.sync_profile_from_auth()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  insert into public.profiles (id, email, full_name, avatar_url, updated_at)
  values (
    new.id,
    new.email,
    -- Google: full_name؛ ومزوّدون آخرون: name. وإلا جزءُ البريد قبل @.
    coalesce(nullif(m->>'full_name', ''), nullif(m->>'name', ''),
             split_part(coalesce(new.email, ''), '@', 1)),
    -- Google: avatar_url؛ وبعضهم: picture.
    coalesce(nullif(m->>'avatar_url', ''), nullif(m->>'picture', '')),
    now()
  )
  on conflict (id) do update set
    email      = excluded.email,
    -- لا نطمس اسماً/صورةً موجودَين بقيمةٍ فارغة قادمة من مزوّدٍ لا يوفّرهما.
    full_name  = coalesce(excluded.full_name,  public.profiles.full_name),
    avatar_url = coalesce(excluded.avatar_url, public.profiles.avatar_url),
    updated_at = now();
  return new;
end;
$function$;

-- ── التريغر: عند إنشاء المستخدم وعند تحديث بياناته (ربط حساب/تحديث صورة) ─────
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.sync_profile_from_auth();

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated
  after update of raw_user_meta_data, email on auth.users
  for each row execute function public.sync_profile_from_auth();

-- ── ملءُ الحسابات القائمة مرّةً واحدة (المستخدمان الاختباريان الحاليان) ──────
insert into public.profiles (id, email, full_name, avatar_url, updated_at)
select u.id, u.email,
       coalesce(nullif(u.raw_user_meta_data->>'full_name', ''),
                nullif(u.raw_user_meta_data->>'name', ''),
                split_part(coalesce(u.email, ''), '@', 1)),
       coalesce(nullif(u.raw_user_meta_data->>'avatar_url', ''),
                nullif(u.raw_user_meta_data->>'picture', '')),
       now()
from auth.users u
on conflict (id) do nothing;

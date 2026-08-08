-- ============================================================================
-- 0064 — الإشعارات داخل التطبيق (المرحلة هـ) — بلا Firebase/FCM إطلاقاً
-- ============================================================================
--
--  إشعاراتٌ سحابيةٌ خالصة تُقرأ من داخل التطبيق واللوحة عبر RPC فقط — لا خدمة
--  دفعٍ خارجية، لا رمز جهاز، لا اعتماد على Firebase. جدول notifications
--  المعتمد (من هجرات 0032–0048) موجودٌ أصلاً؛ هنا نضيف عمود data للحمولة
--  الغنية (صورة/زر/رابط) ونبني خمس دوالٍ بعقيدة النظام كاملةً:
--  SECURITY DEFINER + search_path فارغ + أسماء مؤهَّلة بالكامل + منح صريحة.
--
--  التقسيم:
--    • قراءة المستخدم لغير المقروء (get_my_notifications) وتعليمه مقروءاً
--      (mark_notification_read) — ذاتيّة بحتة عبر auth.uid()، لا كشف لغيره.
--    • إرسال المشرف الموجَّه (admin_send_notification — تُستبدل بإضافة معامل
--      data الخامس الافتراضي فيبقى نداء الأربعة معاملات صالحاً) والبثّ للجميع
--      (admin_broadcast_notification) — محروسان بـ_admin_guard ويُدقَّقان.
--    • إعداد «تحديث التطبيق» (app_update) في app_private.config يُقرأ للمستخدم
--      عبر get_app_update (SECURITY DEFINER كي يقرأ المخطط الخاص).
--
--  ملاحظة توافق: توقيع الخمسة معاملات مغايرٌ لتوقيع الأربعة عند Postgres، لذا
--  نُسقِط نسخة الأربعة صراحةً قبل الإنشاء كي يحسم النداء القديم إلى الجديدة
--  عبر القيمة الافتراضية بلا لبسٍ في التحميل الزائد (overload).
-- ============================================================================

-- ── ١) عمود الحمولة الغنية: {image_url?, action_label?, action_url?} ─────────
alter table public.notifications
  add column if not exists data jsonb not null default '{}'::jsonb;

-- ── ٢) إشعارات المستخدم غير المقروءة (ذاتيّة، قراءة بحتة) ────────────────────
create or replace function public.get_my_notifications()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id',         n.id,
        'title',      n.title,
        'body',       n.body,
        'kind',       n.kind,
        'data',       n.data,
        'created_at', n.created_at
      ) order by n.created_at asc)
    from (
      select id, title, body, kind, data, created_at
        from public.notifications
       where user_id = v_uid
         and read = false
       order by created_at asc
       limit 20
    ) n
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_my_notifications() from public, anon;
grant execute on function public.get_my_notifications() to authenticated;

-- ── ٣) تعليم إشعارٍ مقروءاً (ذاتيّ فقط؛ لا شيء إن لم يكن المالك) ─────────────
create or replace function public.mark_notification_read(p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  update public.notifications
     set read = true
   where id = p_id
     and user_id = (select auth.uid());
end;
$$;

revoke all on function public.mark_notification_read(uuid) from public, anon;
grant execute on function public.mark_notification_read(uuid) to authenticated;

-- ── ٤) إرسال المشرف الموجَّه (تستبدل نسخة الأربعة معاملات بإضافة data) ───────
--  نُسقِط توقيع الأربعة صراحةً أولاً حتى لا يبقى تحميلٌ زائدٌ ملتبس، فيحسم
--  كل نداءٍ قديمٍ (أربعة وسائط) إلى هذه عبر القيمة الافتراضية لـp_data.
drop function if exists public.admin_send_notification(uuid, text, text, text);

create or replace function public.admin_send_notification(
  p_user  uuid,
  p_title text,
  p_body  text,
  p_kind  text,
  p_data  jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email text := public._admin_guard();
begin
  insert into public.notifications (user_id, title, body, kind, data)
  values (p_user, p_title, p_body, p_kind, coalesce(p_data, '{}'::jsonb));

  -- admin_audit جدولٌ إلحاقيّ (لا دالة) — نُدرج فيه كبقية الدوال المعتمدة.
  insert into public.admin_audit
    (actor, actor_email, action, target_user, target_email, detail)
  values ((select auth.uid()), v_email, 'send_notification', p_user, null,
          jsonb_build_object('title', p_title, 'kind', p_kind));
end;
$$;

revoke all on function public.admin_send_notification(uuid, text, text, text, jsonb)
  from public, anon;
grant execute on function public.admin_send_notification(uuid, text, text, text, jsonb)
  to authenticated;

-- ── ٥) بثّ المشرف للجميع (صفٌّ لكل مستخدمٍ في auth.users؛ يعيد العدد) ────────
create or replace function public.admin_broadcast_notification(
  p_title text,
  p_body  text,
  p_kind  text,
  p_data  jsonb default '{}'::jsonb
)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email text := public._admin_guard();
  v_count integer;
begin
  insert into public.notifications (user_id, title, body, kind, data)
  select u.id, p_title, p_body, p_kind, coalesce(p_data, '{}'::jsonb)
    from auth.users u;

  get diagnostics v_count = row_count;

  insert into public.admin_audit
    (actor, actor_email, action, target_user, target_email, detail)
  values ((select auth.uid()), v_email, 'broadcast_notification', null, null,
          jsonb_build_object('title', p_title, 'kind', p_kind, 'count', v_count));

  return v_count;
end;
$$;

revoke all on function public.admin_broadcast_notification(text, text, text, jsonb)
  from public, anon;
grant execute on function public.admin_broadcast_notification(text, text, text, jsonb)
  to authenticated;

-- ── ٦) بذر إعداد «تحديث التطبيق» (لا يُلمس إن وُجد مسبقاً) ────────────────────
insert into app_private.config (key, value)
values ('app_update', jsonb_build_object(
          'enabled', false,
          'version', '',
          'url',     '',
          'notes',   ''))
on conflict (key) do nothing;

-- ── ٧) قراءة إعداد «تحديث التطبيق» للمستخدم (DEFINER كي يقرأ المخطط الخاص) ───
create or replace function public.get_app_update()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_val jsonb;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select value into v_val
    from app_private.config
   where key = 'app_update';

  return coalesce(v_val, jsonb_build_object(
    'enabled', false,
    'version', '',
    'url',     '',
    'notes',   ''));
end;
$$;

revoke all on function public.get_app_update() from public, anon;
grant execute on function public.get_app_update() to authenticated;

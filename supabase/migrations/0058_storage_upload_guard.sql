-- 0058 — حارس رفع الصور على الخادم (المرحلة أ). دفاعٌ ضد عميلٍ معدَّل:
-- حتى لو تجاوز التطبيق فحصَه المحلي، لا يقبل Cloudflare Worker الرفع إلا
-- بعد أن تؤكّد هذه الدالة أن (الاستهلاك + البايتات الجديدة) ضمن الحصة.
--
-- سلامة الإنتاج الحيّ (قرار المالك): الحجب الفعلي خلف مفتاحٍ فرعي مستقل
-- gate.enforce_storage يبدأ **مطفأً** — فلا يُحجب أحدٌ جديد ما لم يُفعَّل
-- صراحةً، رغم أن الإجبار العام مفعّل. حين يكون مطفأً وكانت المحاولة ستتجاوز
-- الحصة، نسجّل «قياساً» (مرة/ساعة/مستخدم) في admin_audit كي يرى المالك مَن
-- سيتأثّر قبل أن يقرّر التفعيل.

-- المفتاح الفرعي الافتراضي: مطفأ. (لا نلمس gate.enforce العام.)
insert into app_private.config (key, value)
values ('gate', jsonb_build_object('enforce_storage', false))
on conflict (key) do update
  set value = app_private.config.value
    || jsonb_build_object(
         'enforce_storage',
         coalesce(app_private.config.value->'enforce_storage', 'false'::jsonb));

create or replace function public.storage_can_upload(p_add_bytes bigint)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid        uuid := (select auth.uid());
  v_add        bigint := greatest(coalesce(p_add_bytes, 0), 0);
  v_used       bigint;
  v_quota      bigint;
  v_enforced   boolean;
  v_would      boolean;
  v_email      text;
  v_recent     boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select coalesce(used_bytes, 0) into v_used
    from public.storage_usage where user_id = v_uid;
  v_used  := coalesce(v_used, 0);
  v_quota := public.storage_quota_bytes(v_uid);
  v_would := (v_used + v_add) > v_quota;

  v_enforced := coalesce(
    (select (value->>'enforce_storage')::boolean
       from app_private.config where key = 'gate'), false);

  -- قياس فقط حين سيتجاوز ولمّا يُفعَّل الحجب — مرة/ساعة/مستخدم (بلا إغراق).
  if v_would and not v_enforced then
    select exists(
      select 1 from public.admin_audit
       where action = 'storage_block_probe'
         and target_user = v_uid
         and created_at > now() - interval '1 hour'
    ) into v_recent;
    if not v_recent then
      select email into v_email from auth.users where id = v_uid;
      insert into public.admin_audit
        (actor, actor_email, action, target_user, target_email, detail)
      values (v_uid, v_email, 'storage_block_probe', v_uid, v_email,
              jsonb_build_object('used', v_used, 'add', v_add,
                                 'quota', v_quota));
    end if;
  end if;

  return jsonb_build_object(
    'allowed',    (not v_would) or (not v_enforced),
    'used',       v_used,
    'quota',      v_quota,
    'add',        v_add,
    'would_block', v_would,
    'enforced',   v_enforced
  );
end;
$$;

revoke all on function public.storage_can_upload(bigint) from public, anon;
grant execute on function public.storage_can_upload(bigint) to authenticated;

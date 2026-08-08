-- ============================================================================
--  notif_probe.sql — مسبار الإشعارات داخل التطبيق (المرحلة هـ / الهجرة 0064)
-- ============================================================================
--
--  الغرض
--  ─────
--  إثبات صحة دوال 0064 الخمس من منظور مستدعٍ حقيقي: مشرفٌ يُرسل موجَّهاً
--  ويبثّ للجميع، ثم مستخدمٌ عاديٌّ يقرأ غير المقروء ويعلّم واحداً مقروءاً،
--  ثم قراءة إعداد التحديث، وأخيراً رفض الإرسال لغير المشرف.
--
--  المنهج (كمصفوفة الاختراق القائمة تماماً)
--  ────────────────────────────────────────
--    • JWT مُنتحَل عبر set_config('request.jwt.claims', …, is_local=true) —
--      محليٌّ للمعاملة، وتبديل الدور بـset local role / reset role.
--    • الدوال كلها SECURITY DEFINER فتقرأ auth.uid() من ادّعاء sub؛ لذا لا
--      حاجة لكتابةٍ في app_private (get_app_update يقرأ المخطط الخاص بنفسه).
--
--  الأمان
--  ──────
--    • كامل السكربت داخل معاملة واحدة تنتهي بـ ROLLBACK: لا صفّ إشعارٍ ولا
--      سجلّ تدقيقٍ يبقى — حتى لو فشل في المنتصف.
--    • يُشغَّل عبر واجهة SQL (لا psql): بلا أي أوامر ميتا خلفية (\set/\echo)؛
--      الإخفاق يُرفع بـ raise exception فيُجهض المعاملة، والنجاح بـ raise notice.
--    • شغّله على قاعدة تدريجٍ أولاً؛ على الإنتاج يلزم دورٌ يتجاوز RLS للقراءة
--      عبر الأدوار داخل المعاملة (كما مسبار الاختراق).
-- ============================================================================

begin;

do $probe$
declare
  v_admin   uuid;
  v_user    uuid;
  v_email   text;
  v_notifs  jsonb;
  v_one     uuid;
  v_cnt     integer;
  v_users   bigint;
  v_upd     jsonb;
  v_has     boolean;
  v_raised  boolean;
begin
  -- ── اختيار فاعلَين حقيقيَّين ───────────────────────────────────────────────
  select user_id into v_admin
    from public.admins
   where user_id is not null
   limit 1;
  if v_admin is null then
    raise exception 'probe: لا يوجد حساب إدارة لاختبار مسار المشرف';
  end if;

  select user_id into v_user
    from public.subscriptions
   limit 1;
  if v_user is null then
    raise exception 'probe: لا يوجد مستخدم في subscriptions للانتحال';
  end if;
  select email into v_email from auth.users where id = v_user;

  raise notice '── فاعلون: admin=% user=% email=% ──',
    v_admin, v_user, coalesce(v_email, '—');

  -- ════════════════════════════════════════════════════════════════════════
  --  (أ) إرسالٌ موجَّه بحمولةٍ غنية بدور المشرف، والتأكد من الصفّ + data
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  set local role authenticated;

  perform public.admin_send_notification(
    v_user, 'ت', 'ن', 'notice',
    '{"image_url":"x","action_label":"افتح","action_url":"https://x"}'::jsonb);

  reset role;

  perform 1
     from public.notifications
    where user_id = v_user
      and title = 'ت'
      and data->>'action_label' = 'افتح';
  if not found then
    raise exception 'probe (أ): لم يوجد صف الإشعار الموجَّه بـdata->>action_label=افتح';
  end if;
  raise notice '✓ (أ) إرسال موجَّه: صفٌّ موجودٌ وحمولته الغنية سليمة (action_label=افتح).';

  -- ════════════════════════════════════════════════════════════════════════
  --  (ب) بثٌّ للجميع بدور المشرف، والتأكد أن العدد = عدد auth.users
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  set local role authenticated;

  v_cnt := public.admin_broadcast_notification('ب', 'ن2', 'notice', '{}'::jsonb);

  reset role;

  select count(*) into v_users from auth.users;
  if v_cnt is distinct from v_users::integer then
    raise exception 'probe (ب): عدد البثّ % لا يساوي عدد المستخدمين %', v_cnt, v_users;
  end if;
  raise notice '✓ (ب) بثّ للجميع: العدد المُعاد % مساوٍ لعدد auth.users %.', v_cnt, v_users;

  -- ════════════════════════════════════════════════════════════════════════
  --  (ج) بدور المستخدم العادي: غير المقروء ≥١، تعليم واحدٍ مقروءاً، ثم غيابه
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);
  set local role authenticated;

  v_notifs := public.get_my_notifications();
  if jsonb_array_length(v_notifs) < 1 then
    reset role;
    raise exception 'probe (ج): get_my_notifications يجب أن يعيد ≥١ غير مقروء (الإرسال+البثّ). res=%', v_notifs;
  end if;

  v_one := (v_notifs->0->>'id')::uuid;
  perform public.mark_notification_read(v_one);

  v_notifs := public.get_my_notifications();
  reset role;

  if exists (
    select 1
      from jsonb_array_elements(v_notifs) e
     where (e->>'id')::uuid = v_one
  ) then
    raise exception 'probe (ج): الإشعار % ما زال ظاهراً بعد تعليمه مقروءاً', v_one;
  end if;
  raise notice '✓ (ج) قراءة/تعليم: غير المقروء ≥١، وبعد mark_notification_read غاب المعرّف %.', v_one;

  -- ════════════════════════════════════════════════════════════════════════
  --  (د) get_app_update يعيد كائن jsonb فيه مفتاح enabled
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);
  set local role authenticated;

  v_upd := public.get_app_update();
  reset role;

  if jsonb_typeof(v_upd) is distinct from 'object' then
    raise exception 'probe (د): get_app_update يجب أن يعيد كائناً. res=%', v_upd;
  end if;
  if not (v_upd ? 'enabled') then
    raise exception 'probe (د): كائن get_app_update يجب أن يحوي مفتاح enabled. res=%', v_upd;
  end if;
  raise notice '✓ (د) إعداد التحديث: كائنٌ يحوي مفتاح enabled (enabled=%).', v_upd->>'enabled';

  -- ════════════════════════════════════════════════════════════════════════
  --  (هـ) ادّعاءات فارغة (لا sub) ⇒ admin_send_notification يرفع «admin privilege»
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims',
    json_build_object('role', 'authenticated')::text, true);
  set local role authenticated;

  v_raised := false;
  begin
    perform public.admin_send_notification(v_user, 'x', 'x', 'notice', '{}'::jsonb);
  exception when others then
    v_raised := true;
    if sqlerrm not ilike '%admin privilege%' then
      reset role;
      raise exception 'probe (هـ): الرفض المتوقَّع «admin privilege» لكن الخطأ كان: %', sqlerrm;
    end if;
  end;
  reset role;

  if not v_raised then
    raise exception 'probe (هـ): admin_send_notification كان يجب أن يُرفَض لغير المشرف (ادّعاءات فارغة)';
  end if;
  raise notice '✓ (هـ) حراسة المشرف: رُفض الإرسال لغير المشرف بـ«admin privilege».';

  raise notice '════ كل فحوص مسبار الإشعارات نجحت (سيُتراجَع عن كل الأثر). ════';
end;
$probe$;

rollback;

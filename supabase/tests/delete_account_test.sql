-- ============================================================================
--  اختبار حذف الحساب — انحدار م185
-- ============================================================================
--
--  لماذا يوجد هذا الملف
--  ────────────────────
--  زرّ «حذف الحساب نهائياً» فشل عند المالك برسالة Postgres خام:
--      violates foreign key constraint "activation_codes_bound_user_id_fkey"
--  السبب مفتاحٌ أجنبي بسلوك NO ACTION، وتحته عيبٌ أعمق: دالة الحذف كُتبت
--  بقائمة جداول ثابتة (م93) فصارت ناقصةً مع كل جدولٍ جديد — تسريبٌ صامت
--  يظهر يوم يحذف مستخدمٌ حسابه فتبقى بياناته.
--
--  ما يُثبته هذا الاختبار (كله سلبيٌّ بالأساس — «لا يبقى شيء»):
--    ١) الحذف ينجح ولا يُمنع بمفتاح أجنبي.
--    ٢) لا يبقى صفٌّ للمستخدم في أي جدولٍ من جداول بياناته.
--    ٣) كود التنشيط يبقى **مستهلَكاً** (status=used) مجرَّداً من الهوية —
--       فلا سجلَّ ترخيصٍ يُمحى، ولا كودَ يعود صالحاً (ثغرة تجربة لا نهائية).
--    ٤) حارس account_purge_gaps() يعيد صفر صفوف — أي لا جدول يحمل هوية
--       مستخدم خارج التطهير والتتالي.
--
--  التشغيل
--  ───────
--    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/delete_account_test.sql
--
--  ⚠ كل شيء داخل معاملة تنتهي بـ ROLLBACK: يكتب مستخدماً وهمياً بمعرّف
--    مخصّص للاختبار ثم يتراجع عنه — **لا يمسّ أي بيانات حقيقية**. وهذا
--    هو نفس السيناريو الذي جُرِّب على الإنتاج قبل تطبيق المهاجرة.
-- ============================================================================

\set ON_ERROR_STOP on
\set probe '11111111-2222-3333-4444-555555555555'

BEGIN;

-- ── بيانات وهمية: مستخدم + كود مرتبط + صفوف في الجداول غير المتتالية ──
INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
VALUES ('00000000-0000-0000-0000-000000000000', :'probe', 'authenticated',
        'authenticated', 'delete-account-test@example.invalid', 'x',
        now(), now(), now());

INSERT INTO public.activation_codes (code_hash, code_prefix, status,
                                     bound_user_id, bound_email, used_at, note)
VALUES ('delete-account-test-hash', 'TEST', 'used', :'probe',
        'delete-account-test@example.invalid', now(), 'اختبار');

INSERT INTO public.audit_log (id, user_id, at, action)
VALUES (gen_random_uuid(), :'probe', now(), 'test');

INSERT INTO public.applied_ops (user_id, op_id)
VALUES (:'probe', 'delete-account-test-op') ON CONFLICT DO NOTHING;

-- ── النداء بهوية المستخدم الوهمي (كما ينادِيه التطبيق تماماً) ──
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'probe', 'role', 'authenticated')::text, true);
SET LOCAL ROLE authenticated;
SELECT public.delete_my_account();
RESET ROLE;

-- ── ١+٢) لا صفَّ مستخدم ولا أثرَ بيانات ──
DO $$
DECLARE
  v_uid uuid := '11111111-2222-3333-4444-555555555555';
  n     bigint;
BEGIN
  SELECT count(*) INTO n FROM auth.users WHERE id = v_uid;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: صفّ المستخدم لم يُحذف (%)', n;
  END IF;
  SELECT count(*) INTO n FROM public.audit_log WHERE user_id = v_uid;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: audit_log بقي (%)', n; END IF;
  SELECT count(*) INTO n FROM public.applied_ops WHERE user_id = v_uid;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL: applied_ops بقي (%)', n; END IF;
  RAISE NOTICE 'PASS ١+٢: الحذف نجح ولا أثر لبيانات المستخدم';
END $$;

-- ── ٣) الكود: باقٍ ومستهلَك ومجرَّد من الهوية ──
DO $$
DECLARE
  r record;
BEGIN
  SELECT status, bound_user_id, bound_email INTO r
    FROM public.activation_codes WHERE code_hash = 'delete-account-test-hash';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: صفّ الكود حُذف — سجلّ الترخيص يجب أن يبقى';
  END IF;
  IF r.status <> 'used' THEN
    RAISE EXCEPTION 'FAIL: حالة الكود صارت % — يجب أن تبقى used '
      '(وإلا صار الحذف باباً لتجربةٍ لا نهائية)', r.status;
  END IF;
  IF r.bound_user_id IS NOT NULL OR r.bound_email IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: هوية صاحب الكود لم تُجرَّد';
  END IF;
  RAISE NOTICE 'PASS ٣: الكود مستهلَك ومجرَّد من الهوية';
END $$;

-- ── ٤) حارس الفجوات: صفر ──
DO $$
DECLARE
  n bigint;
  g text;
BEGIN
  SELECT count(*) INTO n FROM public.account_purge_gaps();
  IF n <> 0 THEN
    SELECT string_agg(table_name || '.' || column_name, ', ')
      INTO g FROM public.account_purge_gaps();
    RAISE EXCEPTION 'FAIL: جداول تحمل هوية مستخدم خارج التطهير: %', g;
  END IF;
  RAISE NOTICE 'PASS ٤: لا فجوات تطهير';
END $$;

ROLLBACK;

-- ============================================================================
--  اختبار عزل الحسابات — انحدار RLS
-- ============================================================================
--
--  لماذا يوجد هذا الملف
--  ────────────────────
--  المهاجرة 0016 أعادت كتابة سياسة SELECT على المسار الساخن. إثبات العزل
--  بعدها كان لقطةً لحظية شغّلتها يدوياً على الإنتاج — واللقطة لا تمنع
--  انحداراً. ما يمنعه اختبارٌ يعمل مع كل تغيير.
--
--  الاختبار **سلبي بالأساس**: لا يكفي أن يرى المستخدم صفوفه، بل يجب أن
--  يُثبَت أنه **لا** يرى صفوف غيره ولا يكتب باسمه.
--
--  التشغيل
--  ───────
--    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_isolation_test.sql
--
--  يفشل بـ exit code غير صفري عند أي خرق. صالح للتعليق في CI مباشرةً.
--
--  ⚠ يكتب صفوفاً باثنين من معرّفات UUID مخصّصة للاختبار ثم يحذفها. لا
--    يمسّ بيانات حقيقية. مع ذلك: **شغّله على قاعدة تدريج (staging) أولاً.**
--    على قاعدة إنتاج يحتاج دوراً بصلاحية تجاوز RLS للتنظيف.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- معرّفات اختبار لا تتقاطع مع حسابات حقيقية
\set u1 '''aaaaaaaa-0000-4000-8000-000000000001'''
\set u2 '''aaaaaaaa-0000-4000-8000-000000000002'''

DO $outer$
DECLARE
  u1 uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  u2 uuid := 'aaaaaaaa-0000-4000-8000-000000000002';
  n  bigint;
  failures text[] := '{}';
  part text;
BEGIN
  -- بذر: 5 صفوف لـ u1 و3 لـ u2
  INSERT INTO public.sync_rows(user_id, entity, id, payload, txid, server_seq)
  SELECT u1, 'patients', 'rlstest_u1_'||g, '{}'::jsonb, g, g FROM generate_series(1,5) g;
  INSERT INTO public.sync_rows(user_id, entity, id, payload, txid, server_seq)
  SELECT u2, 'patients', 'rlstest_u2_'||g, '{}'::jsonb, g, g FROM generate_series(1,3) g;

  -- ── u1 ──────────────────────────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', u1::text, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  EXECUTE 'SELECT count(*) FROM public.sync_rows WHERE id LIKE ''rlstest_u1_%''' INTO n;
  IF n <> 5 THEN
    failures := failures || format('u1 يرى %s من صفوفه بدل 5 (إيجابي)', n);
  END IF;

  -- الفحص الجوهري: تسريب أفقي
  EXECUTE format(
    'SELECT count(*) FROM public.sync_rows WHERE user_id = %L', u2) INTO n;
  IF n <> 0 THEN
    failures := failures || format('خرق: u1 يرى %s من صفوف u2', n);
  END IF;

  -- انتحال بالكتابة: يجب أن ترفضه WITH CHECK
  BEGIN
    EXECUTE format(
      'INSERT INTO public.sync_rows(user_id, entity, id) VALUES (%L, ''patients'', ''rlstest_spoof'')', u2);
    failures := failures || 'خرق: u1 كتب صفاً باسم u2';
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN
    NULL;  -- المتوقع
  END;

  RESET ROLE;

  -- ── u2 ──────────────────────────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', u2::text, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;

  EXECUTE 'SELECT count(*) FROM public.sync_rows WHERE id LIKE ''rlstest_u2_%''' INTO n;
  IF n <> 3 THEN
    failures := failures || format('u2 يرى %s من صفوفه بدل 3', n);
  END IF;
  EXECUTE format('SELECT count(*) FROM public.sync_rows WHERE user_id = %L', u1) INTO n;
  IF n <> 0 THEN
    failures := failures || format('خرق: u2 يرى %s من صفوف u1', n);
  END IF;

  RESET ROLE;

  -- ── anon: يجب ألّا يرى شيئاً ────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SET LOCAL ROLE anon;
  EXECUTE 'SELECT count(*) FROM public.sync_rows' INTO n;
  IF n <> 0 THEN
    failures := failures || format('خرق: anon يرى %s صفاً', n);
  END IF;
  RESET ROLE;

  -- ── الشرائح خارج سطح REST (المهاجرة 0017) ──────────────────────────────
  SELECT count(*)::text INTO part
  FROM pg_class c JOIN pg_inherits i ON i.inhrelid = c.oid
  WHERE i.inhparent = 'public.sync_rows'::regclass AND c.relkind = 'r'
    AND (has_table_privilege('anon', c.oid, 'SELECT')
      OR has_table_privilege('authenticated', c.oid, 'SELECT'));
  IF part <> '0' THEN
    failures := failures || format('%s شريحة ما زالت مكشوفة لـ PostgREST', part);
  END IF;

  -- ── كل سياسة تلفّ auth.uid() في SELECT (المهاجرة 0016) ─────────────────
  SELECT count(*)::text INTO part FROM pg_policies
  WHERE schemaname = 'public'
    AND (coalesce(qual,'')||coalesce(with_check,'')) ~ 'auth\.uid\(\)'
    AND (coalesce(qual,'')||coalesce(with_check,'')) !~ 'SELECT auth\.uid\(\)';
  IF part <> '0' THEN
    failures := failures || format('%s سياسة ما زالت بـ auth.uid() العارية (انحدار أداء)', part);
  END IF;

  -- ── دوال بمسار بحث متغيّر (المهاجرة 0014) ──────────────────────────────
  SELECT count(*)::text INTO part FROM pg_proc p
  JOIN pg_namespace n2 ON n2.oid = p.pronamespace
  WHERE n2.nspname = 'public' AND p.prokind = 'f'
    AND NOT EXISTS (
      SELECT 1 FROM unnest(coalesce(p.proconfig,'{}'::text[])) c
      WHERE c LIKE 'search_path=%');
  IF part <> '0' THEN
    failures := failures || format('%s دالة بلا search_path مثبَّت', part);
  END IF;

  -- ── anon لا ينفّذ SECURITY DEFINER (المهاجرة 0015) ──────────────────────
  SELECT count(*)::text INTO part FROM pg_proc p
  JOIN pg_namespace n2 ON n2.oid = p.pronamespace
  WHERE n2.nspname = 'public' AND p.prosecdef
    AND has_function_privilege('anon', p.oid, 'EXECUTE');
  IF part <> '0' THEN
    failures := failures || format('anon ينفّذ %s دالة SECURITY DEFINER', part);
  END IF;

  IF array_length(failures, 1) > 0 THEN
    RAISE EXCEPTION E'فشل عزل RLS:\n  - %', array_to_string(failures, E'\n  - ');
  END IF;

  RAISE NOTICE 'عزل RLS سليم — كل الفحوص الإيجابية والسلبية نجحت.';
END $outer$;

-- التراجع يمحو صفوف الاختبار: لا أثر يبقى حتى لو فشل الاختبار.
ROLLBACK;

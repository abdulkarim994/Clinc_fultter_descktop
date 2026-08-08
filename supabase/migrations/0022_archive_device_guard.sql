-- ============================================================================
--  م73 — حارس الجهاز الغائب + أفق الأرشيف (يسبق تقليص النافذة إلى 3 أشهر)
-- ============================================================================
--
--  العلة التي يغلقها هذا الملف
--  ───────────────────────────
--  الأرشفة (م70) تحذف بعمر الصف وحده. فلو غاب جهاز الاستقبال شهرين وكانت
--  صفوف كُتبت على جهاز الطبيب في تلك الفترة قد بلغت سن الأرشفة، لاختفت من
--  الخادم قبل أن يصلها الجهاز العائد — ومؤشره (txid) يبدأ من نقطة أقدم،
--  فلا يراها أبداً. البيانات ليست ضائعة (هي على جهاز الطبيب وفي حزم R2)
--  لكن الجهاز الثاني يبقى ناقصاً بصمت.
--
--  بنافذة 7 أشهر الاحتمال بعيد؛ **بثلاثة يصبح واقعياً** — لذا يُبنى الحارس
--  قبل التقليص لا بعده.
--
--  ── الآلية ─────────────────────────────────────────────────────────────
--
--  1) `device_sync_state`: صف واحد لكل (حساب، جهاز) يحمل آخر مؤشر بلغه
--     الجهاز وآخر ظهور له. العميل يبلّغ **مرة يومياً** لا مع كل دورة —
--     دقة اليوم تكفي لنافذة بالأشهر، وتكلفتها نداء واحد يومياً (~380 بايت).
--
--  2) `archive_rows` لا تحذف صفاً إلا إذا كان `txid` أقل من **أدنى مؤشر**
--     بين كل الأجهزة النشطة. جهاز غائب ⇒ مؤشره قديم ⇒ الأرشفة تتوقف عند
--     حدّه تلقائياً وتستأنف حين يعود ويلحق. أما الأجهزة المهجورة (لم تظهر
--     منذ `p_abandon_days`، افتراضياً 180 يوماً) فتُتجاهل كي لا يوقف جهاز
--     تالف الأرشفةَ للأبد.
--
--  3) `archive_horizon`: أعلى txid حُذف فعلاً لكل حساب. `pull_changes`
--     تعيده مع كل سحب، فالجهاز الذي يجد مؤشره **تحت** الأفق يعرف أن ثمة
--     فجوة ويستدعي الاسترجاع من تلقائه بدل انتظار زر يدوي.
--
--  ── التوافق مع النسخ القديمة ────────────────────────────────────────────
--  `pull_changes` تكسب مفتاحاً جديداً في الاستجابة فقط — لا تغيير في
--  المعاملات ولا في `rows`/`safe`. العميل القديم يتجاهل المفتاح المجهول
--  فيعمل كما كان. و`archive_rows` تكسب معاملين اختياريين بقيم افتراضية:
--  النداء القديم (معاملان) ما زال صالحاً ويسلك سلوك العمر وحده.
-- ============================================================================

-- ── 1) حالة مزامنة الأجهزة ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.device_sync_state (
  user_id      uuid        NOT NULL,
  device_id    text        NOT NULL,
  cursor_txid  bigint      NOT NULL DEFAULT 0,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, device_id)
);
REVOKE ALL ON public.device_sync_state FROM PUBLIC, anon, authenticated;
ALTER TABLE public.device_sync_state ENABLE ROW LEVEL SECURITY;

-- ── 2) أفق الأرشيف ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.archive_horizon (
  user_id          uuid        NOT NULL PRIMARY KEY,
  max_archived_txid bigint     NOT NULL DEFAULT 0,
  updated_at       timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON public.archive_horizon FROM PUBLIC, anon, authenticated;
ALTER TABLE public.archive_horizon ENABLE ROW LEVEL SECURITY;

-- ── 3) تبليغ حالة الجهاز (يومياً) ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.report_sync_state(
  p_device_id text,
  p_cursor_txid bigint
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth required';
  END IF;
  IF coalesce(p_device_id, '') = '' THEN
    RETURN;
  END IF;
  INSERT INTO public.device_sync_state(user_id, device_id, cursor_txid, last_seen_at)
  VALUES (v_uid, left(p_device_id, 64), GREATEST(coalesce(p_cursor_txid, 0), 0), now())
  ON CONFLICT (user_id, device_id) DO UPDATE
    -- المؤشر لا يتراجع: نبضة متأخرة من دورة قديمة لا تُنزل الحدّ فتُعطّل
    -- الأرشفة بلا سبب.
    SET cursor_txid  = GREATEST(public.device_sync_state.cursor_txid,
                                EXCLUDED.cursor_txid),
        last_seen_at = now();
END $$;

REVOKE ALL ON FUNCTION public.report_sync_state(text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_sync_state(text, bigint)
  TO authenticated, service_role;

-- ── 4) archive_rows: يضاف حارس المؤشر إلى حارس العمر ──────────────────────
--  ⚠ النسخة القديمة (jsonb, integer) تُسقَط أولاً: التوقيع الجديد بأربعة
--  معاملات **حِمل زائد** لا بديل، وبقاء الاثنين يجعل نداء المعاملين يصيب
--  القديمة (المطابقة التامة تُرجَّح) فيتخطى حارس المؤشر بصمت.
DROP FUNCTION IF EXISTS public.archive_rows(jsonb, integer);

CREATE OR REPLACE FUNCTION public.archive_rows(
  p_items jsonb,
  p_min_age_days integer DEFAULT 90,
  p_caller_txid bigint DEFAULT NULL,
  p_abandon_days integer DEFAULT 180
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_cut   timestamptz;
  v_guard bigint;
  v_n     integer := 0;
  v_ents  jsonb;
  v_max   bigint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth required';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RETURN 0;
  END IF;
  IF jsonb_array_length(p_items) > 10000 THEN
    RAISE EXCEPTION 'too many items (max 10000)';
  END IF;

  -- حارس العمر (كما في 0020): أرضية 90 يوماً تُفرض خادمياً.
  v_cut := now() - make_interval(days => GREATEST(coalesce(p_min_age_days, 90), 90));

  -- حارس المؤشر: أدنى مؤشر بين الأجهزة النشطة (والمهجورة تُتجاهل).
  -- مؤشر المستدعي يُدرَج أيضاً حتى لو لم يبلّغ بعد.
  SELECT min(cursor_txid) INTO v_guard
  FROM (
    SELECT cursor_txid
    FROM public.device_sync_state
    WHERE user_id = v_uid
      AND last_seen_at > now()
          - make_interval(days => GREATEST(coalesce(p_abandon_days, 180), 30))
    UNION ALL
    SELECT coalesce(p_caller_txid, 0) WHERE p_caller_txid IS NOT NULL
  ) g;

  -- لا معلومة عن أي جهاز ⇒ لا حارس مؤشر (يبقى حارس العمر وحده).
  IF v_guard IS NULL THEN
    v_guard := 9223372036854775807;
  END IF;

  WITH req AS (
    SELECT DISTINCT it->>'entity' AS entity, it->>'id' AS id
    FROM jsonb_array_elements(p_items) it
    WHERE it->>'entity' IN ('records', 'appointments', 'xrays')
      AND coalesce(it->>'id', '') <> ''
  ),
  del AS (
    DELETE FROM public.sync_rows s
    USING req r
    WHERE s.user_id = v_uid
      AND s.entity  = r.entity
      AND s.id      = r.id
      AND s.updated_at < v_cut
      AND s.txid      < v_guard      -- ← الحارس الجديد
    RETURNING s.entity, s.txid
  )
  -- ⚠ إصلاح عطل موروث من 0020: كان `count(*)` على تجميعة GROUP BY entity
  -- فيعيد **عدد الكيانات** لا عدد الصفوف. أخفاه اختبار بثلاثة كيانات وصف
  -- لكلٍّ (3 = 3 صدفةً). الصحيح `sum(cnt)`. لا أثر على الحذف نفسه —
  -- العدد المعاد فقط كان يكذب على المستخدم وعلى سجل الأرشفة.
  SELECT coalesce(sum(cnt), 0)::int,
         jsonb_object_agg(entity, cnt),
         max(mx)
    INTO v_n, v_ents, v_max
    FROM (SELECT entity, count(*) AS cnt, max(txid) AS mx
          FROM del GROUP BY entity) x;

  v_n := coalesce(v_n, 0);
  IF v_n > 0 THEN
    INSERT INTO public.archive_log(user_id, n_rows, entities)
    VALUES (v_uid, v_n, v_ents);
    -- الأفق: أعلى txid حُذف — يكشف الفجوة لأي جهاز مؤشره تحته.
    INSERT INTO public.archive_horizon(user_id, max_archived_txid, updated_at)
    VALUES (v_uid, coalesce(v_max, 0), now())
    ON CONFLICT (user_id) DO UPDATE
      SET max_archived_txid = GREATEST(public.archive_horizon.max_archived_txid,
                                       EXCLUDED.max_archived_txid),
          updated_at = now();
  END IF;
  RETURN v_n;
END $$;

REVOKE ALL ON FUNCTION public.archive_rows(jsonb, integer, bigint, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.archive_rows(jsonb, integer, bigint, integer)
  TO authenticated, service_role;

-- ── 5) pull_changes: تعيد الأفق مع كل سحب ─────────────────────────────────
--  إضافة مفتاح فقط — `rows` و`safe` كما هما، فالعميل القديم لا يتأثر.
--  الكلفة: قراءة صف واحد بمفتاحه الأساسي (ميكروثوانٍ) على المسار الساخن.
CREATE OR REPLACE FUNCTION public.pull_changes(
  p_lower bigint DEFAULT 0,
  p_page_txid bigint DEFAULT NULL,
  p_page_seq bigint DEFAULT 0,
  p_upto bigint DEFAULT NULL,
  p_limit integer DEFAULT 500
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_safe bigint;
  v_rows jsonb;
  v_hor  bigint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'pull_changes: not authenticated';
  END IF;
  v_safe := coalesce(p_upto,
                     pg_snapshot_xmin(pg_current_snapshot())::text::bigint);
  SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.txid, t.server_seq), '[]'::jsonb)
    INTO v_rows
  FROM (
    SELECT * FROM sync_rows
    WHERE user_id = v_uid
      AND txid >= p_lower
      AND txid <  v_safe
      AND (p_page_txid IS NULL
           OR txid > p_page_txid
           OR (txid = p_page_txid AND server_seq > p_page_seq))
    ORDER BY txid, server_seq
    LIMIT least(coalesce(p_limit, 500), 2000)
  ) t;

  SELECT max_archived_txid INTO v_hor
  FROM public.archive_horizon WHERE user_id = v_uid;

  RETURN jsonb_build_object(
    'rows', v_rows,
    'safe', v_safe,
    'archive_horizon', coalesce(v_hor, 0)
  );
END $$;

REVOKE ALL ON FUNCTION public.pull_changes(bigint, bigint, bigint, bigint, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pull_changes(bigint, bigint, bigint, bigint, integer)
  TO authenticated, service_role;

-- ============================================================================
--  0026 — سجلّ تدقيق خادمي لا يقبل إلا الإضافة
--  ⚠ مُطبَّقة على الإنتاج: 2026-07-31
-- ============================================================================
--
--  لماذا على الخادم ولم يكفِ المحلي
--  ─────────────────────────────────
--  سجلّ تدقيق يعيش على الجهاز وحده **لا يصلح للتدقيق**: من يملك الجهاز
--  يملك قاعدته غير المشفّرة، فيمحو أثر اطّلاعه. والنسخة الخادمية خارج
--  متناوله وتصلح دليلاً.
--
--  إضافة فقط — وحتّى للمالك
--  ────────────────────────
--  تُعرَّف سياستا INSERT وSELECT فقط. ولأن RLS يمنع ما لا سياسة له، يصير
--  UPDATE وDELETE ممنوعَين تماماً — **لا يستطيع صاحب الحساب نفسه إعادة
--  كتابة تاريخه**، وهذا مقصود: سجلٌّ يملك المدقَّقُ تعديلَه ليس دليلاً.
--  وتُسحب الصلاحيتان صراحةً أيضاً — حاجزان مستقلّان لا واحد.
--
--  المعرّف من العميل عمداً: يجعل الدفع عديم الأثر، فإعادة إرسال دفعة بعد
--  انقطاع شبكة لا تُكرّر القيود.

create table if not exists public.audit_log (
  id          text primary key,
  user_id     uuid not null default auth.uid(),
  at          timestamptz not null,
  actor_uid   text,
  device_id   text,
  action      text not null,
  entity      text,
  entity_id   text,
  detail      jsonb,
  received_at timestamptz not null default now()
);

comment on table public.audit_log is
  'م79 — سجلّ تدقيق لا يقبل إلا الإضافة. لا سياسة UPDATE ولا DELETE — مقصود.';

create index if not exists idx_audit_user_at
  on public.audit_log (user_id, at desc);
create index if not exists idx_audit_user_entity
  on public.audit_log (user_id, entity, entity_id, at desc);

alter table public.audit_log enable row level security;

drop policy if exists audit_insert_own on public.audit_log;
create policy audit_insert_own on public.audit_log
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists audit_select_own on public.audit_log;
create policy audit_select_own on public.audit_log
  for select to authenticated
  using (user_id = (select auth.uid()));

revoke update, delete, truncate on public.audit_log from authenticated, anon;
grant select, insert on public.audit_log to authenticated;

-- تحقّق (نُفِّذ على الإنتاج):
--   السياسات = INSERT, SELECT فقط
--   الصلاحيات = INSERT, REFERENCES, SELECT, TRIGGER  ← لا UPDATE ولا DELETE

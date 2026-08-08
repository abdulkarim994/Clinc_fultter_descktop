-- ============================================================================
-- 0049 — بذر حسابات الإدارة الثلاثة (طُبِّقت على الخادم 2026‑08‑05 عبر MCP)
-- ============================================================================
--
--  تعمل فوق «النظام المعتمد»: مخطط التراخيص الذي طُبِّق بهجرات 0032–0048
--  من جلسة عمل المالك الموازية صباح 2026‑08‑05 واعتمده المالك أساساً
--  (شيفرة تلك الهجرات محفوظة في supabase_migrations على الخادم؛ توثيقها
--  المحلي في supabase/ADOPTED_SYSTEM_AR.md).
--
--  العضوية في admins هي كل صلاحية لوحة التحكم — لا مفتاح خدمة في أي تطبيق.

insert into public.admins (user_id, email, role)
select u.id, u.email, 'owner'
from auth.users u
where u.email in (
  'mam3t7zn995@gmail.com',   -- Abd Alibrahim
  'dam3t7zn995@gmail.com',   -- ABN KAREEM
  'ibabd981@gmail.com'       -- MATRY
)
on conflict (user_id) do nothing;

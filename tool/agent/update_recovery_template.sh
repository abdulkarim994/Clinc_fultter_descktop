#!/usr/bin/env bash
# ============================================================================
#  م186 — تحديث قالب بريد استعادة كلمة المرور عبر Supabase Management API
# ============================================================================
#
#  لماذا هذا السكربت
#  ─────────────────
#  قوالب البريد تعيش في طبقة إدارة Supabase (control plane) لا في قاعدة
#  المشروع — فلا يصلها SQL ولا خادم MCP. المسار الوحيد المؤتمت هو
#  Management API بمفتاح شخصي (sbp_…) يُنشأ من:
#      supabase.com/dashboard/account/tokens
#  ويُحفظ في حقل SUPABASE_MGMT_TOKEN في بطاقة هذه المهارة.
#
#  ماذا يفعل
#  ─────────
#    ١) يقرأ قالب م186 من المستودع (يجرّد ترويسة التعليمات التعليقية).
#    ٢) PATCH /v1/projects/{ref}/config/auth:
#         mailer_subjects_recovery  = «رمز استعادة كلمة المرور — DENTSHINE»
#         mailer_templates_recovery_content = القالب (يعرض {{ .Token }})
#    ٣) GET للتحقق أن المحتوى المخزَّن صار يحمل الرمز لا الرابط.
#
#  الاستعمال (عبر RunWithCredentials حصراً — المفتاح لا يظهر في الأوامر):
#      bash skills/dental-clinic-build/update_recovery_template.sh [مسار الريبو]
# ============================================================================
set -euo pipefail

REPO="${1:-/agent/workspace/repo}"
REF="qajgqatflmiiwqznxfha"
TEMPLATE="$REPO/supabase/templates/recovery_email.html"
SUBJECT="رمز استعادة كلمة المرور — DENTSHINE"

if [ -z "${SUPABASE_MGMT_TOKEN:-}" ]; then
  echo "❌ حقل SUPABASE_MGMT_TOKEN فارغ في بطاقة المهارة."
  echo "   أنشئ مفتاحاً من supabase.com/dashboard/account/tokens"
  echo "   والصقه في بطاقة مهارة dental-clinic-build ثم أعد التشغيل."
  exit 1
fi
[ -f "$TEMPLATE" ] || { echo "❌ القالب غير موجود: $TEMPLATE"; exit 1; }

# ── ١) الحمولة: تجريد ترويسة التعليمات (تعليق HTML الأول) ثم JSON آمن ──
python3 - "$TEMPLATE" "$SUBJECT" > /tmp/auth_patch.json <<'PY'
import json, re, sys
html = open(sys.argv[1], encoding='utf-8').read()
# القالب الفعلي يبدأ من أول <div — ما قبله تعليمات للمشغّل البشري.
m = re.search(r'<div\b', html)
body = html[m.start():] if m else html
print(json.dumps({
    'mailer_subjects_recovery': sys.argv[2],
    'mailer_templates_recovery_content': body,
}, ensure_ascii=False))
PY
echo "ℹ️  حجم الحمولة: $(wc -c < /tmp/auth_patch.json) بايت"

# ── ٢) التطبيق ──
HTTP=$(curl -sS -o /tmp/auth_patch_res.json -w '%{http_code}' \
  -X PATCH "https://api.supabase.com/v1/projects/$REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_MGMT_TOKEN" \
  -H "Content-Type: application/json" \
  --data @/tmp/auth_patch.json)
if [ "$HTTP" != "200" ]; then
  echo "❌ فشل التطبيق (HTTP $HTTP):"
  head -c 400 /tmp/auth_patch_res.json; echo
  exit 1
fi
echo "✅ طُبّق القالب (HTTP 200)"

# ── ٣) تحقق القراءة الراجعة ──
curl -sS "https://api.supabase.com/v1/projects/$REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_MGMT_TOKEN" > /tmp/auth_cfg.json
python3 - <<'PY'
import json
cfg = json.load(open('/tmp/auth_cfg.json'))
subj = cfg.get('mailer_subjects_recovery') or ''
body = cfg.get('mailer_templates_recovery_content') or ''
ok_token = '{{ .Token }}' in body
ok_link = '{{ .ConfirmationURL }}' not in body
ok_brand = 'DENTSHINE' in body
print(f"   العنوان: {subj}")
print(f"   يعرض الرمز {{{{ .Token }}}}: {'✅' if ok_token else '❌'}")
print(f"   بلا رابط قديم: {'✅' if ok_link else '❌'}")
print(f"   بهوية DENTSHINE: {'✅' if ok_brand else '❌'}")
raise SystemExit(0 if (ok_token and ok_link and ok_brand) else 1)
PY
rm -f /tmp/auth_patch.json /tmp/auth_cfg.json /tmp/auth_patch_res.json
echo "🟢 قالب الاستعادة صار بالرمز — جرّب «نسيت كلمة المرور؟» من التطبيق."

// src/index.js
var index_default = {
  async fetch(request, env) {
    const url = new URL(request.url);
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Patient-Name,X-File-Name",
      "Access-Control-Expose-Headers": "X-File-Name,X-Patient-Name,X-Upload-Date"
    };
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    const auth = request.headers.get("Authorization") || "";
    const qToken = url.searchParams.get("token") || "";
    const token = auth.startsWith("Bearer ") ? auth.replace("Bearer ", "") : qToken;
    if (!token) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...cors, "Content-Type": "application/json" } });
    }
    let userId;
    try {
      const payload = JSON.parse(atob(token.split(".")[1]));
      userId = payload.sub;
      if (!userId) throw new Error("No sub");
    } catch (e) {
      return new Response(JSON.stringify({ error: "Invalid token" }), { status: 401, headers: { ...cors, "Content-Type": "application/json" } });
    }
    const path = url.pathname;
    try {
      if (request.method === "POST" && path === "/upload") {
        const patientName = request.headers.get("X-Patient-Name") || "unknown";
        const fileName = request.headers.get("X-File-Name") || `img_${Date.now()}.jpg`;
        const key = `${userId}/${patientName}/${Date.now()}_${fileName}`;
        const body = await request.arrayBuffer();
        if (body.byteLength > 5 * 1024 * 1024) {
          return new Response(JSON.stringify({ error: "File too large (max 5MB)" }), { status: 413, headers: { ...cors, "Content-Type": "application/json" } });
        }
        // ---- Storage quota guard (server-side; Phase A) --------------------
        // Enforcement lives behind the gate.enforce_storage sub-flag: the RPC
        // returns allowed=true while the flag is off (measure-only), so nothing
        // new is blocked until the owner flips it. FAIL-OPEN: a guard error
        // must never break a legitimate upload.
        try {
          if (env.SUPABASE_URL && env.SUPABASE_ANON_KEY) {
            const guard = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/storage_can_upload`, {
              method: "POST",
              headers: {
                "apikey": env.SUPABASE_ANON_KEY,
                "Authorization": `Bearer ${token}`,
                "Content-Type": "application/json"
              },
              body: JSON.stringify({ p_add_bytes: body.byteLength })
            });
            if (guard.ok) {
              const q = await guard.json();
              if (q && q.enforced === true && q.allowed === false) {
                return new Response(JSON.stringify({ error: "storage_full", used: q.used, quota: q.quota }), { status: 413, headers: { ...cors, "Content-Type": "application/json" } });
              }
            }
          }
        } catch (e) {
          // fail-open: allow the upload if the quota check itself failed
        }
        // --------------------------------------------------------------------
        await env.XRAY_BUCKET.put(key, body, {
          customMetadata: { patientName, fileName, userId, uploadDate: (/* @__PURE__ */ new Date()).toISOString().substring(0, 10) }
        });
        return new Response(JSON.stringify({ success: true, key, url: `/image/${encodeURIComponent(key)}` }), {
          headers: { ...cors, "Content-Type": "application/json" }
        });
      }
      if (request.method === "GET" && path.startsWith("/image/")) {
        const key = decodeURIComponent(path.replace("/image/", ""));
        if (!key.startsWith(userId + "/")) {
          return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403, headers: { ...cors, "Content-Type": "application/json" } });
        }
        const obj = await env.XRAY_BUCKET.get(key);
        if (!obj) {
          return new Response(JSON.stringify({ error: "Not found" }), { status: 404, headers: { ...cors, "Content-Type": "application/json" } });
        }
        const headers = { ...cors, "Content-Type": obj.httpMetadata?.contentType || "image/jpeg", "Cache-Control": "public, max-age=31536000" };
        return new Response(obj.body, { headers });
      }
      if (request.method === "GET" && path.startsWith("/list/")) {
        const patientName = decodeURIComponent(path.replace("/list/", ""));
        const prefix = `${userId}/${patientName}/`;
        const listed = await env.XRAY_BUCKET.list({ prefix });
        const items = listed.objects.map((o) => ({
          key: o.key,
          name: o.customMetadata?.fileName || o.key.split("/").pop(),
          date: o.customMetadata?.uploadDate || o.uploaded?.toISOString()?.substring(0, 10) || "",
          size: o.size,
          url: `/image/${encodeURIComponent(o.key)}`
        }));
        return new Response(JSON.stringify({ items }), { headers: { ...cors, "Content-Type": "application/json" } });
      }
      if (request.method === "DELETE" && path.startsWith("/image/")) {
        const key = decodeURIComponent(path.replace("/image/", ""));
        if (!key.startsWith(userId + "/")) {
          return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403, headers: { ...cors, "Content-Type": "application/json" } });
        }
        await env.XRAY_BUCKET.delete(key);
        return new Response(JSON.stringify({ success: true }), { headers: { ...cors, "Content-Type": "application/json" } });
      }
      return new Response(JSON.stringify({ error: "Not found" }), { status: 404, headers: { ...cors, "Content-Type": "application/json" } });
    } catch (e) {
      return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
    }
  }
};
export {
  index_default as default
};

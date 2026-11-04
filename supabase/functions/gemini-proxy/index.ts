// ============================================================================
//  SMART HRD — Gemini Proxy  (Supabase Edge Function — Deno)
//  File  : supabase/functions/gemini-proxy/index.ts
//  Nama  : gemini-proxy
//  Versi : v2.2 — generationConfig kondisional (tanpa temperature/top_p/top_k
//          untuk model Gemini 3.x+), kode kesalahan berkode (BAD_KEY, REGION,
//          MODEL_UNKNOWN, QUOTA, FORBIDDEN, REJECTED) + action "diag".
//          WAJIB di-deploy ulang bila sebelumnya memakai v2.1/lebih lama.
// ============================================================================
//  PERAN
//    Jembatan aman antara aplikasi SMART-HRD.html dan Google Gemini API.
//    API key Gemini TIDAK PERNAH dikirim ke / disimpan di browser. Kunci
//    dibaca di sisi server dari (urutan prioritas):
//      1) Secret Edge Function : GEMINI_API_KEY   (disarankan), atau
//      2) Tabel app_settings   : kolom gemini->>'api_key'
//         (diisi dari menu Pengaturan aplikasi; hanya Admin Sistem &
//          Manajer HRD yang boleh menulis — dilindungi RLS; dibaca di sini
//          memakai kunci service role sehingga tak pernah keluar ke klien).
//
//  KEAMANAN
//    - Wajib JWT login Supabase (header Authorization: Bearer <access_token>).
//    - Profil & peran diverifikasi dari tabel public.profiles (8 role).
//    - Batas laju: 30 permintaan/menit per pengguna.
//    - Setiap panggilan tercatat ke tabel public.audit_log (best-effort).
//    - Kunci API tidak pernah dikembalikan dalam respons maupun dicatat log.
//    - Kunci dikirim ke Google lewat header x-goog-api-key (tidak di URL).
//    - CORS dapat dibatasi lewat secret ALLOWED_ORIGINS (pisahkan dengan koma;
//      kosongkan = * untuk pengembangan).
//
//  CARA DEPLOY
//    A. Supabase CLI (disarankan):
//         supabase login
//         supabase link --project-ref <PROJECT_REF_ANDA>
//         supabase functions deploy gemini-proxy
//         supabase secrets set GEMINI_API_KEY=AQ.Ab8...    (kunci baru AI Studio berawalan AQ.)
//         # opsional: supabase secrets set ALLOWED_ORIGINS=https://domain-anda
//    B. Dashboard (tanpa CLI):
//         Edge Functions → Create a new function → beri nama gemini-proxy
//         → tempel seluruh isi file ini → Deploy.
//         Lalu Edge Functions → Secrets → tambah GEMINI_API_KEY.
//    Catatan: bila secret tidak di-set, function otomatis memakai kunci yang
//    disimpan admin pada menu Pengaturan aplikasi (tabel app_settings).
//
//  PROTOCOOL (POST JSON)
//    { "action": "info" }                    → cek konfigurasi server (untuk Uji Koneksi)
//    { "action": "diag" }                    → diagnostika: daftar model Gemini yang BENAR-BENAR
//                                              tersedia untuk kunci di server (dipakai tombol
//                                              🔍 Diagnosa Kunci & Model di Pengaturan)
//    { "prompt": "...", "system": "...", "model": "gemini-3.8-flash",
//      "temperature": 0.4, "maxOutputTokens": 8192, "action": "generate" }
//      action "json"   → memaksa keluaran application/json
//      action "chat"   → gunakan "messages":[{"role":"user"|"model","text":"..."}]
//    "attachments": [{ "mime": "application/pdf", "data": "<base64>" }]
//    Respons : { ok: true,  text, model, finish, usage }
//              { ok: false, error, code?, detail?, model? }
//
//  CATATAN PARAMETER (penting)
//    Mulai Gemini 3.5/3.6 (dan semua model setelahnya, termasuk 3.8 Flash & 4.x)
//    parameter sampling temperature/top_p/top_k DEPRECATED: Google mengembalikan
//    HTTP 400 bila parameter itu dikirim. Function ini hanya mengirim temperature
//    & maxOutputTokens untuk model lama (gemini-1.x / 2.x) dan MENGOSONGKANNYA
//    untuk model 3.x ke atas.
// ============================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

// ---------- konstanta ---------------------------------------------------------
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models';
const TIMEOUT_MS = 90_000;
const MAX_PROMPT_CHARS = 60_000;
const MAX_MESSAGES = 40;
const MAX_ATTACHMENTS = 5;
const MAX_ATTACHMENT_B64 = 8 * 1024 * 1024; // ± 8 MB base64 per lampiran
const RATE_PER_MINUTE = 30;
const DEFAULT_MODEL = 'gemini-3.8-flash';

// ID model resmi Google (per changelog Gemini API; "Gemini 3.8 Flash" adalah
// ID model resmi terkini). Model kustom di luar daftar tetap diterima bila
// berpola gemini-xxx (diisi dari Pengaturan aplikasi).
const MODEL_WHITELIST = new Set([
  'gemini-3.8-flash',
  'gemini-3.7-flash',
  'gemini-3.6-flash',
  'gemini-3.5-flash',
  'gemini-3.5-flash-lite',
  'gemini-3-flash-preview',
  'gemini-3.1-pro',
  'gemini-4-argon',
  'gemini-2.5-pro',
  'gemini-2.5-flash',
  'gemini-2.5-flash-lite',
  'gemini-2.0-flash',
]);

// Model generasi lama (1.x / 2.x) masih menerima parameter sampling; model
// 3.x ke atas MENOLAK parameter tersebut (HTTP 400).
const isLegacyModel = (m: string): boolean => /^gemini-[12][._-]/.test(m);

// Tipe lampiran yang didukung Gemini inline. DOCX/XLSX diekstrak teksnya
// di sisi aplikasi lalu dikirim sebagai teks biasa.
const MIME_WHITELIST = new Set([
  'application/pdf', 'image/png', 'image/jpeg', 'image/webp',
  'text/plain', 'text/csv', 'application/json',
]);

// ---------- CORS ----------------------------------------------------------------
function corsHeaders(req: Request): Record<string, string> {
  const cfg = (Deno.env.get('ALLOWED_ORIGINS') ?? '*')
    .split(',').map((s) => s.trim()).filter(Boolean);
  const origin = req.headers.get('origin') ?? '';
  const allow = cfg.includes('*') ? '*' : (cfg.includes(origin) ? origin : (cfg[0] ?? '*'));
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

function json(req: Request, status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
  });
}

// ---------- batas laju (per pengguna; memori lokal instance) --------------------
const buckets = new Map<string, { n: number; reset: number }>();
function rateLimited(key: string): boolean {
  if (buckets.size > 5_000) buckets.clear(); // pengaman memori
  const now = Date.now();
  const b = buckets.get(key);
  if (!b || now > b.reset) {
    buckets.set(key, { n: 1, reset: now + 60_000 });
    return false;
  }
  if (b.n >= RATE_PER_MINUTE) return true;
  b.n += 1;
  return false;
}

// ---------- util ------------------------------------------------------------------
function resolveModel(raw: unknown): string {
  const m = typeof raw === 'string' ? raw.trim().toLowerCase() : '';
  if (MODEL_WHITELIST.has(m)) return m;
  if (/^gemini-[a-z0-9._-]{2,60}$/.test(m)) return m; // model kustom dari Pengaturan
  return DEFAULT_MODEL;
}

const clean = (s: unknown, max: number): string =>
  typeof s === 'string' ? s.slice(0, max) : '';

// ---------- handler ----------------------------------------------------------------
Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return json(req, 405, { ok: false, error: 'Gunakan metode POST.' });

  try {
    // 1) Autentikasi pengguna (JWT Supabase wajib)
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) {
      return json(req, 401, {
        ok: false, code: 'NO_SESSION',
        error: 'Tidak memiliki izin — header Authorization: Bearer <access_token> wajib disertakan.',
      });
    }
    const sbUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? anonKey;
    if (!sbUrl || !anonKey) {
      return json(req, 500, { ok: false, error: 'Server belum dikonfigurasi (variabel Supabase tidak tersedia).' });
    }

    const userClient = createClient(sbUrl, anonKey, {
      global: { headers: { Authorization: auth } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return json(req, 401, {
        ok: false, code: 'NO_SESSION',
        error: 'Sesi tidak valid atau kedaluwarsa — silakan login ulang.',
      });
    }
    const user = userData.user;

    // 2) RBAC — profil wajib ada & aktif
    const { data: profile } = await userClient
      .from('profiles').select('nama, role, aktif').eq('id', user.id).maybeSingle();
    if (!profile) {
      return json(req, 403, {
        ok: false, code: 'NO_PROFILE',
        error: 'Profil pengguna tidak ditemukan pada sistem. Hubungi Admin Sistem.',
      });
    }
    if (profile.aktif === false) {
      return json(req, 403, {
        ok: false, code: 'INACTIVE',
        error: 'Akun Anda dinonaktifkan. Hubungi Admin Sistem.',
      });
    }

    // 3) Batas laju per pengguna
    if (rateLimited(user.id)) {
      return json(req, 429, {
        ok: false, code: 'RATE',
        error: 'Terlalu banyak permintaan AI — tunggu sebentar lalu coba lagi.',
      });
    }

    // 4) Payload masuk
    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const action = clean(body.action, 12) || 'generate';

    // 5) Kunci API server — secret diutamakan, lalu app_settings (service role)
    const admin = createClient(sbUrl, serviceKey, { auth: { persistSession: false } });
    let serverKey = (Deno.env.get('GEMINI_API_KEY') ?? '').trim();
    let keyFrom: 'secret' | 'pengaturan' | null = serverKey ? 'secret' : null;
    let modeServer = '';
    if (!serverKey) {
      const { data: st } = await admin.from('app_settings').select('gemini').eq('id', 'global').maybeSingle();
      const gem = (st?.gemini ?? {}) as Record<string, unknown>;
      serverKey = String(gem.api_key ?? '').trim();
      modeServer = String(gem.mode ?? '');
      if (serverKey) keyFrom = 'pengaturan';
    }

    // 5a) action "info" — dipakai tombol Uji Koneksi di Pengaturan
    if (action === 'info') {
      return json(req, 200, {
        ok: true,
        role: profile.role,
        keyFrom,
        mode: modeServer || undefined,
        modelDefault: DEFAULT_MODEL,
        modelTersedia: [...MODEL_WHITELIST],
        ratePerMinute: RATE_PER_MINUTE,
      });
    }

    if (!['generate', 'json', 'chat', 'diag'].includes(action)) {
      return json(req, 400, { ok: false, error: `Action tidak dikenal: ${action}` });
    }

    if (!serverKey) {
      return json(req, 400, {
        ok: false, code: 'NO_API_KEY',
        error: 'Kunci API Gemini belum tersedia di server. Tempel API key di menu Pengaturan → AI Gemini lalu Simpan (tersimpan aman di server), atau jalankan: supabase secrets set GEMINI_API_KEY=AQ.Ab8...',
      });
    }

    // 5b) action "diag" — daftar model yang benar-benar tersedia untuk kunci ini.
    //     Dipakai tombol 🔍 Diagnosa Kunci & Model pada menu Pengaturan.
    if (action === 'diag') {
      let dresp: Response;
      try {
        dresp = await fetch(`${GEMINI_BASE}?pageSize=200`, {
          headers: { 'x-goog-api-key': serverKey },
          signal: AbortSignal.timeout(20_000),
        });
      } catch {
        return json(req, 504, { ok: false, code: 'TIMEOUT', error: 'Tidak dapat menghubungi layanan Gemini (timeout) saat diagnosa.' });
      }
      const ddata = (await dresp.json().catch(() => null)) as Record<string, unknown> | null;
      if (!dresp.ok) {
        const raw = String((ddata?.error as Record<string, unknown> | undefined)?.message ?? dresp.statusText);
        return json(req, dresp.status === 400 ? 400 : 502, {
          ok: false, code: dresp.status === 400 ? 'BAD_KEY' : 'UPSTREAM',
          error: dresp.status === 400
            ? 'Kunci API DITOLAK Google (tidak valid / belum aktif). Salin ulang kunci utuh dari Google AI Studio (awalan AQ. atau AIza) tanpa spasi, lalu Simpan.'
            : 'Layanan Gemini merespons kesalahan saat diagnosa.',
          detail: raw.slice(0, 300),
        });
      }
      const list = (ddata?.models as Record<string, unknown>[] | undefined) ?? [];
      const models = list
        .filter((m) => {
          const name = String(m.name ?? '');
          const methods = (m.supportedGenerationMethods as string[] | undefined) ?? [];
          return name.startsWith('models/gemini-') && methods.includes('generateContent');
        })
        .map((m) => ({
          id: String(m.name).replace(/^models\//, ''),
          label: String(m.displayName ?? ''),
        }));
      try {
        await admin.from('audit_log').insert({
          id: crypto.randomUUID(),
          user_email: user.email ?? null,
          user_role: profile.role,
          aksi: 'AI_CALL',
          entitas: 'gemini-proxy',
          entitas_id: 'diag',
          detail: `Diagnosa kunci (${keyFrom}): ${models.length} model generateContent tersedia`,
        });
      } catch { /* best-effort */ }
      return json(req, 200, { ok: true, keyFrom, total: models.length, models });
    }

    // 6) Susun konten untuk Gemini
    const model = resolveModel(body.model);
    const temperature = typeof body.temperature === 'number'
      ? Math.min(Math.max(body.temperature, 0), 2) : 0.4;
    const maxOutputTokens = typeof body.maxOutputTokens === 'number'
      ? Math.min(body.maxOutputTokens, 65_536) : 8_192;
    const system = clean(body.system, MAX_PROMPT_CHARS);

    const parts: Record<string, unknown>[] = [];
    const attachments = Array.isArray(body.attachments)
      ? (body.attachments as unknown[]).slice(0, MAX_ATTACHMENTS) : [];
    for (const a of attachments) {
      const o = (a ?? {}) as Record<string, unknown>;
      const mime = typeof o.mime === 'string' ? o.mime : '';
      const data = typeof o.data === 'string' ? o.data.replace(/^data:[^;]+;base64,/, '') : '';
      if (!MIME_WHITELIST.has(mime) || !data || data.length > MAX_ATTACHMENT_B64) continue;
      parts.push({ inlineData: { mimeType: mime, data } });
    }

    const contents: { role: string; parts: Record<string, unknown>[] }[] = [];
    if (action === 'chat' && Array.isArray(body.messages)) {
      for (const m of (body.messages as unknown[]).slice(-MAX_MESSAGES)) {
        const o = (m ?? {}) as Record<string, unknown>;
        const text = clean(o.text, MAX_PROMPT_CHARS);
        if (!text) continue;
        contents.push({ role: o.role === 'model' ? 'model' : 'user', parts: [{ text }] });
      }
      if (!contents.length) return json(req, 400, { ok: false, error: 'Percakapan kosong.' });
      if (parts.length) contents[contents.length - 1].parts.push(...parts);
    } else {
      const prompt = clean(body.prompt, MAX_PROMPT_CHARS);
      if (!prompt.trim()) return json(req, 400, { ok: false, error: 'Parameter "prompt" wajib diisi.' });
      contents.push({ role: 'user', parts: [...parts, { text: prompt }] });
    }

    // Parameter sampling HANYA untuk model lama — model 3.x+ menolaknya (HTTP 400).
    const generationConfig: Record<string, unknown> = {};
    if (isLegacyModel(model)) {
      generationConfig.temperature = temperature;
      generationConfig.maxOutputTokens = maxOutputTokens;
    }
    if (action === 'json') generationConfig.responseMimeType = 'application/json';

    const payload: Record<string, unknown> = { contents };
    if (Object.keys(generationConfig).length) payload.generationConfig = generationConfig;
    if (system) payload.systemInstruction = { parts: [{ text: system }] };

    // 7) Panggil Gemini (kunci lewat header — tidak pernah masuk URL/log)
    let resp: Response;
    try {
      resp = await fetch(`${GEMINI_BASE}/${encodeURIComponent(model)}:generateContent`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': serverKey },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch {
      return json(req, 504, {
        ok: false, model,
        error: 'Tidak dapat menghubungi layanan Gemini (timeout). Coba beberapa saat lagi.',
      });
    }

    const data = (await resp.json().catch(() => null)) as Record<string, unknown> | null;
    if (!resp.ok) {
      const raw = String((data?.error as Record<string, unknown> | undefined)?.message ?? resp.statusText);
      const st = resp.status;
      // Pemetaan status Google → pesan ramah + kode mesin (detail asli selalu disertakan)
      const [friendly, code] =
        (st === 400 && /api key not valid|api_key_invalid/i.test(raw))
          ? ['Kunci API DITOLAK Google (tidak valid / belum aktif). Salin ulang kunci utuh dari Google AI Studio tanpa spasi, lalu Simpan kembali di Pengaturan.', 'BAD_KEY'] as const
        : (st === 400 && /user location|location is not supported/i.test(raw))
          ? ['Wilayah jaringan server belum didukung Google Gemini API — pilih region deployment Supabase lain (mis. us-east) atau gunakan jaringan berbeda.', 'REGION'] as const
        : (st === 404 || (st === 400 && /not found|not supported|unsupported|unknown|does not exist/i.test(raw)))
          ? [`Model "${model}" tidak dikenal Google. Klik 🔍 Diagnosa Kunci & Model untuk melihat daftar model yang benar-benar tersedia untuk kunci Anda.`, 'MODEL_UNKNOWN'] as const
        : st === 429
          ? ['Kuota/batas pemakaian Gemini tercapai — tunggu sebentar lalu coba lagi (cek kuota di Google AI Studio).', 'QUOTA'] as const
        : (st === 401 || st === 403)
          ? ['Kunci API Gemini tidak memiliki izin untuk model ini. Pastikan Generative Language API aktif pada project Google Anda.', 'FORBIDDEN'] as const
        : [`Gemini menolak permintaan (HTTP ${st}).`, 'REJECTED'] as const;
      return json(req, st === 429 ? 429 : 502, {
        ok: false, error: friendly, code, detail: raw.slice(0, 300), model,
      });
    }

    const cand = (data?.candidates as Record<string, unknown>[] | undefined)?.[0];
    const cParts = ((cand?.content as Record<string, unknown> | undefined)?.parts ?? []) as Record<string, unknown>[];
    const text = cParts.map((p) => (p?.text as string | undefined) ?? '').join('').trim();
    const finish = String(cand?.finishReason ?? 'STOP');
    const usage = data?.usageMetadata ?? null;

    if (!text) {
      const blocked = finish === 'SAFETY' ||
        !!(data?.promptFeedback as Record<string, unknown> | undefined)?.blockReason;
      return json(req, 502, {
        ok: false, model, finish,
        error: blocked
          ? 'Permintaan diblokir filter keamanan Gemini — ubah kalimatnya lalu coba lagi.'
          : finish === 'MAX_TOKENS'
            ? 'Jawaban terpotong sebelum teks tercetak (batas token keluaran tercapai). Coba model lain atau sederhanakan permintaan.'
            : 'Gemini tidak mengembalikan teks.',
      });
    }

    // 8) Jejak audit (best-effort — kegagalan tidak mengganggu respons)
    const masuk = contents.reduce((acc, c) =>
      acc + c.parts.reduce((b, p) => b + String((p as { text?: string }).text ?? '').length, 0), 0);
    try {
      await admin.from('audit_log').insert({
        id: crypto.randomUUID(),
        user_email: user.email ?? null,
        user_role: profile.role,
        aksi: 'AI_CALL',
        entitas: 'gemini-proxy',
        entitas_id: model,
        detail: `action=${action}; masuk=${masuk} karakter; keluar=${text.length} karakter; kunci=${keyFrom}`,
      });
    } catch {
      /* audit bersifat best-effort */
    }

    return json(req, 200, { ok: true, text, model, finish, usage });
  } catch (e) {
    return json(req, 500, {
      ok: false,
      error: 'Kesalahan tak terduga pada server AI.',
      detail: String((e as Error)?.message ?? e).slice(0, 300),
    });
  }
});

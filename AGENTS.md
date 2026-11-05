# DracinManager

Rails 8.1 + Devise + PostgreSQL. Tanpa Turbo/Stimulus (importmap hanya pin `application`), jadi
pakai `button_to` untuk request non-GET (jangan `link_to ... turbo_method:`).

## Ruby
- `.ruby-version` = 3.2.3, hanya ada sebagai Ruby sistem (`/usr/bin/ruby`, gem di `/var/lib/gems/3.2.0`).
- Dev lokal: `RBENV_VERSION=3.2.9 bin/rails ...` (rbenv). Production: `RBENV_VERSION=system`.
- Setelah menambah gem, jalankan `bundle install` untuk KEDUA Ruby, kalau tidak production gagal boot.

## Production
- systemd `dracinmanager.service` (puma unix socket) + nginx `dracin.aridaev.com`, `RAILS_ENV=production`.
- Perubahan view/CSS tidak terlihat sampai `assets:precompile` + restart. Pakai `bin/deploy`.
- Log: `journalctl -u dracinmanager -n 50`.

## Dev
- `RBENV_VERSION=3.2.9 bin/rails server -p 3055 -b 127.0.0.1`
- Dev dan production berbagi `public/assets/.manifest.json`, jadi Propshaft di dev memakai resolver STATIS:
  setelah menambah file CSS/JS baru, jalankan `assets:precompile` (lihat bin/deploy) lalu restart server dev.
- Di dalam view, tulis `::Template::V1::...` (tanpa `::` akan resolve ke `ActionView::Template`).
- Lint: `RBENV_VERSION=3.2.9 bin/rubocop`
- Belum ada test suite (dibuat dengan `--skip-test`). Verifikasi via curl/browser.

## Struktur
- Layout bersama: `app/views/shared/_auth_card.html.erb` (halaman Devise) dan `_app_shell.html.erb`
  (halaman setelah login). Dipakai via `render layout: "shared/...", locals: { title:, subtitle: }`.
- I18n: default `id`, tersedia `en`. Teks di `config/locales/{id,en}.yml`, Devise di `devise.{en,id}.yml`.
  Locale dipilih via `?locale=xx` dan disimpan di session (`ApplicationController#switch_locale`).
- DracinAPI (realita, BUKAN docs dracinapi.com): hub `https://api.dramabuzz.sbs/api/status?key=KEY` hanya memberi
  daftar 44 platform (status active/maintenance/coming, logo, url docs). Konten tiap platform ada di host sendiri
  (`*.goodbos.online`, field `api`) dengan skema API BERBEDA-BEDA; auth biasanya header `x-token: KEY`, sebagian `?code=KEY`.
  - `app/services/dracin_api/http.rb` GET JSON + error classes; `client.rb` = hub (status saja).
  - `app/services/dracin_api/adapters/*.rb` = satu adapter per platform (kontrak: home/search/detail/episodes/play →
    struct `DracinApi::Catalog`). Registry di `adapters.rb`. Tambah platform baru = tulis adapter + daftarkan di REGISTRY.
    Sudah ada (24): cubetv, dramabite (path tanpa /api: /home /module /drama/:cid /episodes/:cid /play/:cid/:vid), dramabox, dramawave, flextv, flickreels (x-token, /batchload/:id, tanpa search), freereels, goodshort (tanpa /api, /batchload/:id, HLS via host DracinAPI /hls/ + ?code=, rate limit 60/menit), melolo, microdrama, moboreels, netshort (lang `id`→`in`),
    pinedrama (tanpa /api, /episode?id=&ep=, MP4 tiktokcdn), reelbuzz, reelife, reelshort (path tanpa /api: /home /detail/:id /allepisodes/:id, lang `in`, ?code=), serialplus, shortmax, shortswave (lang `id`→`in`), stardusttv (lang `id_ID`, path non-/api), starshort,
    storyreel, vibeshort, vigloo. Host bersama `drakula.goodbos.online` = starshort/freereels/microdrama (+fundrama yang mati).
    Auth: `?code=KEY` untuk shortmax/serialplus/moboreels/melolo/reelbuzz/starshort/microdrama/freereels/shortswave/flextv/cubetv;
    `x-token` untuk dramabox/dramawave/netshort/vibeshort/storyreel/vigloo/stardusttv; reelife: katalog x-token, play `?code=`.
    Flag lock dari API (dramabox isLocked/isCharge, serialplus lock, reelife isCharge, cubetv lockStatus) adalah paywall aplikasi asli —
    URL video tetap valid, jadi episode dianggap terkunci hanya jika API tidak memberi URL. DramaBox: `/dubbed?classify=terbaru|terpopuler`.
    FlexTV: DracinAPI hanya membuka 5–7 episode pertama per judul. FreeReels: search minimal 2 kata (adapter menambah " drama").
    MicroDrama: tidak ada daftar episode → dibangun dari total_episodes. ShortsWave: play = URL m3u8 ke host DracinAPI dengan ?code=.
    Vigloo: stream HLS butuh signed cookie CloudFront → diputar lewat proxy `Template::V1::StreamsController` (`/template/v1/stream/:sid?u=`).
    Reelife host lambat (~6 dtk per panggilan pertama). Storyreel: API mengembalikan 0 item (kosong, bukan error).
    Tidak bisa (dicek ulang 29 Okt 2026 via api.html masing-masing): fundrama (backend 37.60.252.87:5389 refused),
    bilitv (origin 47.236.26.63 timeout), dramanova (openAPI auth error), bonustv (CF 502), flareflow (CF 1015), raptdrama (detail ""/episodes []),
    happyshort (play selalu EP 1 + CDN 403 untuk semua header), velolo (semua endpoint "null"), dotdrama & rapidtv (field acak, CDN 403;
    kontennya = MicroDrama yang sudah ada). Docs per-platform: host drakula `/<slug>-api.html`, lainnya `/api.html` atau `/` (JSON).
    PENTING: banyak host memakai path TANPA prefix /api dan rate limit 60 req/menit per code (ban 2 menit) — baca api.html dulu,
    jangan brute-force path.
   - Konfigurasi di tabel `settings` (`Setting.dracin_api_base_url`, `Setting.dracin_api_key`, value terenkripsi
    via Active Record Encryption — key ada di `config/credentials.yml.enc`).
- Provider: `app/models/provider.rb`, 44 slug di `Provider::CATALOG`, di-seed oleh `Provider.sync_catalog!`;
  `Provider.apply_status!` menyimpan status/logo/api_url dari hub. `Provider.supported` = punya adapter.
  Admin enable/disable di `/admin/providers`, pengaturan API di `/admin/settings/edit`.
- Cache dev = memory_store per proses: `Rails.cache.clear` via runner TIDAK membersihkan cache server dev; restart server.
  Cek `tmp/pids/server.pid` kalau `rails server` bilang "A server is already running".
- Template publik `/template/v1` (tanpa login): controller `app/controllers/template/v1/*`, layout
  `layouts/template/v1`, CSS `app/assets/stylesheets/template/v1.css`, player HLS via `hls.js` (vendored importmap).
  Data lewat `DracinApi::Catalog` (normalisasi + cache 10 menit, play 5 menit). TIDAK ada data demo: error API → `rescue_from DracinApi::Error`
  di `Template::V1::BaseController` → halaman `shared/api_error` (HTTP 502).
  Hanya provider `enabled` yang muncul di pemilih provider.

## Template v1 — performa & pemutar (Okt 2026)
- Adapter memanggil API paralel lewat `Base#concurrently` (thread + `Rails.application.executor.wrap`). Jangan panggil
  `I18n.t` di dalam blok thread (locale thread-local) — judul section diambil di luar blok.
- `Catalog#fetch`: cache 30 mnt + `race_condition_ttl`; salinan "stale" 6 jam dipakai otomatis saat upstream timeout
  (`[DracinApi] ... pakai cache lama` di log). Host `*.goodbos.online` sering lambat 10–25 dtk, itu sumber "web berat", bukan kode.
- Puma: `RAILS_MAX_THREADS=5` via drop-in `/etc/systemd/system/dracinmanager.service.d/threads.conf` (RAM server ~90%, jangan tambah worker).
- `Catalog::Stream#sources` = [{label:, url:}] semua varian kualitas → dropdown "HD" di watch; HLS tunggal memakai level hls.js.
- Subtitle lewat proxy same-origin `/template/v1/subtitle?t=<MessageVerifier token>` (`Template::V1::SubtitlesController`):
  CORS + konversi SRT→VTT, token 6 jam, tanpa token → 403. Adapter memakai `Base#subtitle(lang:, url:, label:)`.
- Home: 2 section pertama dirender langsung, sisanya `<template>` + IntersectionObserver (`data-lazy-slot`), per section
  maksimal 18 kartu + tombol "Muat lagi" (`data-load-more`). Kartu/hero/poster detail bisa diklik (overlay → detail, `.card-play` → EP 1).
- Tidak ada tombol "Masuk" di template publik; link "Kelola" hanya muncul bila admin sudah login.
- Urutan provider di template = `Provider.by_latency` (providers.last_latency_ms ASC, NULL di belakang). Nilai diisi oleh
  `bin/rails dracin:latency[N]` (median N sampel home tanpa cache, paralel), dijadwalkan cron tiap 30 menit
  (`/etc/cron.d/dracin-latency`, log `log/latency.log`). Solid Queue TIDAK berjalan di server ini, jadi recurring.yml tidak dipakai.
- Admin shell v2 (`shared/_app_shell`): sidebar + topbar, `content_for :page_actions` untuk tombol di topbar, ikon via
  `dm_icon(name)` (ApplicationHelper::ICONS). Kerapatan compact/comfortable = `<html data-density>` dari localStorage `dm_density`;
  variabel CSS di blok "Admin shell v2" (application.css). Mobile <900px: sidebar jadi drawer (checkbox #nav-toggle).
- Sumber API: model `ApiSource` (base_url, auth_mode header_x_token|query_code|query_key|bearer|none, api_key terenkripsi,
  status_path, is_default). `Setting.dracin_api_*` kini shim ke ApiSource.default. Admin: /admin/api_sources (tes, sinkron,
  jadikan default). /admin/settings/edit hanya redirect. Locale tambahan di config/locales/admin2.{id,en}.yml.
- Provider punya api_source_id, auth_mode, adapter_key, api_key, notes, custom. Key efektif: provider → sumber → Setting
  (`Provider#effective_api_key`). `adapter_key` memilih adapter berbeda dari slug (penyedia kustom = host lain dengan skema
  adapter yang ada; dibuat di /admin/custom_providers). `Base#get` menghormati `effective_auth_mode`; adapter yang
  meng-override `get` sendiri (mode ?code=) tidak terpengaruh.
- Codec: ReelShort memberi tiap kualitas dalam 2 versi — HEVC (`.../video/...-video-sd.m3u8`, hvc1) dan H.264 (`/vod-.../...-ld.m3u8`);
  master "0p" hanya berisi varian HEVC → browser desktop cuma dapat suara. Adapter memilih H.264 (`h264?`), HEVC hanya fallback.
  Melolo: semua kualitas MP4 **HEVC + CENC terenkripsi** (encv/tenc/senc, key/kid di qualityList) — tidak bisa diputar browser
  biasa tanpa DRM/decrypt; biarkan apa adanya. Provider lain yang dicek (28 Okt 2026) semuanya H.264.
  Periksa codec: ambil segmen TS pertama → PMT stream_type 0x1b=H.264, 0x24=HEVC; fMP4/MP4 → box avc1 vs hvc1.

## Domain kustom instance (routing)
- Nginx: `/etc/nginx/sites-available/dracin-instances` meng-include `/etc/nginx/dracin_domains.conf` (baris `server_name`), yang ditulis otomatis oleh `NginxDomains.sync!` (callback `Domain#sync_edge`) lalu `systemctl reload nginx`. Jangan edit manual.
- Rails: `InstanceHost.resolve(env)` memetakan Host → Instance (cache memori 60 dtk; `www.` dibuang). `config/routes.rb` memakai blok `template_v1_routes` dua kali: di root dengan `constraints InstanceHost::Constraint.new("v1")` (helper `site_*_path`) dan di `/template/v1` (helper `template_v1_*_path`).
- `Template::V1::InstanceAware` (concern) menimpa `template_v1_*_path` → `site_*_path` saat di domain instance, menyediakan `current_instance` + helper branding `tv1_*`, mode pratinjau `?preview_instance=<nama>` (login saja; `=0` keluar), dan halaman "dijeda" (503) untuk instance paused/disabled.
- Template baru (v2): tambah entri `Instance::TEMPLATES`, blok constraint baru di routes, dan include concern serupa.
- Logo provider dari hub mengirim `Cross-Origin-Resource-Policy: same-origin` → dipakai proxy `/provider_logos/:slug` (`ProviderLogosController`, cache 1 hari, membuka bungkus `<svg><image data:…>`).
- Cron `/etc/cron.d/dracin-domains` tiap 15 menit: `dracin:domains_refresh` mengaktifkan domain yang zone-nya sudah aktif di CF.
- Pembatasan negara per domain: `Domain#set_geo!("ID")` → WAF custom rule di zone (`CloudflareClient#set_geo_allow_only`,
  phase `http_request_firewall_custom`, rule ditandai description `dracinmanager-geo`, bot terverifikasi tetap lolos);
  `set_geo!(nil)` menghapus rule kita saja. Tombol di kartu Domain (`POST admin/instances/:id/domains/:id/geo?country=ID`).
  Ruleset kosong dikembalikan CF TANPA key `rules` → selalu `Array(rs["rules"])`. Origin masih bisa diakses langsung via IP VPS
  (nginx tidak membatasi ke IP Cloudflare), jadi geo-block hanya berlaku lewat CF.

## Hub Mola API (api.molatv.id, Okt 2026)
- ApiSource slug `mola` (base_url api.molatv.id, auth header `X-API-TOKEN`; field auth_mode diisi `bearer` hanya formalitas).
  `Client#status` → `mola_status`: validasi `/api/validate-token?token=` + daftar platform dari katalog docs → provider
  dengan `adapter_key: "mola"`, dibuat NONAKTIF (quota). Sync ulang: tombol Sinkron di /admin/api_sources.
- Adapter GENERIK `DracinApi::Adapters::Mola`: aksi+parameter tiap platform dibaca dari `const ALL_PLATFORMS` di HTML
  `/docs/<slug>?token=` (cache 24 jam), cadangan `config/mola_platforms.json` (88 platform, 666 endpoint). Respons
  dinormalisasi lewat daftar kunci lazim (ID_KEYS/TITLE_KEYS/...). Teruji: vibeshortv2 (data.data[]), dramaboxv2 (books[]/bookName/
  chapterIndex), joyreels (books[]/playlet_id/tags[{name}]). Platform lain belum diuji satu per satu — kalau ada yang
  gagal, tambahkan kunci ke konstanta tsb, jangan bikin adapter baru.
- Bahasa katalog stateful per token (`set_language`) → dipanggil 1x/hari per platform (`ensure_language!`).
- KUOTA token tester 100 request/hari (`validate-token` → requests_today). Karena itu: `Mola::CACHE_TTL` 6 jam
  (Catalog menghormati `adapter.class::CACHE_TTL`), beranda maks `HOME_MAX`=2 section, dan rake `dracin:latency`
  MELEWATI provider mola. Jangan aktifkan banyak provider Mola sebelum token diupgrade.
- Fallback: provider DracinAPI → Vorta → Mola (`Adapters.fallback_for`); provider hub → adapter natif slug sama bila ada.

## Auto posting Instagram (Okt 2026)
- Halaman `/admin/instances/:id/auto_posts` = tabel, satu form `PATCH bulk_update` (`auto_posts[<id>][field]`); hanya baris
  yang `changed?` disimpan. Cookie/judul manual/teks tetap/log ada di baris Detail (`<tr class="ap-detail" hidden>`).
  Tombol ⇩ di header menyalin nilai baris pertama ke semua baris (client-side).
- Cookie mati: `AutoPost#record_auth_failure!` — setelah `AUTH_FAILS_TO_DISABLE` (2) AUTH gagal berturut-turut akun
  dinonaktifkan (`enabled=false, next_run_at=nil, auth_failed_at`), tampil "Cookie mati"; `cookie=` dengan nilai baru mereset
  `auth_failed_at`. Uji controller tanpa browser: `Rack::Test` + `Warden.test_mode!` + `ActionController::Base.allow_forgery_protection = false`
  di `bin/rails runner`.

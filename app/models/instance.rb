# Instance: profil branding situs (ikon, logo, judul, meta, footer, navbar) dengan nama acak unik.
# Semua pengaturan disimpan di kolom settings (jsonb) — lihat SETTING_KEYS dan nav_items.
class Instance < ApplicationRecord
  NAME_LENGTH = 10
  NAME_ALPHABET = ("a".."z").to_a + ("2".."9").to_a # tanpa 0/1 agar tidak tertukar dengan o/l

  # Kunci pengaturan skalar (string). Navbar disimpan terpisah sebagai array di settings["nav_items"].
  SOCIALS = {
    "instagram" => { name: "Instagram", placeholder: "https://instagram.com/…", color: "#e1306c" },
    "tiktok"    => { name: "TikTok",    placeholder: "https://tiktok.com/@…",   color: "#000000" },
    "facebook"  => { name: "Facebook",  placeholder: "https://facebook.com/…",  color: "#1877f2" },
    "youtube"   => { name: "YouTube",   placeholder: "https://youtube.com/@…",  color: "#ff0000" },
    "x"         => { name: "X / Twitter", placeholder: "https://x.com/…",       color: "#111111" },
    "telegram"  => { name: "Telegram",  placeholder: "https://t.me/…",          color: "#229ed9" },
    "whatsapp"  => { name: "WhatsApp",  placeholder: "https://wa.me/628…",      color: "#25d366" }
  }.freeze
  # Halaman bawaan template (untuk pilihan cepat navbar/footer).
  PAGES = [ [ "/", "Beranda" ], [ "/genre", "Semua genre" ], [ "/latest", "Terbaru" ], [ "/search", "Cari" ] ].freeze
  # Teks yang bisa punya varian per bahasa: disimpan sebagai "<key>_<locale>" (mis. seo_content_en);
  # locale bawaan (:id) memakai key polos. Baca lewat #localized(key).
  LOCALIZED_KEYS = %w[site_title meta_description seo_content footer_text footer_about ads_title ads_text ads_button_text].freeze
  EXTRA_LOCALES = (I18n.available_locales - [ I18n.default_locale ]).map(&:to_s).freeze
  SETTING_KEYS = (%w[app_name site_title meta_description icon_url logo_url copyright footer_text footer_about template watermark_url watermark_position watermark_opacity watermark_size footer_show_providers footer_show_powered seo_content seo_keywords seo_generated_at seo_job_status seo_job_info seo_job_at protect_source gsc_verification bing_verification indexnow_key indexnow_auto indexnow_last ads_enabled ads_duration ads_title ads_text ads_image_url ads_button_text ads_button_url amp_enabled amp_google_redirect members_enabled adfree_site_url] + SOCIALS.keys.map { |k| "social_#{k}" } + LOCALIZED_KEYS.product(EXTRA_LOCALES).map { |k, l| "#{k}_#{l}" }).freeze
  WATERMARK_SIZES = %w[small medium large xlarge].freeze
  WATERMARK_POSITIONS = %w[top-center top-left top-right bottom-left bottom-right].freeze
  include InstanceTheme
  # Template situs publik yang tersedia. Tambahkan entri baru di sini saat template berikutnya dibuat
  # (key = folder app/views/template/<key>, path = root route-nya).
  TEMPLATES = {
    "v1" => { name: "Template v1 — Klasik", description: "Katalog drama pendek: hero rail, section per penyedia, navbar atas, gelap/terang.", path: "/template/v1", status: "stable", accent: "#e10037", bg: "#090a0d" },
    "v2" => { name: "Template v2 — Cinema", description: "Gaya Dracinema: sidebar kiri, hero besar, rail geser, ranking 'Paling Dicari', tema plum gelap.", path: "/template/v2", status: "stable", accent: "#ff2357", bg: "#241c29" },
    "v3" => { name: "Template v3 — Mango", description: "Gaya MangoTV: tema terang oranye, tab kanal, banner swiper, modul kartu landscape + ranking.", path: "/template/v3", status: "stable", accent: "#ff5f00", bg: "#ffffff" },
    "v4" => { name: "Template v4 — Vidio", description: "Gaya Vidio: tema gelap merah, header satu baris, hero full-width dengan thumbnail, rail landscape, Top 10 angka besar, rail short drama portrait.", path: "/template/v4", status: "stable", accent: "#e4002b", bg: "#0b0b0d" }
  }.freeze
  DEFAULT_TEMPLATE = "v1".freeze
  DEFAULT_NAV = [
    { "label" => "Beranda", "url" => "/", "enabled" => true },
    { "label" => "Genre", "url" => "/genre", "enabled" => true },
    { "label" => "Terbaru", "url" => "/latest", "enabled" => true }
  ].freeze

  enum :status, { active: 0, paused: 1, disabled: 2 }, default: :active

  belongs_to :created_by, class_name: "User", optional: true
  has_many :domains, dependent: :destroy
  has_many :members, dependent: :destroy
  has_many :deposit_requests, dependent: :destroy
  has_many :auto_posts, dependent: :destroy
  has_many :visits, dependent: :delete_all

  scope :owned_by, ->(user) { where(created_by_id: user.id) }
  def primary_domain = domains.active.first || domains.first

  validates :name, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :icon_url, :logo_url, format: { with: %r{\Ahttps?://|\A/}i, allow_blank: true }
  validates :template, inclusion: { in: TEMPLATES.keys }, allow_blank: true
  validates :watermark_url, format: { with: %r{\Ahttps?://|\A/}i, allow_blank: true }
  validates :watermark_position, inclusion: { in: WATERMARK_POSITIONS }, allow_blank: true
  validates :watermark_size, inclusion: { in: WATERMARK_SIZES }, allow_blank: true
  validates :watermark_opacity, numericality: { only_integer: true, greater_than_or_equal_to: 10, less_than_or_equal_to: 100, message: "harus 10–100" }, allow_blank: true

  # Logo watermark di atas video: pakai watermark_url, fallback ke logo lalu icon.
  # Iklan pra-tayang: overlay beberapa detik sebelum video diputar (teks + tombol/link, bisa diatur per instance).
  ADS_DURATION_RANGE = (3..30)
  def members_enabled? = members_enabled == "1"
  # Paket deposit: beberapa pilihan {price (teks), days}. Fallback ke adfree_price/adfree_days lama.
  def adfree_packages
    raw = settings["adfree_packages"]
    list = raw.is_a?(Array) ? raw.map { |p| { "price" => p["price"].to_s.strip, "days" => p["days"].to_i } }.select { |p| p["price"].present? && p["days"] > 0 } : []
    list.presence || [ { "price" => settings["adfree_price"].presence || "Rp 50.000", "days" => (settings["adfree_days"].presence || 30).to_i.clamp(1, 3650) } ]
  end

  def adfree_packages=(raw)
    arr = raw.is_a?(Hash) ? raw.sort_by { |k, _| k.to_s.match?(/\A\d+\z/) ? k.to_i : 10**9 }.map(&:last) : Array(raw)
    items = arr.map { |p| p = p.respond_to?(:to_h) ? p.to_h.stringify_keys : {}; { "price" => p["price"].to_s.strip.first(40), "days" => p["days"].to_i.clamp(0, 3650) } }
                .select { |p| p["price"].present? && p["days"] > 0 }.first(12)
    self.settings = settings.merge("adfree_packages" => items)
  end

  def adfree_package(idx) = idx.to_s.match?(/\A\d+\z/) ? adfree_packages[idx.to_i] : nil
  def adfree_days  = adfree_packages.first["days"]
  def adfree_price = adfree_packages.first["price"]
  def adfree_site_href = adfree_site_url.to_s.strip.then { |u| u.match?(%r{\Ahttps?://}i) ? u : nil }
  def ads_enabled? = ads_enabled == "1"
  def ads_seconds = ads_duration.to_i.clamp(ADS_DURATION_RANGE.min, ADS_DURATION_RANGE.max).then { |n| ads_duration.present? ? n : 6 }
  def ads_active? = ads_enabled? && (ads_title.present? || ads_text.present? || ads_image_url.present?)
  def ads_button_href = ads_button_url.to_s.strip.then { |u| u.match?(%r{\Ahttps?://}i) ? u : nil }
  # Halaman AMP (/amp): aktif bila dicentang; isinya dari pengaturan iklan (banner, tombol login).
  def amp_enabled? = amp_enabled == "1"
  def amp_google_redirect? = amp_enabled? && amp_google_redirect == "1"

  def watermark_src = watermark_url.presence || logo_url.presence || icon_url.presence
  def watermark_pos = watermark_position.presence || "top-center"
  def watermark_alpha = (watermark_opacity.presence || 70).to_i
  def watermark_size_key = watermark_size.presence || "medium"
  def footer_show_providers? = settings["footer_show_providers"] != "0"
  def footer_show_powered? = settings["footer_show_powered"] != "0"
  def protect_source? = settings["protect_source"] != "0"
  def indexnow_auto? = settings["indexnow_auto"] != "0"
  def primary_host = domains.active.first&.hostname
  def ensure_indexnow_key
    self.settings = settings.merge("indexnow_key" => SecureRandom.hex(16)) if settings["indexnow_key"].blank?
  end
  # Kirim ke IndexNow di thread terpisah (tanpa worker Solid Queue) saat instance dengan domain aktif disimpan.
  # Status job Generate SEO. Dianggap masih berjalan maks. 10 menit (jaga-jaga bila worker mati).
  def seo_job_running?
    return false unless seo_job_status == "running"
    at = (Time.zone.parse(seo_job_at.to_s) rescue nil)
    at.present? && at > 10.minutes.ago
  end

  def mark_seo_job!(status, info = nil)
    update_columns(settings: settings.merge("seo_job_status" => status, "seo_job_info" => info.presence, "seo_job_at" => Time.current.iso8601), updated_at: Time.current)
  end

  def submit_indexnow_later
    return unless indexnow_auto? && active? && (host = primary_host)
    Thread.new { Rails.application.executor.wrap { IndexNowSubmitter.new(self, host: host).call rescue nil } }
  end
  def seo_keyword_list = seo_keywords.to_s.split(/[,\n;]+/).map(&:strip).compact_blank.uniq.first(12)
  def seo_word_count = ActionController::Base.helpers.strip_tags(seo_content.to_s).split(/\s+/).size
  def social_links = SOCIALS.filter_map { |k, s| (u = public_send("social_#{k}")).present? ? { "key" => k, "name" => s[:name], "url" => u, "color" => s[:color] } : nil }

  # Tautan footer: array [{label, url, new_tab}] di settings["footer_links"]. Menerima juga
  # format teks lama "Label | /url" per baris.
  def footer_link_items
    v = settings["footer_links"]
    v.is_a?(Array) ? v : footer_text_lines(v).map { |l, u| { "label" => l, "url" => u } }
  end
  def footer_links=(raw)
    items = raw.is_a?(String) ? footer_text_lines(raw).map { |l, u| { "label" => l, "url" => u } } : normalize_nav(raw, depth: 1)
    self.settings = settings.merge("footer_links" => items)
  end
  def footer_links = footer_link_items

  before_validation :assign_random_name, on: :create
  before_validation :ensure_indexnow_key
  after_commit :submit_indexnow_later, on: :update

  scope :ordered, -> { order(created_at: :desc) }

  # Akses settings[key] sebagai atribut virtual: instance.app_name / instance.app_name = ...
  SETTING_KEYS.each do |key|
    define_method(key) { settings[key] }
    define_method("#{key}=") { |v| self.settings = settings.merge(key => v.to_s.strip.presence) }
  end

  # Nilai teks sesuai bahasa aktif: "<key>_<locale>" bila terisi, jika tidak jatuh ke key polos.
  def localized(key, locale = I18n.locale)
    key = key.to_s; loc = locale.to_s
    return settings[key] if loc == I18n.default_locale.to_s || !EXTRA_LOCALES.include?(loc)
    settings["#{key}_#{loc}"].presence || settings[key]
  end

  def localized_key(key, locale = I18n.locale)
    loc = locale.to_s
    EXTRA_LOCALES.include?(loc) ? "#{key}_#{loc}" : key.to_s
  end

  # Kode verifikasi GSC/Bing: terima kode polos atau seluruh tag <meta ... content="...">.
  def gsc_verification=(v)
    s = v.to_s.strip; s = $1 if s =~ /content=["']([^"']+)["']/
    self.settings = settings.merge("gsc_verification" => s.presence)
  end
  def bing_verification=(v)
    s = v.to_s.strip; s = $1 if s =~ /content=["']([^"']+)["']/
    self.settings = settings.merge("bing_verification" => s.presence)
  end

  def nav_items
    items = settings["nav_items"]
    items.is_a?(Array) && items.any? ? items : DEFAULT_NAV.map(&:dup)
  end

  # Menerima array/hash dari form: [{label:, url:, enabled:, children: [{label:, url:, enabled:}]}].
  # Baris tanpa label & url dibuang (termasuk sub-menu kosong).
  def nav_items=(raw)
    self.settings = settings.merge("nav_items" => normalize_nav(raw, depth: 0))
  end

  def nav_items_flat
    nav_items.flat_map { |it| [ it ] + Array(it["children"]) }
  end

  def self.random_name
    loop do
      candidate = Array.new(NAME_LENGTH) { NAME_ALPHABET.sample(random: SecureRandom) }.join
      return candidate unless exists?(name: candidate)
    end
  end

  def display_name = title.presence || app_name.presence || name
  def template_key = template.presence || DEFAULT_TEMPLATE
  def template_info = TEMPLATES[template_key] || TEMPLATES[DEFAULT_TEMPLATE]
  def template_path = template_info[:path]
  # URL publik: domain aktif pertama; jika belum ada, pratinjau branding di host utama.
  def public_url
    d = domains.active.first
    d ? "https://#{d.hostname}" : "#{template_path}?preview_instance=#{name}"
  end
  def footer_link_list = footer_link_items.map { |it| [ it["label"], it["url"] ] }

  private
  def normalize_nav(raw, depth:)
    list = raw.is_a?(Hash) ? raw.values : Array(raw)
    list.filter_map do |it|
      it = it.to_h.stringify_keys
      label = it["label"].to_s.strip; url = it["url"].to_s.strip
      children = depth.zero? ? normalize_nav(it["children"], depth: 1) : []
      next if label.blank? && url.blank?
      item = { "label" => label, "url" => url.presence || "#", "enabled" => ActiveModel::Type::Boolean.new.cast(it["enabled"]) != false }
      item["new_tab"] = true if ActiveModel::Type::Boolean.new.cast(it["new_tab"])
      item["children"] = children if children.any?
      item
    end
  end

  def assign_random_name
    self.name = self.class.random_name if name.blank?
  end

  # "Label | /url" per baris → [[label, url]]
  def footer_text_lines(text)
    text.to_s.lines.filter_map { |l| a, b = l.split("|", 2).map { |x| x.to_s.strip }; [ a, b.presence || "#" ] if a.present? }
  end
end

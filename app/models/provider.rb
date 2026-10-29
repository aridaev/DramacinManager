class Provider < ApplicationRecord
  enum :category, { short_drama: 0, chinese_drama: 1 }, default: :short_drama

  ONLINE_STATUSES = %w[online active].freeze

  # Daftar platform DracinAPI (sumber: GET https://api.dramabuzz.sbs/api/status).
  # Urutan mengikuti respons hub. Field api_url/logo_url diisi saat sinkron status.
  CATALOG = [
    [ "StarShort", "starshort", :short_drama ],
    [ "FlexTV", "flextv", :short_drama ],
    [ "DramaBite", "dramabite", :short_drama ],
    [ "FreeReels", "freereels", :short_drama ],
    [ "FunDrama", "fundrama", :short_drama ],
    [ "MicroDrama", "microdrama", :short_drama ],
    [ "Vigloo", "vigloo", :short_drama ],
    [ "Reelala", "reelala", :short_drama ],
    [ "BiliTV", "bilitv", :chinese_drama ],
    [ "DramaBox", "dramabox", :short_drama ],
    [ "DramaWave", "dramawave", :short_drama ],
    [ "NetShort", "netshort", :short_drama ],
    [ "iDrama", "idrama", :short_drama ],
    [ "ShortMax", "shortmax", :short_drama ],
    [ "GoodShort", "goodshort", :short_drama ],
    [ "Melolo", "melolo", :short_drama ],
    [ "Velolo", "velolo", :short_drama ],
    [ "ReelShort", "reelshort", :short_drama ],
    [ "FlickReels", "flickreels", :short_drama ],
    [ "Stardusttv", "stardusttv", :short_drama ],
    [ "Serial+", "serialplus", :short_drama ],
    [ "DotDrama", "dotdrama", :short_drama ],
    [ "RapidTV", "rapidtv", :short_drama ],
    [ "ShortsWave", "shortswave", :short_drama ],
    [ "DramaNova", "dramanova", :short_drama ],
    [ "CubeTV", "cubetv", :short_drama ],
    [ "ReelBuzz", "reelbuzz", :short_drama ],
    [ "FlareFlow", "flareflow", :short_drama ],
    [ "MoboReels", "moboreels", :short_drama ],
    [ "HappyShort", "happyshort", :short_drama ],
    [ "Reelife", "reelife", :short_drama ],
    [ "PineDrama", "pinedrama", :short_drama ],
    [ "Anyreel", "anyreel", :short_drama ],
    [ "RaptDrama", "raptdrama", :short_drama ],
    [ "BonusTV", "bonustv", :short_drama ],
    [ "MiniTV", "minitv", :short_drama ],
    [ "Gold Drama", "golddrama", :short_drama ],
    [ "IQIYI", "iqiyi", :chinese_drama ],
    [ "Bstation", "bstation", :chinese_drama ],
    [ "Joyreels", "joyreels", :short_drama ],
    [ "KalosTV", "kalostv", :short_drama ],
    [ "Vibeshort", "vibeshort", :short_drama ],
    [ "TopDrama", "topdrama", :short_drama ],
    [ "Storyreel", "storyreel", :short_drama ]
  ].freeze

  belongs_to :api_source, optional: true

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+\z/ }

  scope :ordered, -> { order(:position, :id) }
  # Tercepat dulu; provider tanpa pengukuran (NULL) di belakang, lalu posisi hub.
  scope :by_latency, -> { order(Arel.sql("last_latency_ms IS NULL, last_latency_ms ASC, position ASC, id ASC")) }
  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :supported, -> { where(slug: DracinApi::Adapters.supported_slugs).or(where(adapter_key: DracinApi::Adapters.supported_slugs)) }

  def self.sync_catalog!
    CATALOG.each_with_index do |(name, slug, category), index|
      provider = find_or_initialize_by(slug: slug)
      provider.name = name if provider.new_record?
      provider.assign_attributes(category: category, position: index + 1)
      provider.save!
    end
  end

  # entries: array `platforms` dari /api/status → { id, name, status, logo, api }
  # (kompatibel juga dengan bentuk lama { slug, status, latency, lastChecked }).
  def self.apply_status!(entries, source: nil)
    now = Time.current
    count = 0
    Array(entries).each_with_index do |entry, index|
      slug = (entry["id"] || entry["slug"]).to_s
      next if slug.blank?
      provider = find_or_initialize_by(slug: slug)
      # Hub lain (mis. Vorta) hanya mengambil alih provider baru atau yang belum punya adapter; provider yang sudah
      # jalan lewat sumber lain dibiarkan (hub kedua menjadi cadangan lewat Adapters.fallback_for).
      takeover = entry["adapter"].present? && (provider.new_record? || !provider.supported?)
      owned = provider.new_record? || provider.api_source.nil? || provider.api_source == source
      next unless owned || takeover
      if takeover
        provider.adapter_key = entry["adapter"]
        provider.api_source = source if source
      end
      provider.name = entry["name"].presence || slug.titleize if provider.new_record? || entry["name"].present?
      provider.position = (source && !source.is_default? ? Provider.maximum(:position).to_i : 0) + index + 1 if provider.new_record?
      provider.last_status = entry["status"].to_s.presence
      provider.last_latency_ms = entry["latency"]
      provider.last_checked_at = entry["lastChecked"].present? ? (Time.zone.parse(entry["lastChecked"]) || now) : now
      provider.api_url = entry["api"] if entry.key?("api")
      provider.logo_url = entry["logo"] if entry.key?("logo")
      provider.api_source ||= source if source
      provider.save!
      count += 1
    end
    count
  end

  # Key efektif: key khusus provider → key sumber API → key default (Setting).
  def effective_api_key = api_key.presence || api_source&.api_key.presence || Setting.dracin_api_key
  def effective_auth_mode = auth_mode.presence || api_source&.auth_mode.presence
  def adapter_slug = adapter_key.presence || slug

  def online?     = ONLINE_STATUSES.include?(last_status)
  def offline?    = last_status.present? && !online?
  def supported?  = DracinApi::Adapters.supported?(adapter_slug)
end

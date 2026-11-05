# Domain kustom untuk instance. Saat dibuat, zone Cloudflare dibuat otomatis (Domain#provision!),
# nameserver CF disimpan agar user mengarahkan NS domainnya ke sana; SSL Flexible dan record A/CNAME ke IP VPS diset.
class Domain < ApplicationRecord
  HOSTNAME_RE = /\A(?=.{4,253}\z)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}\z/

  enum :status, { pending_ns: 0, active: 1, error: 2, removed: 3 }, default: :pending_ns

  belongs_to :instance

  validates :hostname, presence: true, uniqueness: true, format: { with: HOSTNAME_RE, message: "bukan nama domain yang valid" }
  before_validation { self.hostname = hostname.to_s.strip.downcase.sub(%r{\Ahttps?://}, "").sub(/\Awww\./, "").sub(%r{/.*\z}, "") }

  scope :ordered, -> { order(created_at: :desc) }
  scope :servable, -> { where(status: [ statuses[:active], statuses[:pending_ns] ]) }

  after_commit :sync_edge, on: [ :create, :update, :destroy ]

  def self.find_for_host(host)
    h = host.to_s.downcase.sub(/\Awww\./, "")
    servable.find_by(hostname: h)
  end

  def nameservers = Array(cf_nameservers)

  # Perbarui daftar server_name Nginx + cache host→instance setiap domain berubah.
  def sync_edge
    InstanceHost.forget(hostname)
    NginxDomains.sync!
  rescue StandardError => e
    Rails.logger.warn("[Domain] sync_edge #{hostname}: #{e.class} #{e.message}")
  end

  # Buat zone + SSL + DNS. Idempoten: aman dipanggil ulang (mis. tombol "Coba lagi").
  def provision!(client = CloudflareClient.from_settings)
    ip = Setting.vps_ip
    raise CloudflareClient::Error, "IP VPS belum diisi di Pengaturan Situs" if ip.blank?
    zone = client.create_zone(hostname)
    update!(cf_zone_id: zone["id"], cf_nameservers: Array(zone["name_servers"]), cf_status: zone["status"], last_error: nil, last_checked_at: Time.current)
    client.set_ssl_mode(zone["id"], Setting.cloudflare_ssl_mode)
    client.set_always_https(zone["id"], on: true)
    client.upsert_dns(zone["id"], type: "A", name: "@", content: ip, proxied: true)
    client.upsert_dns(zone["id"], type: "CNAME", name: "www", content: hostname, proxied: true)
    refresh_status!(client, zone: zone)
    self
  rescue CloudflareClient::Error => e
    update_columns(status: Domain.statuses[:error], last_error: e.message.truncate(500), last_checked_at: Time.current)
    raise
  end

  # Cek apakah NS sudah diarahkan (zone status "active" di CF).
  def refresh_status!(client = CloudflareClient.from_settings, zone: nil)
    return self if cf_zone_id.blank?
    zone ||= client.zone(cf_zone_id)
    now_active = zone["status"] == "active"
    update!(cf_status: zone["status"], cf_nameservers: Array(zone["name_servers"]).presence || cf_nameservers,
            status: now_active ? :active : :pending_ns, activated_at: (now_active ? (activated_at || Time.current) : nil),
            last_checked_at: Time.current, last_error: nil)
    self
  rescue CloudflareClient::Error => e
    update_columns(last_error: e.message.truncate(500), last_checked_at: Time.current)
    self
  end

  # Semua negara/wilayah Asia (ISO 3166-1 alpha-2 => nama). Dipakai sebagai pilihan pembatasan akses.
  GEO_COUNTRIES = {
    "AF" => "Afghanistan", "AM" => "Armenia", "AZ" => "Azerbaijan", "BH" => "Bahrain", "BD" => "Bangladesh",
    "BT" => "Bhutan", "BN" => "Brunei", "KH" => "Kamboja", "CN" => "Tiongkok", "CY" => "Siprus",
    "GE" => "Georgia", "HK" => "Hong Kong", "IN" => "India", "ID" => "Indonesia", "IR" => "Iran",
    "IQ" => "Irak", "IL" => "Israel", "JP" => "Jepang", "JO" => "Yordania", "KZ" => "Kazakhstan",
    "KW" => "Kuwait", "KG" => "Kirgistan", "LA" => "Laos", "LB" => "Lebanon", "MO" => "Makau",
    "MY" => "Malaysia", "MV" => "Maladewa", "MN" => "Mongolia", "MM" => "Myanmar", "NP" => "Nepal",
    "KP" => "Korea Utara", "OM" => "Oman", "PK" => "Pakistan", "PS" => "Palestina", "PH" => "Filipina",
    "QA" => "Qatar", "SA" => "Arab Saudi", "SG" => "Singapura", "KR" => "Korea Selatan", "LK" => "Sri Lanka",
    "SY" => "Suriah", "TW" => "Taiwan", "TJ" => "Tajikistan", "TH" => "Thailand", "TL" => "Timor Leste",
    "TR" => "Turki", "TM" => "Turkmenistan", "AE" => "Uni Emirat Arab", "UZ" => "Uzbekistan", "VN" => "Vietnam",
    "YE" => "Yaman"
  }.freeze
  GEO_ASIA = GEO_COUNTRIES.keys.freeze

  # "ID,MY" / ["ID", "MY"] / "ID" → ["ID", "MY"] (huruf besar, unik, urut sesuai daftar).
  def self.parse_geo(value)
    codes = Array(value).flat_map { |v| v.to_s.split(/[,\s]+/) }.map(&:upcase).reject(&:blank?).uniq
    [ codes & GEO_ASIA, codes - GEO_ASIA ] # [dikenal, tidak dikenal]
  end

  # Ringkasan untuk UI: satu negara → namanya; semua Asia → "Semua Asia"; selain itu → "N negara Asia".
  def self.geo_summary(codes)
    codes = Array(codes)
    return GEO_COUNTRIES[codes.first] || codes.first if codes.size == 1
    return I18n.t("admin.domains.geo_all_asia") if codes.size == GEO_ASIA.size
    I18n.t("admin.domains.geo_n_countries", n: codes.size)
  end

  def geo_restricted? = geo_country.present?
  def geo_codes = geo_country.to_s.split(",").map(&:strip).reject(&:blank?)

  # Batasi akses situs publik ke satu/banyak negara lewat WAF Cloudflare (kosong/nil = buka untuk semua negara).
  def set_geo!(countries, client = CloudflareClient.from_settings)
    raise CloudflareClient::Error, "Zone Cloudflare belum ada" if cf_zone_id.blank?
    codes = self.class.parse_geo(countries).first
    if codes.any?
      rs_id = client.set_geo_allow_only(cf_zone_id, codes)
      update!(geo_country: codes.join(","), cf_geo_ruleset_id: rs_id, last_error: nil)
    else
      client.clear_geo(cf_zone_id)
      update!(geo_country: nil, cf_geo_ruleset_id: nil, last_error: nil)
    end
    self
  rescue CloudflareClient::Error => e
    update_columns(last_error: "Geo: #{e.message}".truncate(500), last_checked_at: Time.current)
    raise
  end

  # Hapus zone di CF (opsional) lalu record lokal.
  def deprovision!(client = CloudflareClient.from_settings, delete_zone: true)
    client.delete_zone(cf_zone_id) if delete_zone && cf_zone_id.present? && client.configured?
  rescue CloudflareClient::Error
    nil
  ensure
    destroy
  end
end
